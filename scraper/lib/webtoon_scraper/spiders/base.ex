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

  @doc "Returns the site identifier (must match webtoon_sources.site_id)"
  @callback site_id() :: String.t()

  @doc "Returns the base URL for the site"
  @callback base_url() :: String.t()

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

      @impl Crawly.Spider
      def base_url do
        __MODULE__.base_url()
      end

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
        source = WebtoonScraper.Sources.get_by_url(response.request_url)

        cond do
          is_nil(source) ->
            Logger.warning("No source found for URL: #{response.request_url}")
            %Crawly.ParsedItem{items: [], requests: []}

          is_chapter_page?(response) ->
            parse_chapter_page(response)

          true ->
            parse_webtoon_page(response, source)
        end
      end

      defp is_chapter_page?(response) do
        Map.has_key?(response.request.metadata || %{}, :chapter_number)
      end

      defp parse_webtoon_page(response, source) do
        last_scraped = source.last_chapter_scraped || Decimal.new(0)

        # Parse chapter list from page
        chapters = parse_chapter_list(response)

        Logger.info(
          "Found #{length(chapters)} chapters for #{source.webtoon && source.webtoon.title || source.source_url}"
        )

        # Filter to only new chapters (chapter_number > last_scraped)
        new_chapters =
          chapters
          |> Enum.filter(fn ch ->
            ch_num = to_decimal(ch.chapter_number)
            Decimal.compare(ch_num, last_scraped) == :gt
          end)
          |> Enum.sort_by(& &1.chapter_number)

        Logger.info("#{length(new_chapters)} new chapters to scrape")

        # Mark source as checked even if no new chapters
        if Enum.empty?(new_chapters) do
          WebtoonScraper.Sources.touch_last_checked(source.id)
        end

        # Generate requests for new chapter pages
        requests =
          Enum.map(new_chapters, fn ch ->
            request = Crawly.Utils.request_from_url(ch.url)

            %{
              request
              | metadata: %{
                  source_id: source.id,
                  webtoon_id: source.webtoon_id,
                  webtoon_slug: source.webtoon && source.webtoon.slug,
                  chapter_number: to_decimal(ch.chapter_number),
                  chapter_title: ch.title,
                  source_url: ch.url
                }
            }
          end)

        %Crawly.ParsedItem{items: [], requests: requests}
      end

      defp parse_chapter_page(response) do
        metadata = response.request.metadata

        Logger.info(
          "Parsing chapter #{metadata.chapter_number} images from #{response.request_url}"
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

        Logger.info("Found #{length(images)} images in chapter #{metadata.chapter_number}")

        # Create single item for the chapter with all images
        item = %{
          type: :chapter,
          webtoon_id: metadata.webtoon_id,
          webtoon_slug: metadata.webtoon_slug,
          source_id: metadata.source_id,
          chapter_number: metadata.chapter_number,
          chapter_title: metadata.chapter_title,
          source_url: metadata.source_url,
          images: images
        }

        %Crawly.ParsedItem{items: [item], requests: []}
      end

      defp get_image_headers(url) do
        if function_exported?(__MODULE__, :image_headers, 1) do
          __MODULE__.image_headers(url)
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
