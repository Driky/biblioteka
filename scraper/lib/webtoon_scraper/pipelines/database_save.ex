defmodule WebtoonScraper.Pipelines.DatabaseSave do
  @moduledoc """
  Pipeline that saves chapter and image data to the database.
  Updates the source's last_chapter_scraped after successful save.
  """

  @behaviour Crawly.Pipeline

  require Logger
  import Ecto.Query

  alias WebtoonShared.Repo
  alias WebtoonShared.Schema.{Chapter, ChapterImage, Webtoon}
  alias WebtoonScraper.Sources

  @impl Crawly.Pipeline
  def run(item, state) do
    case item do
      %{type: :chapter} ->
        save_chapter(item, state)

      %{type: :cover} ->
        save_cover(item, state)

      _ ->
        {item, state}
    end
  end

  defp save_cover(item, state) do
    # Check if storage_path exists (set by R2Upload pipeline)
    case item do
      %{webtoon_id: webtoon_id, storage_path: storage_path} ->
        # Store just the path, not the full URL
        # The full URL will be built at display time using R2_PUBLIC_URL config
        case Repo.get(Webtoon, webtoon_id) do
          nil ->
            Logger.error("Webtoon #{webtoon_id} not found, cannot save cover")
            {false, state}

          webtoon ->
            webtoon
            |> Webtoon.changeset(%{cover_url: storage_path})
            |> Repo.update()
            |> case do
              {:ok, _} ->
                Logger.info("Updated webtoon #{webtoon_id} cover_url to #{storage_path}")
                {item, state}

              {:error, reason} ->
                Logger.error("Failed to update webtoon cover: #{inspect(reason)}")
                {false, state}
            end
        end

      _ ->
        Logger.warning("Cover item missing storage_path, skipping database save")
        {item, state}
    end
  end

  defp save_chapter(item, state) do
    %{
      webtoon_id: webtoon_id,
      source_id: source_id,
      chapter_number: chapter_number,
      chapter_title: chapter_title,
      source_url: source_url,
      images: images
    } = item

    Repo.transaction(fn ->
      # Insert or update chapter
      chapter_attrs = %{
        webtoon_id: webtoon_id,
        chapter_number: chapter_number,
        title: chapter_title,
        source_url: source_url
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

      chapter
    end)
    |> case do
      {:ok, _chapter} ->
        # Update source's last_chapter_scraped
        Sources.update_last_scraped(source_id, chapter_number)
        Logger.info("Updated source #{source_id} last_chapter_scraped to #{chapter_number}")
        {item, state}

      {:error, reason} ->
        Logger.error("Failed to save chapter #{chapter_number}: #{inspect(reason)}")
        {false, state}
    end
  end
end
