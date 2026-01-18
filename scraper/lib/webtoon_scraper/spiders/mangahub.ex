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
    {:ok, document} = Floki.parse_document(response.body)

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
  end

  @impl WebtoonScraper.Spiders.Base
  def parse_chapter_list(response) do
    {:ok, document} = Floki.parse_document(response.body)

    # Chapters are in: li._287KE.list-group-item
    # Each contains a link with class _3pfyN
    document
    |> Floki.find("li._287KE.list-group-item")
    |> Enum.map(&parse_chapter_item/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.chapter_number)
  end

  @impl WebtoonScraper.Spiders.Base
  def parse_chapter_images(response) do
    {:ok, document} = Floki.parse_document(response.body)

    # MangaHub reader typically uses img tags within a reader container
    # Common selectors for manga reader pages
    images =
      document
      |> Floki.find("img.PB0mN, img[src*='imghub'], .reader-content img, #images img")
      |> Floki.attribute("src")
      |> Enum.filter(&valid_image_url?/1)

    # If no images found with specific selectors, try a broader search
    if Enum.empty?(images) do
      document
      |> Floki.find("img")
      |> Floki.attribute("src")
      |> Enum.filter(&is_chapter_image?/1)
    else
      images
    end
  end

  @impl WebtoonScraper.Spiders.Base
  def image_headers(_url) do
    [
      {"Referer", base_url()},
      {"Accept", "image/webp,image/apng,image/*,*/*;q=0.8"},
      {"User-Agent",
       "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"}
    ]
  end

  # Private helpers

  defp parse_chapter_item(element) do
    # Find the primary chapter link (class _3pfyN)
    case Floki.find(element, "a._3pfyN") |> List.first() do
      nil ->
        nil

      link_element ->
        url = Floki.attribute(link_element, "href") |> List.first()
        chapter_number = extract_chapter_number(link_element)
        title = extract_chapter_title(link_element)

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
end
