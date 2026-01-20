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
      %{type: :chapter, images: [_ | _] = _images} ->
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
            # Convert header tuples to map for JSON serialization
            headers: Map.new(img.headers || []),
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
        # or from state. Note: Crawly's state contains the module atom,
        # but we store runs by site_id string.
        spider_name_or_module =
          Map.get(state, :spider_name) ||
            get_spider_name_from_source(item.source_id)

        spider_name = normalize_spider_name(spider_name_or_module)

        Logger.debug("EnqueuePipeline: Looking up run for spider_name=#{inspect(spider_name)} (from #{inspect(spider_name_or_module)})")

        if spider_name do
          run_id = SpiderRuns.get_current_run_id(spider_name)
          Logger.debug("EnqueuePipeline: Found run_id=#{inspect(run_id)} for #{spider_name}")
          run_id
        else
          Logger.warning("EnqueuePipeline: Could not determine spider_name, no run tracking")
          nil
        end

      run_id ->
        run_id
    end
  end

  # Convert spider module atom to site_id string
  defp normalize_spider_name(nil), do: nil

  defp normalize_spider_name(spider_name) when is_binary(spider_name), do: spider_name

  defp normalize_spider_name(spider_module) when is_atom(spider_module) do
    # Ensure module is loaded before checking for exported functions
    Code.ensure_loaded!(spider_module)

    if function_exported?(spider_module, :site_id, 0) do
      spider_module.site_id()
    else
      # Fall back to deriving from module name
      spider_module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
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
