defmodule WebtoonScraper.Pipelines.R2Upload do
  @moduledoc """
  Pipeline that uploads processed images to Cloudflare R2.
  Generates storage paths and handles upload errors gracefully.
  """

  @behaviour Crawly.Pipeline

  require Logger

  alias WebtoonShared.Storage

  @impl Crawly.Pipeline
  def run(item, state) do
    case item do
      %{type: :chapter, images: images, webtoon_slug: slug, chapter_number: chapter_num}
      when is_binary(slug) ->
        upload_chapter_images(item, images, slug, chapter_num, state)

      %{type: :chapter, webtoon_slug: nil} ->
        Logger.error("Cannot upload images: webtoon_slug is nil")
        {false, state}

      %{type: :cover, binary: binary, webtoon_slug: slug, extension: ext, content_type: content_type}
      when is_binary(slug) and is_binary(binary) ->
        upload_cover_image(item, binary, slug, ext, content_type, state)

      %{type: :cover, webtoon_slug: nil} ->
        Logger.error("Cannot upload cover: webtoon_slug is nil")
        {false, state}

      _ ->
        {item, state}
    end
  end

  defp upload_cover_image(item, binary, slug, extension, content_type, state) do
    storage_path = "webtoons/#{slug}/cover.#{extension}"

    Logger.info("Uploading cover image to #{storage_path}")

    case Storage.upload(binary, storage_path, content_type: content_type) do
      {:ok, %{path: path}} ->
        updated_item =
          item
          |> Map.delete(:binary)
          |> Map.put(:storage_path, path)

        Logger.info("Cover image uploaded successfully to #{path}")
        {updated_item, state}

      {:error, reason} ->
        Logger.error("Failed to upload cover image: #{inspect(reason)}")
        {false, state}
    end
  end

  defp upload_chapter_images(item, images, slug, chapter_num, state) do
    uploaded_images =
      images
      |> Enum.map(&upload_image(&1, slug, chapter_num))
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(uploaded_images) do
      Logger.error("No images could be uploaded for chapter #{chapter_num}")
      {false, state}
    else
      Logger.info(
        "Uploaded #{length(uploaded_images)}/#{length(images)} images to R2 for chapter #{chapter_num}"
      )

      {Map.put(item, :images, uploaded_images), state}
    end
  end

  defp upload_image(image, slug, chapter_num) do
    %{
      sequence: sequence,
      binary: binary,
      extension: extension,
      content_type: content_type
    } = image

    storage_path = Storage.image_path(slug, chapter_num, sequence, extension)

    Logger.debug("Uploading #{storage_path}")

    case Storage.upload(binary, storage_path, content_type: content_type) do
      {:ok, %{path: path}} ->
        # Remove binary from image map (no longer needed) and add storage_path
        image
        |> Map.delete(:binary)
        |> Map.put(:storage_path, path)

      {:error, reason} ->
        Logger.error("Failed to upload #{storage_path}: #{inspect(reason)}")
        nil
    end
  end
end
