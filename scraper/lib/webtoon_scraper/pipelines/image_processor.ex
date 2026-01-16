defmodule WebtoonScraper.Pipelines.ImageProcessor do
  @moduledoc """
  Pipeline that downloads images and extracts their dimensions.
  Images are downloaded but NOT resized - original dimensions are preserved.
  """

  @behaviour Crawly.Pipeline

  require Logger

  @impl Crawly.Pipeline
  def run(item, state) do
    case item do
      %{type: :chapter, images: images} ->
        process_chapter_images(item, images, state)

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

  defp process_chapter_images(item, images, state) do
    processed_images =
      images
      |> Task.async_stream(
        &download_and_analyze_image/1,
        max_concurrency: 3,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, _reason} -> nil
      end)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(processed_images) do
      Logger.error("No images could be downloaded for chapter #{item.chapter_number}")
      {false, state}
    else
      Logger.info(
        "Downloaded #{length(processed_images)}/#{length(images)} images for chapter #{item.chapter_number}"
      )

      {Map.put(item, :images, processed_images), state}
    end
  end

  defp download_and_analyze_image(image_info) do
    %{url: url, headers: headers, sequence: sequence} = image_info

    Logger.debug("Downloading image #{sequence}: #{url}")

    req_headers =
      headers
      |> Enum.map(fn {k, v} -> {String.downcase(k), v} end)

    case Req.get(url, headers: req_headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body, headers: resp_headers}} ->
        case extract_dimensions(body) do
          {:ok, width, height} ->
            content_type = get_content_type(resp_headers, url)
            extension = content_type_to_extension(content_type)

            %{
              sequence: sequence,
              binary: body,
              width: width,
              height: height,
              file_size: byte_size(body),
              content_type: content_type,
              extension: extension
            }

          {:error, reason} ->
            Logger.warning("Failed to extract dimensions from #{url}: #{inspect(reason)}")
            nil
        end

      {:ok, %{status: status}} ->
        Logger.warning("HTTP #{status} downloading image: #{url}")
        nil

      {:error, reason} ->
        Logger.warning("Failed to download image #{url}: #{inspect(reason)}")
        nil
    end
  end

  defp extract_dimensions(binary) do
    case Image.from_binary(binary) do
      {:ok, image} ->
        {width, height, _bands} = Image.shape(image)
        {:ok, width, height}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_content_type(headers, url) do
    # Try to get from headers first
    case List.keyfind(headers, "content-type", 0) do
      {_, type} ->
        type |> String.split(";") |> List.first() |> String.trim()

      nil ->
        # Fall back to URL extension
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
