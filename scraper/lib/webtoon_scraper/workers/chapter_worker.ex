defmodule WebtoonScraper.Workers.ChapterWorker do
  @moduledoc """
  Oban worker that processes a single chapter:
  1. Downloads all images (parallel, max 3 concurrent)
  2. Uploads all images to Cloudflare R2 (parallel, max 3 concurrent)
  3. Saves chapter and images to database
  4. Records stats for spider run tracking
  """

  use Oban.Worker,
    queue: :chapters,
    max_attempts: 3,
    unique: [period: 300, fields: [:args], keys: [:webtoon_id, :chapter_number]]

  require Logger

  import Ecto.Query

  alias WebtoonShared.Repo
  alias WebtoonShared.Schema.{Chapter, ChapterImage}
  alias WebtoonShared.Storage
  alias WebtoonScraper.Sources
  alias WebtoonScraper.SpiderRuns

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "webtoon_id" => webtoon_id,
      "webtoon_slug" => webtoon_slug,
      "source_id" => source_id,
      "chapter_number" => chapter_number_str,
      "chapter_title" => chapter_title,
      "source_url" => source_url,
      "images" => images
    } = args

    # Optional spider_run_id for tracking
    spider_run_id = Map.get(args, "spider_run_id")

    chapter_number = Decimal.new(chapter_number_str)

    Logger.info(
      "ChapterWorker processing chapter #{chapter_number_str} with #{length(images)} images, spider_run_id=#{inspect(spider_run_id)}"
    )

    with {:ok, processed_images} <- download_images(images),
         {:ok, uploaded_images} <-
           upload_images(processed_images, webtoon_slug, chapter_number),
         {:ok, _chapter} <-
           save_to_database(
             webtoon_id,
             source_id,
             chapter_number,
             chapter_title,
             source_url,
             uploaded_images
           ) do
      # Update spider run stats if tracking
      if spider_run_id do
        Logger.info("ChapterWorker updating stats for run #{spider_run_id}: +1 chapter, +#{length(uploaded_images)} images")
        update_spider_run_stats(spider_run_id, length(uploaded_images))
      else
        Logger.debug("ChapterWorker: No spider_run_id, skipping stats update")
      end

      Logger.info("ChapterWorker completed chapter #{chapter_number_str}")
      :ok
    else
      {:error, reason} ->
        Logger.error("ChapterWorker failed for chapter #{chapter_number_str}: #{inspect(reason)}")

        # Record error if tracking
        if spider_run_id do
          record_error(spider_run_id, webtoon_id, chapter_number, reason)
        end

        {:error, reason}
    end
  end

  defp download_images(images) do
    results =
      images
      |> Task.async_stream(
        fn img -> download_single_image(img) end,
        max_concurrency: 3,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, {:ok, result}} -> result
        {:ok, {:error, _}} -> nil
        {:exit, _} -> nil
      end)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(results) do
      {:error, :no_images_downloaded}
    else
      Logger.info("Downloaded #{length(results)}/#{length(images)} images")
      {:ok, results}
    end
  end

  defp download_single_image(%{"url" => url, "headers" => headers, "sequence" => sequence}) do
    # Headers come from Oban args as a map (JSON deserialized)
    req_headers =
      headers
      |> Enum.map(fn {k, v} -> {String.downcase(to_string(k)), v} end)

    case Req.get(url, headers: req_headers, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body, headers: resp_headers}} ->
        case extract_dimensions(body) do
          {:ok, width, height} ->
            content_type = get_content_type(resp_headers, url)
            extension = content_type_to_extension(content_type)

            {:ok,
             %{
               sequence: sequence,
               binary: body,
               width: width,
               height: height,
               file_size: byte_size(body),
               content_type: content_type,
               extension: extension
             }}

          {:error, reason} ->
            Logger.warning("Failed to extract dimensions from #{url}: #{inspect(reason)}")
            {:error, reason}
        end

      {:ok, %{status: status}} ->
        Logger.warning("HTTP #{status} downloading image: #{url}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.warning("Failed to download image #{url}: #{inspect(reason)}")
        {:error, reason}
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

  defp upload_images(images, webtoon_slug, chapter_number) do
    results =
      images
      |> Task.async_stream(
        fn img -> upload_single_image(img, webtoon_slug, chapter_number) end,
        max_concurrency: 3,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, {:ok, result}} -> result
        {:ok, {:error, _}} -> nil
        {:exit, _} -> nil
      end)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(results) do
      {:error, :no_images_uploaded}
    else
      Logger.info("Uploaded #{length(results)}/#{length(images)} images to R2")
      {:ok, results}
    end
  end

  defp upload_single_image(image, webtoon_slug, chapter_number) do
    %{
      sequence: sequence,
      binary: binary,
      extension: extension,
      content_type: content_type
    } = image

    storage_path = Storage.image_path(webtoon_slug, chapter_number, sequence, extension)

    case Storage.upload(binary, storage_path, content_type: content_type) do
      {:ok, %{path: path}} ->
        {:ok,
         image
         |> Map.delete(:binary)
         |> Map.put(:storage_path, path)}

      {:error, reason} ->
        Logger.error("Failed to upload #{storage_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp save_to_database(
         webtoon_id,
         source_id,
         chapter_number,
         chapter_title,
         source_url,
         images
       ) do
    Repo.transaction(fn ->
      # Insert or update chapter
      chapter_attrs = %{
        webtoon_id: webtoon_id,
        chapter_number: chapter_number,
        title: chapter_title,
        source_url: source_url,
        needs_rescrape: false
      }

      chapter =
        case Repo.get_by(Chapter, webtoon_id: webtoon_id, chapter_number: chapter_number) do
          nil ->
            %Chapter{}
            |> Chapter.changeset(chapter_attrs)
            |> Repo.insert!()

          existing ->
            existing
            |> Chapter.changeset(chapter_attrs)
            |> Repo.update!()
        end

      # Delete existing images for this chapter (if re-scraping)
      Repo.delete_all(
        from(i in ChapterImage, where: i.chapter_id == ^chapter.id)
      )

      # Insert new images
      image_records =
        images
        |> Enum.map(fn img ->
          %{
            chapter_id: chapter.id,
            sequence: img.sequence,
            storage_path: img.storage_path,
            width: img.width,
            height: img.height,
            file_size: img.file_size,
            inserted_at: {:placeholder, :now},
            updated_at: {:placeholder, :now}
          }
        end)

      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      {count, _} =
        Repo.insert_all(
          ChapterImage,
          image_records,
          placeholders: %{now: now}
        )

      Logger.info(
        "Saved chapter #{chapter_number} with #{count} images for webtoon #{webtoon_id}"
      )

      # Update source's last_chapter_scraped
      Sources.update_last_scraped(source_id, chapter_number)

      chapter
    end)
  end

  defp update_spider_run_stats(spider_run_id, image_count) do
    SpiderRuns.increment_stats(spider_run_id, 1, image_count)
  end

  defp record_error(spider_run_id, webtoon_id, chapter_number, reason) do
    SpiderRuns.record_error(spider_run_id, %{
      webtoon_id: webtoon_id,
      chapter_number: chapter_number,
      error_type: "processing_error",
      error_message: inspect(reason)
    })
  end
end
