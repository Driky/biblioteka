defmodule WebtoonScraper.Pipelines.Enqueue do
  @moduledoc """
  Pipeline that enqueues chapter processing as Oban jobs instead of
  processing synchronously. This prevents Crawly GenServer timeouts.

  Covers continue through the synchronous pipeline as they are single
  images and process quickly.
  """

  @behaviour Crawly.Pipeline

  require Logger

  alias WebtoonScraper.SpiderRuns

  @impl Crawly.Pipeline
  def run(item, state) do
    case item do
      %{type: :chapter, images: images} when length(images) > 0 ->
        enqueue_chapter_job(item, state)

      %{type: :cover} ->
        # Keep cover processing synchronous (it's just one image)
        {item, state}

      _ ->
        {item, state}
    end
  end

  defp enqueue_chapter_job(item, state) do
    # Get current spider run ID from ETS (set by spider init)
    # We derive the spider name from the source's site_id via the item
    spider_run_id = get_spider_run_id(item, state)

    job_args = %{
      webtoon_id: item.webtoon_id,
      webtoon_slug: item.webtoon_slug,
      source_id: item.source_id,
      chapter_number: Decimal.to_string(item.chapter_number),
      chapter_title: item.chapter_title,
      source_url: item.source_url,
      images:
        Enum.map(item.images, fn img ->
          %{
            url: img.url,
            headers: img.headers,
            sequence: img.sequence
          }
        end),
      spider_run_id: spider_run_id
    }

    case WebtoonScraper.Workers.ChapterWorker.new(job_args) |> Oban.insert() do
      {:ok, job} ->
        Logger.info("Enqueued chapter #{item.chapter_number} as Oban job #{job.id}")
        # Return false to stop further pipeline processing for this item
        {false, state}

      {:error, reason} ->
        Logger.error("Failed to enqueue chapter #{item.chapter_number}: #{inspect(reason)}")
        {false, state}
    end
  end

  defp get_spider_run_id(item, state) do
    # Try to get spider_run_id from state first (if set by pipeline init)
    case Map.get(state, :spider_run_id) do
      nil ->
        # Fall back to looking up by spider name from the item's source
        # or from state
        spider_name =
          Map.get(state, :spider_name) ||
            get_spider_name_from_source(item.source_id)

        if spider_name do
          SpiderRuns.get_current_run_id(spider_name)
        else
          nil
        end

      run_id ->
        run_id
    end
  end

  defp get_spider_name_from_source(nil), do: nil

  defp get_spider_name_from_source(source_id) do
    alias WebtoonShared.Schema.WebtoonSource
    alias WebtoonShared.Repo

    case Repo.get(WebtoonSource, source_id) do
      nil -> nil
      source -> source.site_id
    end
  end
end
