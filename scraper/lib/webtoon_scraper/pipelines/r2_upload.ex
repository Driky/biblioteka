defmodule WebtoonScraper.Pipelines.R2Upload do
  @moduledoc """
  Pipeline that uploads cover images to Cloudflare R2.
  Chapter images are handled asynchronously by Oban ChapterWorker.
  """

  @behaviour Crawly.Pipeline

  require Logger

  alias WebtoonShared.Storage

  @impl Crawly.Pipeline
  def run(item, state) do
    case item do
      # Chapters are handled asynchronously by Oban ChapterWorker
      %{type: :chapter} ->
        {item, state}

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
end
