defmodule Webtoon.Webtoons do
  @moduledoc """
  Context module for querying webtoons, chapters, and managing reading progress.
  """

  import Ecto.Query
  alias WebtoonShared.Repo
  alias WebtoonShared.Schema.{Webtoon, Chapter, ChapterImage, ReadingProgress}

  # ============================================================================
  # Webtoons
  # ============================================================================

  @doc """
  Lists all webtoons with chapter count.
  """
  def list_webtoons do
    Webtoon
    |> join(:left, [w], c in Chapter, on: c.webtoon_id == w.id)
    |> group_by([w], w.id)
    |> select([w, c], %{webtoon: w, chapter_count: count(c.id)})
    |> order_by([w], asc: w.title)
    |> Repo.all()
  end

  @doc """
  Gets a webtoon by slug.
  """
  def get_webtoon_by_slug(slug) do
    Webtoon
    |> Repo.get_by(slug: slug)
  end

  @doc """
  Gets a webtoon by slug with chapters.
  """
  def get_webtoon_with_chapters(slug) do
    webtoon = get_webtoon_by_slug(slug)

    if webtoon do
      chapters =
        Chapter
        |> where([c], c.webtoon_id == ^webtoon.id)
        |> order_by([c], desc: c.chapter_number)
        |> Repo.all()

      %{webtoon: webtoon, chapters: chapters}
    else
      nil
    end
  end

  # ============================================================================
  # Chapters
  # ============================================================================

  @doc """
  Gets a chapter by webtoon slug and chapter number.
  """
  def get_chapter(webtoon_slug, chapter_number) do
    webtoon = get_webtoon_by_slug(webtoon_slug)

    if webtoon do
      chapter_num = parse_chapter_number(chapter_number)

      Chapter
      |> where([c], c.webtoon_id == ^webtoon.id and c.chapter_number == ^chapter_num)
      |> Repo.one()
      |> case do
        nil -> nil
        chapter -> Map.put(chapter, :webtoon, webtoon)
      end
    else
      nil
    end
  end

  @doc """
  Gets a chapter with all its images.
  """
  def get_chapter_with_images(webtoon_slug, chapter_number) do
    case get_chapter(webtoon_slug, chapter_number) do
      nil ->
        nil

      chapter ->
        images =
          ChapterImage
          |> where([i], i.chapter_id == ^chapter.id)
          |> order_by([i], asc: i.sequence)
          |> Repo.all()
          |> Enum.map(&add_public_url/1)

        %{chapter: chapter, images: images, webtoon: chapter.webtoon}
    end
  end

  @doc """
  Gets the previous chapter (lower chapter number).
  """
  def get_previous_chapter(webtoon_id, current_chapter_number) do
    Chapter
    |> where([c], c.webtoon_id == ^webtoon_id and c.chapter_number < ^current_chapter_number)
    |> order_by([c], desc: c.chapter_number)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets the next chapter (higher chapter number).
  """
  def get_next_chapter(webtoon_id, current_chapter_number) do
    Chapter
    |> where([c], c.webtoon_id == ^webtoon_id and c.chapter_number > ^current_chapter_number)
    |> order_by([c], asc: c.chapter_number)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Gets images for a chapter by chapter ID.
  """
  def get_chapter_images(chapter_id) do
    ChapterImage
    |> where([i], i.chapter_id == ^chapter_id)
    |> order_by([i], asc: i.sequence)
    |> Repo.all()
    |> Enum.map(&add_public_url/1)
  end

  # ============================================================================
  # Reading Progress
  # ============================================================================

  @doc """
  Gets reading progress for a user and webtoon.
  """
  def get_reading_progress(user_id \\ default_user_id(), webtoon_id) do
    ReadingProgress
    |> where([p], p.user_id == ^user_id and p.webtoon_id == ^webtoon_id)
    |> preload(:last_chapter)
    |> Repo.one()
  end

  @doc """
  Updates reading progress for a user.
  """
  def update_reading_progress(user_id \\ default_user_id(), webtoon_id, chapter_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case get_reading_progress(user_id, webtoon_id) do
      nil ->
        %ReadingProgress{}
        |> ReadingProgress.changeset(%{
          user_id: user_id,
          webtoon_id: webtoon_id,
          last_chapter_id: chapter_id,
          last_read_at: now
        })
        |> Repo.insert()

      progress ->
        progress
        |> ReadingProgress.changeset(%{
          last_chapter_id: chapter_id,
          last_read_at: now
        })
        |> Repo.update()
    end
  end

  @doc """
  Gets reading progress for all webtoons for a user.
  Returns a map of webtoon_id => progress.
  """
  def get_all_reading_progress(user_id \\ default_user_id()) do
    ReadingProgress
    |> where([p], p.user_id == ^user_id)
    |> preload(:last_chapter)
    |> Repo.all()
    |> Map.new(fn p -> {p.webtoon_id, p} end)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp add_public_url(%ChapterImage{storage_path: path} = image) do
    url =
      if String.starts_with?(path || "", "http") do
        # Backwards compatibility: path is already a full URL
        path
      else
        public_url = Application.get_env(:webtoon_shared, :r2_public_url, "")
        "#{public_url}/#{path}"
      end

    Map.put(image, :url, url)
  end

  defp parse_chapter_number(number) when is_binary(number) do
    case Decimal.parse(number) do
      {decimal, _} -> decimal
      :error -> Decimal.new(0)
    end
  end

  defp parse_chapter_number(number) when is_integer(number), do: Decimal.new(number)
  defp parse_chapter_number(number) when is_float(number), do: Decimal.from_float(number)
  defp parse_chapter_number(%Decimal{} = number), do: number

  defp default_user_id, do: ReadingProgress.default_user_id()
end
