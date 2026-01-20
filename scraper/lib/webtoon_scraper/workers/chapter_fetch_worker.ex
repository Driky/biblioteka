defmodule WebtoonScraper.Workers.ChapterFetchWorker do
  @moduledoc """
  Oban worker that fetches and processes a chapter URL.

  This worker handles the complete chapter processing pipeline:
  1. Fetches the chapter page using RenderServer
  2. Extracts images from the page using the spider's parser
  3. Downloads all images
  4. Uploads to R2
  5. Saves to database

  This architecture separates concerns:
  - Crawly: Discovery (fetch webtoon page, find chapters)
  - Oban: Processing (reliably fetch and process each chapter)
  """

  use Oban.Worker,
    queue: :chapter_fetch,
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
      "spider_module" => spider_module_str,
      "chapter_url" => chapter_url,
      "webtoon_id" => webtoon_id,
      "webtoon_slug" => webtoon_slug,
      "source_id" => source_id,
      "chapter_number" => chapter_number_str,
      "chapter_title" => chapter_title
    } = args

    spider_run_id = Map.get(args, "spider_run_id")
    chapter_number = Decimal.new(chapter_number_str)

    Logger.info(
      "ChapterFetchWorker: Processing chapter #{chapter_number_str} from #{chapter_url}"
    )

    # Get the spider module for parsing
    spider_module = String.to_existing_atom(spider_module_str)

    with {:ok, html} <- fetch_chapter_page(chapter_url),
         {:ok, images} <- extract_images(spider_module, html, chapter_url),
         {:ok, processed_images} <- download_images(images, spider_module),
         {:ok, uploaded_images} <- upload_images(processed_images, webtoon_slug, chapter_number),
         {:ok, _chapter} <-
           save_to_database(
             webtoon_id,
             source_id,
             chapter_number,
             chapter_title,
             chapter_url,
             uploaded_images
           ) do
      # Update spider run stats if tracking
      if spider_run_id do
        Logger.info(
          "ChapterFetchWorker: Updating stats for run #{spider_run_id}: +1 chapter, +#{length(uploaded_images)} images"
        )

        SpiderRuns.increment_stats(spider_run_id, 1, length(uploaded_images))
      end

      Logger.info("ChapterFetchWorker: Completed chapter #{chapter_number_str}")
      :ok
    else
      {:error, reason} ->
        Logger.error(
          "ChapterFetchWorker: Failed for chapter #{chapter_number_str}: #{inspect(reason)}"
        )

        if spider_run_id do
          SpiderRuns.record_error(spider_run_id, %{
            webtoon_id: webtoon_id,
            chapter_number: chapter_number,
            error_type: "fetch_error",
            error_message: inspect(reason)
          })
        end

        {:error, reason}
    end
  end

  defp fetch_chapter_page(url) do
    Logger.info("ChapterFetchWorker: Fetching page #{url}")

    body =
      Jason.encode!(%{
        url: url,
        scroll: true,
        headers: []
      })

    headers = [{"Content-Type", "application/json"}]

    http_options = [
      recv_timeout: 120_000,
      timeout: 120_000,
      connect_timeout: 10_000,
      hackney: [pool: false]
    ]

    base_url = get_render_server_url()

    case HTTPoison.post(base_url, body, headers, http_options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"body" => html}} when is_binary(html) and html != "" ->
            Logger.debug("ChapterFetchWorker: Got page, body length: #{String.length(html)}")
            {:ok, html}

          {:ok, %{"body" => _}} ->
            {:error, :empty_response}

          {:ok, %{"error" => error}} ->
            {:error, {:render_error, error}}

          {:error, reason} ->
            {:error, {:json_decode_error, reason}}
        end

      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, {:http_error, status}}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp get_render_server_url do
    case Application.get_env(:crawly, :fetcher) do
      {WebtoonScraper.Fetchers.RenderServer, opts} ->
        Keyword.get(opts, :base_url, "http://render-server:3000/render")

      _ ->
        "http://render-server:3000/render"
    end
  end

  defp extract_images(spider_module, html, url) do
    Logger.debug("ChapterFetchWorker: Extracting images from page")

    # Create a mock response for the spider's parser
    response = %{
      body: html,
      request_url: url
    }

    # Call the spider's parse_chapter_images function
    Code.ensure_loaded!(spider_module)

    raw_images =
      if function_exported?(spider_module, :parse_chapter_images, 1) do
        spider_module.parse_chapter_images(response)
      else
        Logger.error("Spider #{spider_module} does not implement parse_chapter_images/1")
        []
      end

    if Enum.empty?(raw_images) do
      Logger.warning("ChapterFetchWorker: No images found in page")
      {:error, :no_images_found}
    else
      Logger.info("ChapterFetchWorker: Found #{length(raw_images)} images")
      {:ok, raw_images}
    end
  end

  defp download_images(raw_images, spider_module) do
    Code.ensure_loaded!(spider_module)

    images =
      raw_images
      |> Enum.with_index(1)
      |> Enum.map(fn {img, seq} ->
        {url, headers} =
          case img do
            %{url: url, headers: headers} ->
              {url, headers}

            url when is_binary(url) ->
              headers =
                if function_exported?(spider_module, :image_headers, 1) do
                  spider_module.image_headers(url)
                else
                  []
                end

              {url, headers}
          end

        %{url: url, headers: headers, sequence: seq}
      end)

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
      Logger.info("ChapterFetchWorker: Downloaded #{length(results)}/#{length(images)} images")
      {:ok, results}
    end
  end

  defp download_single_image(%{url: url, headers: headers, sequence: sequence}) do
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
        fn img ->
          %{sequence: sequence, binary: binary, extension: extension, content_type: content_type} =
            img

          storage_path = Storage.image_path(webtoon_slug, chapter_number, sequence, extension)

          case Storage.upload(binary, storage_path, content_type: content_type) do
            {:ok, %{path: path}} ->
              {:ok,
               img
               |> Map.delete(:binary)
               |> Map.put(:storage_path, path)}

            {:error, reason} ->
              Logger.error("Failed to upload #{storage_path}: #{inspect(reason)}")
              {:error, reason}
          end
        end,
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
      Logger.info("ChapterFetchWorker: Uploaded #{length(results)}/#{length(images)} images to R2")
      {:ok, results}
    end
  end

  defp save_to_database(webtoon_id, source_id, chapter_number, chapter_title, source_url, images) do
    Repo.transaction(fn ->
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
      Repo.delete_all(from(i in ChapterImage, where: i.chapter_id == ^chapter.id))

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
        "ChapterFetchWorker: Saved chapter #{chapter_number} with #{count} images"
      )

      # Update source's last_chapter_scraped
      Sources.update_last_scraped(source_id, chapter_number)

      chapter
    end)
  end
end
