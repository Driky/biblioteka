defmodule WebtoonScraper.Pipelines.ImageProcessor do
  @moduledoc """
  Pipeline that downloads cover images.
  Chapter images are handled asynchronously by Oban ChapterWorker.
  """

  @behaviour Crawly.Pipeline

  require Logger

  @impl Crawly.Pipeline
  def run(item, state) do
    case item do
      # Chapters are handled asynchronously by Oban ChapterWorker
      %{type: :chapter} ->
        {item, state}

      %{type: :cover, url: url, headers: headers} ->
        process_cover_image(item, url, headers, state)

      _ ->
        {item, state}
    end
  end

  defp process_cover_image(item, url, headers, state) do
    Logger.info("Downloading cover image: #{url}")

    case download_single_image(url, headers) do
      {:ok, image_data} ->
        updated_item =
          item
          |> Map.put(:binary, image_data.binary)
          |> Map.put(:content_type, image_data.content_type)
          |> Map.put(:extension, image_data.extension)
          |> Map.put(:file_size, image_data.file_size)

        Logger.info("Cover image downloaded successfully (#{image_data.file_size} bytes)")
        {updated_item, state}

      {:error, reason} ->
        Logger.error("Failed to download cover image: #{inspect(reason)}")
        {false, state}
    end
  end

  defp download_single_image(url, headers) do
    req_headers =
      headers
      |> Enum.map(fn {k, v} -> {String.downcase(k), v} end)

    case Req.get(url, headers: req_headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body, headers: resp_headers}} ->
        content_type = get_content_type(resp_headers, url)
        extension = content_type_to_extension(content_type)

        {:ok,
         %{
           binary: body,
           content_type: content_type,
           extension: extension,
           file_size: byte_size(body)
         }}

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_content_type(headers, url) do
    content_type =
      case headers do
        %{"content-type" => [type | _]} -> type
        %{"content-type" => type} when is_binary(type) -> type
        _ -> nil
      end

    if content_type do
      content_type |> String.split(";") |> List.first() |> String.trim()
    else
      guess_content_type_from_url(url)
    end
  end

  defp guess_content_type_from_url(url) do
    cond do
      String.contains?(url, ".webp") -> "image/webp"
      String.contains?(url, ".png") -> "image/png"
      String.contains?(url, ".gif") -> "image/gif"
      String.contains?(url, ".jpg") or String.contains?(url, ".jpeg") -> "image/jpeg"
      true -> "image/jpeg"
    end
  end

  defp content_type_to_extension(content_type) do
    case content_type do
      "image/webp" -> "webp"
      "image/png" -> "png"
      "image/gif" -> "gif"
      "image/jpeg" -> "jpg"
      _ -> "jpg"
    end
  end
end
