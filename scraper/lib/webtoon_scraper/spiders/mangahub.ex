defmodule WebtoonScraper.Spiders.MangaHub do
  @moduledoc """
  Spider for scraping webtoons from MangaHub (mangahub.io).

  Supports:
  - Cover image extraction from title page
  - Chapter list parsing with proper number extraction
  - Chapter image extraction from reader pages
  """

  use WebtoonScraper.Spiders.Base

  @impl WebtoonScraper.Spiders.Base
  def site_id, do: "mangahub"

  @impl Crawly.Spider
  def base_url, do: "https://mangahub.io"

  # Optional: extracts cover image from the webtoon page
  def parse_cover_image(response) do
    case parse_body(response.body) do
      {:ok, document} ->
        # Cover is in: <section class="_2fecr" style="background-image:url("...")">
        # Located within #mangadetail
        document
        |> Floki.find("#mangadetail section._2fecr")
        |> Floki.attribute("style")
        |> List.first()
        |> extract_background_image_url()
        |> case do
          nil -> nil
          url -> %{url: url, headers: image_headers(url)}
        end

      {:error, _} ->
        nil
    end
  end

  @impl WebtoonScraper.Spiders.Base
  def parse_chapter_list(response) do
    case parse_body(response.body) do
      {:ok, document} ->
        # Debug: log page title and body snippet to help diagnose issues
        title = document |> Floki.find("title") |> Floki.text()
        body_preview = String.slice(response.body || "", 0, 500)
        Logger.debug("Page title: #{title}")
        Logger.debug("Body preview: #{body_preview}")

        # Chapters are in: li._287KE.list-group-item
        # Each contains a link with class _3pfyN
        chapters =
          document
          |> Floki.find("li._287KE.list-group-item")
          |> Enum.map(&parse_chapter_item/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq_by(& &1.chapter_number)

        if Enum.empty?(chapters) do
          Logger.warning("No chapters found. Checking for common issues...")
          # Check for Cloudflare challenge
          if String.contains?(response.body || "", "cf-browser-verification") do
            Logger.error("Cloudflare challenge detected - browser verification required")
          end
          # Check for rate limiting
          if String.contains?(response.body || "", "rate limit") do
            Logger.error("Rate limiting detected")
          end
          # Log selector debug info
          all_lis = document |> Floki.find("li") |> length()
          Logger.debug("Total <li> elements on page: #{all_lis}")
        end

        chapters

      {:error, reason} ->
        Logger.error("Failed to parse chapter list: #{inspect(reason)}")
        []
    end
  end

  @impl WebtoonScraper.Spiders.Base
  def parse_chapter_images(response) do
    case parse_body(response.body) do
      {:error, reason} ->
        Logger.error("Failed to parse chapter images: #{inspect(reason)}")
        []

      {:ok, document} ->
        # Debug: log page title and body snippet
        title = document |> Floki.find("title") |> Floki.text()
        body_preview = String.slice(response.body || "", 0, 500)
        Logger.debug("Chapter page title: #{title}")
        Logger.debug("Chapter body preview: #{body_preview}")

        # Extract expected image count from page indicator (e.g., "1/25")
        expected_count = extract_expected_image_count(document)
        Logger.debug("Expected image count from page: #{inspect(expected_count)}")

        # MangaHub reader typically uses img tags within a reader container
        # Common selectors for manga reader pages
        images =
          document
          |> Floki.find("img.PB0mN, img[src*='imghub'], .reader-content img, #images img")
          |> Floki.attribute("src")
          |> Enum.filter(&valid_image_url?/1)

        # If no images found with src, try data-src (lazy loading fallback)
        images =
          if Enum.empty?(images) do
            Logger.debug("No images found with src, trying data-src attribute")
            document
            |> Floki.find("img.PB0mN, img[data-src*='imghub'], .reader-content img, #images img")
            |> Floki.attribute("data-src")
            |> Enum.filter(&valid_image_url?/1)
          else
            images
          end

        # If still no images, try a broader search with both src and data-src
        images =
          if Enum.empty?(images) do
            Logger.debug("Trying broader img search")
            src_images =
              document
              |> Floki.find("img")
              |> Floki.attribute("src")
              |> Enum.filter(&is_chapter_image?/1)

            if Enum.empty?(src_images) do
              document
              |> Floki.find("img")
              |> Floki.attribute("data-src")
              |> Enum.filter(&is_chapter_image?/1)
            else
              src_images
            end
          else
            images
          end

        Logger.debug("Found #{length(images)} chapter images")

        # Log warning if we got fewer images than expected
        if expected_count && length(images) < expected_count do
          Logger.warning(
            "Found #{length(images)} images but expected #{expected_count}. " <>
              "Some images may not have loaded (lazy loading issue)."
          )
        end

        images
    end
  end

  @impl WebtoonScraper.Spiders.Base
  def image_headers(_url) do
    [
      {"Referer", base_url()},
      {"Accept", "image/webp,image/apng,image/*,*/*;q=0.8"},
      {"User-Agent",
       "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:134.0) Gecko/20100101 Firefox/134.0"}
    ]
  end

  # Private helpers

  defp parse_body(nil) do
    {:error, :nil_body}
  end

  defp parse_body("") do
    {:error, :empty_body}
  end

  defp parse_body(body) when is_binary(body) do
    Floki.parse_document(body)
  end

  defp parse_chapter_item(element) do
    # Find the primary chapter link (class _3pfyN)
    case Floki.find(element, "a._3pfyN") |> List.first() do
      nil ->
        nil

      link_element ->
        url = Floki.attribute(link_element, "href") |> List.first()
        chapter_number = extract_chapter_number(link_element)
        title = extract_chapter_title(link_element)

        # Log first few chapters for debugging
        if chapter_number && Decimal.lt?(chapter_number, Decimal.new(5)) do
          Logger.debug("Chapter #{chapter_number}: title='#{title}', url=#{url}")
        end

        if url && chapter_number do
          %{
            chapter_number: chapter_number,
            title: title,
            url: make_absolute_url(url)
          }
        else
          nil
        end
    end
  end

  defp extract_chapter_number(element) do
    # Chapter number is in span._3D1SJ, format: "#200" or "#200.5"
    element
    |> Floki.find("span._3D1SJ")
    |> Floki.text()
    |> String.replace(~r/[#\s]/, "")
    |> parse_number()
  end

  defp extract_chapter_title(element) do
    # Title is in span._2IG5P, format: " - Chapter Title"
    element
    |> Floki.find("span._2IG5P")
    |> Floki.text()
    |> String.trim()
    |> String.replace(~r/^[\s-]+/, "")
    |> case do
      "" -> nil
      title -> title
    end
  end

  defp extract_background_image_url(nil), do: nil

  defp extract_background_image_url(style) do
    # Parse: background-image:url("https://thumb.mghcdn.com/mh/solo-leveling.jpg")
    case Regex.run(~r/background-image:\s*url\(['""]?([^'""]+)['""]?\)/, style) do
      [_, url] -> url
      _ -> nil
    end
  end

  defp parse_number(text) when is_binary(text) do
    text
    |> String.trim()
    |> case do
      "" ->
        nil

      num_str ->
        case Decimal.parse(num_str) do
          {decimal, _} -> decimal
          :error -> nil
        end
    end
  end

  defp parse_number(_), do: nil

  defp make_absolute_url(nil), do: nil

  defp make_absolute_url(href) do
    cond do
      String.starts_with?(href, "http") -> href
      String.starts_with?(href, "//") -> "https:" <> href
      String.starts_with?(href, "/") -> base_url() <> href
      true -> base_url() <> "/" <> href
    end
  end

  defp valid_image_url?(url) do
    is_binary(url) &&
      String.match?(url, ~r/\.(jpg|jpeg|png|gif|webp)/i) &&
      not String.contains?(url, "avatar") &&
      not String.contains?(url, "logo") &&
      not String.contains?(url, "icon")
  end

  defp is_chapter_image?(url) do
    is_binary(url) &&
      (String.contains?(url, "imghub") ||
         String.contains?(url, "mghcdn") ||
         String.contains?(url, "chapter")) &&
      valid_image_url?(url)
  end

  defp extract_expected_image_count(document) do
    # MangaHub shows page indicator like "1/25" in <p class="_3w1ww">
    # Use List.first to avoid concatenating text from multiple page indicator elements
    # (which was causing 10x inflated counts like "392" instead of "39")
    document
    |> Floki.find("p._3w1ww")
    |> List.first()
    |> case do
      nil -> nil
      element -> element |> Floki.text() |> parse_page_indicator()
    end
  end

  defp parse_page_indicator(text) when is_binary(text) do
    case Regex.run(~r/(\d+)\s*\/\s*(\d+)/, text) do
      [_, _current, total] ->
        case Integer.parse(total) do
          {n, _} -> n
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_page_indicator(_), do: nil
end
