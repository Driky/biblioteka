defmodule WebtoonScraper.Spiders.Base do
  @moduledoc """
  Base spider module that handles common logic for webtoon scraping.
  Site-specific spiders should use this module and implement the callbacks.
  """

  @type chapter_info :: %{
          chapter_number: Decimal.t() | float() | integer(),
          title: String.t() | nil,
          url: String.t()
        }

  @type image_info :: %{
          url: String.t(),
          headers: [{String.t(), String.t()}]
        }

  @type cover_info :: %{
          url: String.t(),
          headers: [{String.t(), String.t()}]
        }

  @doc "Returns the site identifier (must match webtoon_sources.site_id)"
  @callback site_id() :: String.t()

  # Note: base_url/0 is defined by Crawly.Spider, so spiders should implement it directly

  @doc "Parses the chapter list from the webtoon page response"
  @callback parse_chapter_list(response :: map()) :: [chapter_info()]

  @doc "Parses image URLs from a chapter page response"
  @callback parse_chapter_images(response :: map()) :: [image_info()] | [String.t()]

  @doc "Optional: Returns custom headers for image downloads"
  @callback image_headers(image_url :: String.t()) :: [{String.t(), String.t()}]

  @optional_callbacks [image_headers: 1]

  defmacro __using__(_opts) do
    quote do
      use Crawly.Spider
      @behaviour WebtoonScraper.Spiders.Base

      require Logger

      # Each spider must implement base_url/0 for Crawly.Spider

      @impl Crawly.Spider
      def init do
        sources = WebtoonScraper.Sources.get_enabled_sources(site_id())

        if Enum.empty?(sources) do
          Logger.warning("No enabled sources found for #{site_id()}")
        end

        start_urls = Enum.map(sources, & &1.source_url)
        [start_urls: start_urls]
      end

      @impl Crawly.Spider
      def parse_item(response) do
        # Spider only handles webtoon pages - chapter processing is done by Oban jobs
        source = WebtoonScraper.Sources.get_by_url(response.request_url)

        if is_nil(source) do
          Logger.warning("No source found for URL: #{response.request_url}")
          %Crawly.ParsedItem{items: [], requests: []}
        else
          parse_webtoon_page(response, source)
        end
      end

      defp parse_webtoon_page(response, source) do
        # Get max chapters from spider config (database) or fall back to app config
        config = WebtoonScraper.SpiderRuns.get_config(site_id())
        max_chapters = config.max_chapters_per_run

        # Parse chapter list from page
        chapters = parse_chapter_list(response)

        Logger.info(
          "Found #{length(chapters)} chapters for #{source.webtoon && source.webtoon.title || source.source_url}"
        )

        # Try to extract cover image if the callback is implemented
        cover_item = extract_cover_image(response, source)

        # Get already scraped chapters from DB (more reliable than tracking last_scraped)
        # This handles gaps from failed scrapes - missing chapters will be retried
        scraped_chapters = WebtoonScraper.Sources.get_scraped_chapter_numbers(source.webtoon_id)

        Logger.debug("Already scraped #{MapSet.size(scraped_chapters)} chapters")

        # Filter to chapters NOT already in DB, sort ascending, take max_chapters
        new_chapters =
          chapters
          |> Enum.reject(fn ch ->
            ch_num = to_decimal(ch.chapter_number)
            MapSet.member?(scraped_chapters, ch_num)
          end)
          |> Enum.sort_by(&to_decimal(&1.chapter_number))
          |> Enum.take(max_chapters)

        chapter_numbers =
          new_chapters
          |> Enum.map(&to_decimal(&1.chapter_number))
          |> Enum.map(&Decimal.to_string/1)
          |> Enum.join(", ")

        Logger.info(
          "#{length(new_chapters)} new chapters to scrape (max #{max_chapters} per run): [#{chapter_numbers}]"
        )

        # Update chapters_found in the spider run record
        if length(new_chapters) > 0 do
          case WebtoonScraper.SpiderRuns.get_current_run_id(site_id()) do
            nil ->
              Logger.warning("No active run found for #{site_id()}, cannot update chapters_found")

            run_id ->
              WebtoonScraper.SpiderRuns.update_chapters_found(run_id, length(new_chapters))
              Logger.debug("Updated chapters_found=#{length(new_chapters)} for run #{run_id}")
          end
        end

        # Mark source as checked even if no new chapters
        if Enum.empty?(new_chapters) do
          WebtoonScraper.Sources.touch_last_checked(source.id)
        end

        # Get spider run ID for job tracking
        spider_run_id = WebtoonScraper.SpiderRuns.get_current_run_id(site_id())

        # Create Oban jobs for each chapter instead of Crawly requests
        # This ensures reliable processing - jobs persist in DB and survive restarts
        Enum.each(new_chapters, fn ch ->
          job_args = %{
            spider_module: to_string(__MODULE__),
            chapter_url: ch.url,
            webtoon_id: source.webtoon_id,
            webtoon_slug: source.webtoon && source.webtoon.slug,
            source_id: source.id,
            chapter_number: Decimal.to_string(to_decimal(ch.chapter_number)),
            chapter_title: ch.title,
            spider_run_id: spider_run_id
          }

          case WebtoonScraper.Workers.ChapterFetchWorker.new(job_args) |> Oban.insert() do
            {:ok, job} ->
              Logger.info("Enqueued chapter #{ch.chapter_number} as Oban job #{job.id}")

            {:error, reason} ->
              Logger.error("Failed to enqueue chapter #{ch.chapter_number}: #{inspect(reason)}")
          end
        end)

        # Include cover item if we found one and webtoon doesn't have a cover yet
        # No requests - chapter processing is handled by Oban jobs
        items = if cover_item, do: [cover_item], else: []

        %Crawly.ParsedItem{items: items, requests: []}
      end

      defp extract_cover_image(response, source) do
        # Skip if webtoon already has a cover
        if source.webtoon && source.webtoon.cover_url do
          Logger.debug("Webtoon already has cover, skipping cover extraction")
          nil
        else
          # Use apply/3 to avoid compile-time warning about undefined function
          if function_exported?(__MODULE__, :parse_cover_image, 1) do
            case apply(__MODULE__, :parse_cover_image, [response]) do
              nil ->
                nil

              %{url: url, headers: headers} when is_binary(url) ->
                Logger.info("Found cover image: #{url}")
                %{
                  type: :cover,
                  webtoon_id: source.webtoon_id,
                  webtoon_slug: source.webtoon && source.webtoon.slug,
                  source_id: source.id,
                  url: url,
                  headers: headers
                }

              url when is_binary(url) ->
                Logger.info("Found cover image: #{url}")
                %{
                  type: :cover,
                  webtoon_id: source.webtoon_id,
                  webtoon_slug: source.webtoon && source.webtoon.slug,
                  source_id: source.id,
                  url: url,
                  headers: get_image_headers(url)
                }

              _ ->
                nil
            end
          else
            nil
          end
        end
      end

      defp get_image_headers(url) do
        # Use apply/3 to avoid compile-time warning about undefined function
        if function_exported?(__MODULE__, :image_headers, 1) do
          apply(__MODULE__, :image_headers, [url])
        else
          [{"Referer", base_url()}]
        end
      end

      defp to_decimal(value) when is_float(value), do: Decimal.from_float(value)
      defp to_decimal(value) when is_integer(value), do: Decimal.new(value)
      defp to_decimal(%Decimal{} = value), do: value

      defp to_decimal(value) when is_binary(value) do
        case Decimal.parse(value) do
          {decimal, _} -> decimal
          :error -> Decimal.new(0)
        end
      end

      # Allow override
      defoverridable init: 0
    end
  end
end
