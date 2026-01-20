defmodule Webtoon.Admin do
  @moduledoc """
  Admin context for back-office operations.
  Provides queries and operations for managing webtoons, spiders, and runs.
  """

  import Ecto.Query

  alias WebtoonShared.Repo
  alias WebtoonShared.Schema.{Chapter, ChapterImage, Webtoon, WebtoonSource}
  alias WebtoonShared.Schema.{SpiderRun, SpiderRunError, SpiderConfig}

  # =============================================================================
  # Dashboard Stats
  # =============================================================================

  def get_dashboard_stats do
    webtoons_count = Repo.aggregate(Webtoon, :count)
    chapters_count = Repo.aggregate(Chapter, :count)
    images_count = Repo.aggregate(ChapterImage, :count)

    chapters_pending =
      Chapter
      |> where([c], c.needs_rescrape == true)
      |> Repo.aggregate(:count)

    chapters_needing_title =
      Chapter
      |> where([c], c.needs_title_rescrape == true)
      |> Repo.aggregate(:count)

    chapters_needing_images =
      Chapter
      |> where([c], c.needs_images_rescrape == true)
      |> Repo.aggregate(:count)

    # Errors in last 24 hours
    yesterday = DateTime.utc_now() |> DateTime.add(-24, :hour)

    errors_24h =
      SpiderRunError
      |> where([e], e.inserted_at >= ^yesterday)
      |> Repo.aggregate(:count)

    %{
      webtoons_count: webtoons_count,
      chapters_count: chapters_count,
      images_count: images_count,
      chapters_pending_rescrape: chapters_pending,
      chapters_needing_title: chapters_needing_title,
      chapters_needing_images: chapters_needing_images,
      errors_24h: errors_24h
    }
  end

  def get_recent_runs(limit \\ 10) do
    SpiderRun
    |> order_by([r], desc: r.started_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_active_oban_jobs_count do
    # Query Oban jobs table for active jobs
    try do
      from(j in "oban_jobs",
        where: j.state in ["available", "executing", "scheduled"],
        select: count()
      )
      |> Repo.one()
    rescue
      _ -> 0
    end
  end

  # =============================================================================
  # Webtoons
  # =============================================================================

  def list_webtoons do
    Webtoon
    |> preload([:sources])
    |> order_by([w], asc: w.title)
    |> Repo.all()
    |> Enum.map(fn webtoon ->
      stats = get_webtoon_stats(webtoon.id)
      Map.put(webtoon, :stats, stats)
    end)
  end

  def get_webtoon!(id) do
    Webtoon
    |> preload([:sources])
    |> Repo.get!(id)
  end

  def get_webtoon_stats(webtoon_id) do
    chapters_count =
      Chapter
      |> where([c], c.webtoon_id == ^webtoon_id)
      |> Repo.aggregate(:count)

    # Count chapters that have at least one image using distinct
    chapters_with_images =
      from(c in Chapter,
        where: c.webtoon_id == ^webtoon_id,
        join: i in assoc(c, :images),
        distinct: true,
        select: c.id
      )
      |> Repo.all()
      |> length()

    chapters_missing_title =
      Chapter
      |> where([c], c.webtoon_id == ^webtoon_id and is_nil(c.title))
      |> Repo.aggregate(:count)

    %{
      chapters_count: chapters_count,
      chapters_with_images: chapters_with_images,
      chapters_missing_title: chapters_missing_title
    }
  end

  def get_webtoon_chapters(webtoon_id, opts \\ []) do
    filter = Keyword.get(opts, :filter, :all)

    query =
      Chapter
      |> where([c], c.webtoon_id == ^webtoon_id)
      |> preload(:images)
      |> order_by([c], asc: c.chapter_number)

    query =
      case filter do
        :all -> query
        :missing_title -> where(query, [c], is_nil(c.title))
        :needs_rescrape -> where(query, [c], c.needs_rescrape == true)
        _ -> query
      end

    Repo.all(query)
  end

  def mark_chapters_for_rescrape(chapter_ids, rescrape_type) do
    updates =
      case rescrape_type do
        :full -> %{needs_rescrape: true}
        :title -> %{needs_title_rescrape: true}
        :images -> %{needs_images_rescrape: true}
      end

    Chapter
    |> where([c], c.id in ^chapter_ids)
    |> Repo.update_all(set: Map.to_list(updates))
  end

  def toggle_source_crawl(source_id, enabled) do
    source = Repo.get!(WebtoonSource, source_id)

    source
    |> WebtoonSource.changeset(%{crawl_enabled: enabled})
    |> Repo.update()
  end

  def create_webtoon(attrs) do
    %Webtoon{}
    |> Webtoon.changeset(attrs)
    |> Repo.insert()
  end

  def update_webtoon(webtoon, attrs) do
    webtoon
    |> Webtoon.changeset(attrs)
    |> Repo.update()
  end

  def add_source_to_webtoon(webtoon_id, source_attrs) do
    %WebtoonSource{}
    |> WebtoonSource.changeset(Map.put(source_attrs, :webtoon_id, webtoon_id))
    |> Repo.insert()
  end

  # =============================================================================
  # Spiders
  # =============================================================================

  def list_spider_configs do
    SpiderConfig
    |> order_by([c], asc: c.spider_name)
    |> Repo.all()
  end

  def get_spider_config!(name) do
    case Repo.get_by(SpiderConfig, spider_name: name) do
      nil ->
        # Return default config if not found
        %SpiderConfig{
          spider_name: name,
          enabled: true,
          max_chapters_per_run: 10,
          request_delay_ms: 1000
        }

      config ->
        config
    end
  end

  def get_or_create_spider_config(name) do
    case Repo.get_by(SpiderConfig, spider_name: name) do
      nil ->
        %SpiderConfig{}
        |> SpiderConfig.changeset(%{spider_name: name})
        |> Repo.insert!()

      config ->
        config
    end
  end

  def update_spider_config(config, attrs) do
    config
    |> SpiderConfig.changeset(attrs)
    |> Repo.update()
  end

  def toggle_spider(name, enabled) do
    config = get_or_create_spider_config(name)
    update_spider_config(config, %{enabled: enabled})
  end

  # =============================================================================
  # Runs
  # =============================================================================

  def list_runs(opts \\ []) do
    spider_name = Keyword.get(opts, :spider_name)
    status = Keyword.get(opts, :status)
    limit = Keyword.get(opts, :limit, 50)

    query =
      SpiderRun
      |> order_by([r], desc: r.started_at)
      |> limit(^limit)

    query =
      if spider_name do
        where(query, [r], r.spider_name == ^spider_name)
      else
        query
      end

    query =
      if status do
        where(query, [r], r.status == ^status)
      else
        query
      end

    Repo.all(query)
  end

  def get_run!(id) do
    SpiderRun
    |> preload(:errors)
    |> Repo.get!(id)
  end

  def get_run_errors(run_id) do
    SpiderRunError
    |> where([e], e.spider_run_id == ^run_id)
    |> preload(:webtoon)
    |> order_by([e], desc: e.occurred_at)
    |> Repo.all()
  end

  def create_spider_run(spider_name, crawl_id \\ nil) do
    %SpiderRun{}
    |> SpiderRun.changeset(%{
      spider_name: spider_name,
      crawl_id: crawl_id,
      status: "running",
      started_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert()
  end

  def complete_spider_run(run_id, status \\ "completed") do
    run = Repo.get!(SpiderRun, run_id)

    run
    |> SpiderRun.changeset(%{
      status: status,
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  def update_spider_run_stats(run_id, attrs) do
    run = Repo.get!(SpiderRun, run_id)
    run |> SpiderRun.changeset(attrs) |> Repo.update()
  end

  def record_spider_run_error(run_id, webtoon_id, chapter_number, error_type, message, stacktrace \\ nil) do
    %SpiderRunError{}
    |> SpiderRunError.changeset(%{
      spider_run_id: run_id,
      webtoon_id: webtoon_id,
      chapter_number: chapter_number,
      error_type: error_type,
      error_message: message,
      stacktrace: stacktrace,
      occurred_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.insert()
  end

  # =============================================================================
  # Known Spiders
  # =============================================================================

  @doc """
  Returns list of known spider names.
  In a real app, this might be dynamically discovered from modules.
  """
  def known_spiders do
    ["mangahub", "mangadex"]
  end
end
