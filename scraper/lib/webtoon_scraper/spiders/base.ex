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
        options = response.request.options || []
        Keyword.has_key?(options, :chapter_number)
      end

      defp parse_webtoon_page(response, source) do
        # Default to -1 so that chapter 0 is included on first run
        last_scraped = source.last_chapter_scraped || Decimal.new(-1)
        max_chapters = Application.get_env(:webtoon_scraper, :max_chapters_per_run, 20)

        # Parse chapter list from page
        chapters = parse_chapter_list(response)

        Logger.info(
          "Found #{length(chapters)} chapters for #{source.webtoon && source.webtoon.title || source.source_url}"
        )

        # Try to extract cover image if the callback is implemented
        cover_item = extract_cover_image(response, source)

        # Filter to only new chapters (chapter_number > last_scraped)
        # For new sources, last_scraped is -1 so chapter 0 is included
        # Sort by chapter number ascending and take only max_chapters_per_run
        new_chapters =
          chapters
          |> Enum.filter(fn ch ->
            ch_num = to_decimal(ch.chapter_number)
            Decimal.compare(ch_num, last_scraped) == :gt
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

        # Mark source as checked even if no new chapters
        if Enum.empty?(new_chapters) do
          WebtoonScraper.Sources.touch_last_checked(source.id)
        end

        # Generate requests for new chapter pages
        requests =
          Enum.map(new_chapters, fn ch ->
            request = Crawly.Utils.request_from_url(ch.url)

            # Store chapter metadata in the options field
            chapter_options = [
              source_id: source.id,
              webtoon_id: source.webtoon_id,
              webtoon_slug: source.webtoon && source.webtoon.slug,
              chapter_number: to_decimal(ch.chapter_number),
              chapter_title: ch.title,
              source_url: ch.url
            ]

            %{request | options: chapter_options}
          end)

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
        # Get chapter metadata from request options
        opts = response.request.options || []
        chapter_number = Keyword.get(opts, :chapter_number)
        chapter_title = Keyword.get(opts, :chapter_title)
        source_id = Keyword.get(opts, :source_id)
        webtoon_id = Keyword.get(opts, :webtoon_id)
        webtoon_slug = Keyword.get(opts, :webtoon_slug)
        source_url = Keyword.get(opts, :source_url)

        Logger.info(
          "Parsing chapter #{chapter_number} images from #{response.request_url}"
        )

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

      # Allow override
      defoverridable init: 0
    end
  end
end
