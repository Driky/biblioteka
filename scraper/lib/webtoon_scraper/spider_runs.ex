defmodule WebtoonScraper.SpiderRuns do
  @moduledoc """
  Context module for tracking spider runs.
  Provides functions to create, update, and complete spider runs.
  Uses ETS to store the current run ID per spider for access during crawl.
  """

  import Ecto.Query

  alias WebtoonShared.Repo
  alias WebtoonShared.Schema.{SpiderRun, SpiderRunError}

  @ets_table :spider_run_tracking

  def init_ets do
    if :ets.whereis(@ets_table) == :undefined do
      :ets.new(@ets_table, [:named_table, :public, :set])
    end
  end

  @doc """
  Creates a new spider run and stores it for the given spider name.
  Returns {:ok, run} or {:error, changeset}.
  """
  def start_run(spider_name, crawl_id \\ nil) do
    init_ets()

    result =
      %SpiderRun{}
      |> SpiderRun.changeset(%{
        spider_name: spider_name,
        crawl_id: crawl_id,
        status: "running",
        started_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()

    case result do
      {:ok, run} ->
        :ets.insert(@ets_table, {spider_name, run.id})
        # Also update spider config last_run_at
        update_config_last_run(spider_name)
        {:ok, run}

      error ->
        error
    end
  end

  @doc """
  Gets the current run ID for a spider name from ETS.
  """
  def get_current_run_id(spider_name) do
    init_ets()

    case :ets.lookup(@ets_table, spider_name) do
      [{^spider_name, run_id}] -> run_id
      [] -> nil
    end
  end

  @doc """
  Updates the chapters_found count for a run.
  """
  def update_chapters_found(run_id, count) do
    SpiderRun
    |> Repo.get(run_id)
    |> case do
      nil -> {:error, :not_found}
      run -> run |> SpiderRun.changeset(%{chapters_found: count}) |> Repo.update()
    end
  end

  @doc """
  Increments chapters_processed and images_downloaded for a run.
  Called by ChapterWorker after successful processing.
  """
  def increment_stats(run_id, chapters \\ 1, images \\ 0) do
    from(r in SpiderRun,
      where: r.id == ^run_id,
      update: [
        inc: [chapters_processed: ^chapters, images_downloaded: ^images]
      ]
    )
    |> Repo.update_all([])
  end

  @doc """
  Increments the error count for a run.
  """
  def increment_errors(run_id, count \\ 1) do
    from(r in SpiderRun,
      where: r.id == ^run_id,
      update: [inc: [errors_count: ^count]]
    )
    |> Repo.update_all([])
  end

  @doc """
  Completes a spider run with the given status.
  Removes the run from ETS tracking.
  """
  def complete_run(spider_name, status \\ "completed") do
    init_ets()

    case get_current_run_id(spider_name) do
      nil ->
        {:error, :no_active_run}

      run_id ->
        :ets.delete(@ets_table, spider_name)

        SpiderRun
        |> Repo.get(run_id)
        |> case do
          nil ->
            {:error, :not_found}

          run ->
            run
            |> SpiderRun.changeset(%{
              status: status,
              completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })
            |> Repo.update()
        end
    end
  end

  @doc """
  Records an error for a spider run.
  """
  def record_error(run_id, attrs) do
    %SpiderRunError{}
    |> SpiderRunError.changeset(
      Map.merge(attrs, %{
        spider_run_id: run_id,
        occurred_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    )
    |> Repo.insert()
    |> case do
      {:ok, _error} ->
        increment_errors(run_id)
        :ok

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Gets the spider config for a given spider name.
  Returns default values if no config exists.
  """
  def get_config(spider_name) do
    alias WebtoonShared.Schema.SpiderConfig

    case Repo.get_by(SpiderConfig, spider_name: spider_name) do
      nil ->
        %{
          enabled: true,
          max_chapters_per_run: Application.get_env(:webtoon_scraper, :max_chapters_per_run, 10),
          request_delay_ms: 1000
        }

      config ->
        %{
          enabled: config.enabled,
          max_chapters_per_run: config.max_chapters_per_run,
          request_delay_ms: config.request_delay_ms
        }
    end
  end

  @doc """
  Checks if a spider is enabled.
  """
  def spider_enabled?(spider_name) do
    get_config(spider_name).enabled
  end

  defp update_config_last_run(spider_name) do
    alias WebtoonShared.Schema.SpiderConfig

    case Repo.get_by(SpiderConfig, spider_name: spider_name) do
      nil ->
        # Create config if it doesn't exist
        %SpiderConfig{}
        |> SpiderConfig.changeset(%{
          spider_name: spider_name,
          last_run_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      config ->
        config
        |> SpiderConfig.changeset(%{
          last_run_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()
    end
  end
end
