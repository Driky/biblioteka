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
        # Check if this is a chapter page first (has metadata in options)
        if is_chapter_page?(response) do
          parse_chapter_page(response)
        else
          # For webtoon pages, look up source by URL
          source = WebtoonScraper.Sources.get_by_url(response.request_url)

          if is_nil(source) do
            Logger.warning("No source found for URL: #{response.request_url}")
            %Crawly.ParsedItem{items: [], requests: []}
          else
            parse_webtoon_page(response, source)
          end
        end
      end

      defp is_chapter_page?(response) do
        # Check if this is a chapter page by looking at options in the request
        # Handle case where request or options might be nil
        options =
          case response do
            %{request: %{options: opts}} when is_list(opts) -> opts
            %{request: %Crawly.Request{options: opts}} when is_list(opts) -> opts
            _ -> []
          end

        has_chapter_option = Keyword.has_key?(options, :chapter_number)

        # Fallback: check URL pattern if options aren't available
        # (happens when using custom fetcher that doesn't preserve request)
        url = response.request_url || ""
        is_chapter_url = String.contains?(url, "/chapter/")

        has_chapter_option || is_chapter_url
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

        # Generate requests for new chapter pages
        # Reverse the list so that when Crawly processes LIFO, smallest chapters are handled first
        requests =
          new_chapters
          |> Enum.map(fn ch ->
            request = Crawly.Utils.request_from_url(ch.url)

            # Store chapter metadata in the options field
            # Enable scrolling for chapter pages (lazy-loaded images)
            chapter_options = [
              source_id: source.id,
              webtoon_id: source.webtoon_id,
              webtoon_slug: source.webtoon && source.webtoon.slug,
              chapter_number: to_decimal(ch.chapter_number),
              chapter_title: ch.title,
              source_url: ch.url,
              scroll: true
            ]

            Logger.debug("Creating request for chapter #{ch.chapter_number}: #{ch.url}")
            %{request | options: chapter_options}
          end)

        # Log the request order before and after reverse
        Logger.info("Request order before reverse: #{requests |> Enum.map(&Keyword.get(&1.options, :chapter_number)) |> Enum.map(&Decimal.to_string/1) |> Enum.join(", ")}")
        requests = Enum.reverse(requests)
        Logger.info("Request order after reverse (Crawly LIFO will process last first): #{requests |> Enum.map(&Keyword.get(&1.options, :chapter_number)) |> Enum.map(&Decimal.to_string/1) |> Enum.join(", ")}")

        # Include cover item if we found one and webtoon doesn't have a cover yet
        items = if cover_item, do: [cover_item], else: []

        %Crawly.ParsedItem{items: items, requests: requests}
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

      defp parse_chapter_page(response) do
        url = response.request_url || ""
        Logger.info(">>> parse_chapter_page called for URL: #{url}")

        # Try to get options from response.request first (standard Crawly way)
        # Fall back to ETS if not available
        opts =
          case response do
            %{request: %Crawly.Request{options: o}} when is_list(o) and o != [] -> o
            %{request: %{options: o}} when is_list(o) and o != [] -> o
            _ ->
              # Fallback to ETS storage
              WebtoonScraper.Fetchers.RenderServer.get_options(url)
          end

        # Extract chapter metadata from options
        chapter_number = Keyword.get(opts, :chapter_number) || extract_chapter_number_from_url(url)
        Logger.info(">>> Processing chapter #{inspect(chapter_number)} from URL: #{url}")
        chapter_title = Keyword.get(opts, :chapter_title)
        source_id = Keyword.get(opts, :source_id)
        webtoon_id = Keyword.get(opts, :webtoon_id)
        webtoon_slug = Keyword.get(opts, :webtoon_slug)
        source_url = Keyword.get(opts, :source_url) || url

        # If we don't have webtoon_id, try to look it up from the URL
        {webtoon_id, webtoon_slug, source_id} =
          if is_nil(webtoon_id) do
            lookup_webtoon_from_chapter_url(url)
          else
            {webtoon_id, webtoon_slug, source_id}
          end

        Logger.info(
          "Parsing chapter #{inspect(chapter_number)} images from #{url}"
        )
        Logger.debug("Chapter metadata - webtoon_id: #{inspect(webtoon_id)}, source_id: #{inspect(source_id)}, title: #{inspect(chapter_title)}")
        Logger.debug("Options keys: #{inspect(Keyword.keys(opts))}")

        # Parse images from page
        raw_images = parse_chapter_images(response)

        # Normalize image info
        images =
          raw_images
          |> Enum.with_index(1)
          |> Enum.map(fn {img, seq} ->
            {url, headers} =
              case img do
                %{url: url, headers: headers} -> {url, headers}
                url when is_binary(url) -> {url, get_image_headers(url)}
              end

            %{
              url: url,
              headers: headers,
              sequence: seq
            }
          end)

        Logger.info("Found #{length(images)} images in chapter #{chapter_number}")

        # Create single item for the chapter with all images
        item = %{
          type: :chapter,
          webtoon_id: webtoon_id,
          webtoon_slug: webtoon_slug,
          source_id: source_id,
          chapter_number: chapter_number,
          chapter_title: chapter_title,
          source_url: source_url,
          images: images
        }

        Logger.info(">>> Returning ParsedItem for chapter #{chapter_number} with #{length(images)} images")
        %Crawly.ParsedItem{items: [item], requests: []}
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

      # Extract chapter number from URL like /chapter/manga-name/chapter-123
      defp extract_chapter_number_from_url(url) when is_binary(url) do
        case Regex.run(~r/chapter[_-]?(\d+(?:\.\d+)?)/i, url) do
          [_, num_str] ->
            case Decimal.parse(num_str) do
              {decimal, _} -> decimal
              :error -> nil
            end

          _ ->
            nil
        end
      end

      defp extract_chapter_number_from_url(_), do: nil

      # Look up webtoon info from chapter URL by finding source with matching base URL
      defp lookup_webtoon_from_chapter_url(chapter_url) when is_binary(chapter_url) do
        # Extract the manga identifier from URL
        # e.g., /chapter/solo-leveling_105/chapter-4 -> solo-leveling_105
        case Regex.run(~r{/chapter/([^/]+)/}, chapter_url) do
          [_, manga_slug] ->
            # Try to find source by matching URL pattern
            import Ecto.Query

            source =
              WebtoonShared.Schema.WebtoonSource
              |> where([s], like(s.source_url, ^"%#{manga_slug}%"))
              |> preload(:webtoon)
              |> WebtoonShared.Repo.one()

            if source do
              Logger.debug("Found source for chapter URL: #{chapter_url} -> #{source.webtoon && source.webtoon.title}")
              {source.webtoon_id, source.webtoon && source.webtoon.slug, source.id}
            else
              Logger.warning("Could not find source for chapter URL: #{chapter_url}")
              {nil, nil, nil}
            end

          _ ->
            Logger.warning("Could not extract manga slug from URL: #{chapter_url}")
            {nil, nil, nil}
        end
      end

      defp lookup_webtoon_from_chapter_url(_), do: {nil, nil, nil}

      # Allow override
      defoverridable init: 0
    end
  end
end
