defmodule WebtoonScraper.Spiders.MangaDex do
  @moduledoc """
  Spider for scraping webtoons from MangaDex.

  Note: MangaDex has an API that should be used instead of scraping.
  This is an example implementation - adjust selectors as needed.
  """

  use WebtoonScraper.Spiders.Base

  @impl WebtoonScraper.Spiders.Base
  def site_id, do: "mangadex"

  @impl Crawly.Spider
  def base_url, do: "https://mangadex.org"

  @impl WebtoonScraper.Spiders.Base
  def parse_chapter_list(response) do
    {:ok, document} = Floki.parse_document(response.body)

    # MangaDex chapter list parsing
    # Note: Selectors may need adjustment based on actual page structure
    document
    |> Floki.find("[data-chapter]")
    |> Enum.map(fn el ->
      %{
        chapter_number: extract_chapter_number(el),
        title: extract_title(el),
        url: extract_chapter_url(el)
      }
    end)
    |> Enum.filter(fn ch -> ch.url != nil end)
  end

  @impl WebtoonScraper.Spiders.Base
  def parse_chapter_images(response) do
    {:ok, document} = Floki.parse_document(response.body)

    # Extract image URLs from reader page
    # Note: Selectors may need adjustment based on actual page structure
    document
    |> Floki.find(".reader-image img, [data-page] img")
    |> Floki.attribute("src")
    |> Enum.filter(&valid_image_url?/1)
  end

  @impl WebtoonScraper.Spiders.Base
  def image_headers(_url) do
    [
      {"Referer", base_url()},
      {"Accept", "image/webp,image/apng,image/*,*/*;q=0.8"}
    ]
  end

  # Private helpers

  defp extract_chapter_number(element) do
    # Try to extract from data attribute first
    case Floki.attribute(element, "data-chapter") do
      [num] when num != "" ->
        parse_number(num)

      _ ->
        # Fall back to text content
        element
        |> Floki.find(".chapter-number, .ch-num")
        |> Floki.text()
        |> parse_number()
    end
  end

  defp extract_title(element) do
    element
    |> Floki.find(".chapter-title, .ch-title")
    |> Floki.text()
    |> String.trim()
    |> case do
      "" -> nil
      title -> title
    end
  end

  defp extract_chapter_url(element) do
    case Floki.attribute(element, "href") do
      [href] -> make_absolute_url(href)
      _ -> nil
    end
  end

  defp parse_number(text) when is_binary(text) do
    text
    |> String.trim()
    |> String.replace(~r/[^\d.]/, "")
    |> case do
      "" -> Decimal.new(0)
      num -> Decimal.new(num)
    end
  end

  defp parse_number(_), do: Decimal.new(0)

  defp make_absolute_url(href) do
    cond do
      String.starts_with?(href, "http") -> href
      String.starts_with?(href, "/") -> base_url() <> href
      true -> nil
    end
  end

  defp valid_image_url?(url) do
    is_binary(url) && String.match?(url, ~r/\.(jpg|jpeg|png|gif|webp)/i)
  end
end
