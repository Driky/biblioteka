defmodule WebtoonScraper.Sources do
  @moduledoc """
  Context module for managing webtoon sources.
  Handles CRUD operations and scraping state tracking.
  """

  import Ecto.Query
  alias WebtoonShared.Repo
  alias WebtoonShared.Schema.WebtoonSource

  @doc """
  Gets all enabled sources for a specific site spider.
  """
  def get_enabled_sources(site_id) do
    WebtoonSource
    |> where([s], s.site_id == ^site_id and s.enabled == true)
    |> preload(:webtoon)
    |> Repo.all()
  end

  @doc """
  Gets a source by its URL.
  """
  def get_by_url(url) do
    WebtoonSource
    |> where([s], s.source_url == ^url)
    |> preload(:webtoon)
    |> Repo.one()
  end

  @doc """
  Gets a source by ID.
  """
  def get(id) do
    WebtoonSource
    |> preload(:webtoon)
    |> Repo.get(id)
  end

  @doc """
  Updates the last scraped chapter for a source.
  Called after successfully saving a chapter.
  """
  def update_last_scraped(source_id, chapter_number) do
    source = Repo.get!(WebtoonSource, source_id)

    source
    |> WebtoonSource.changeset(%{
      last_chapter_scraped: chapter_number,
      last_checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Updates the last checked timestamp without updating the chapter.
  Called when checking a source but finding no new chapters.
  """
  def touch_last_checked(source_id) do
    source = Repo.get!(WebtoonSource, source_id)

    source
    |> WebtoonSource.changeset(%{
      last_checked_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Enables or disables a source.
  """
  def set_enabled(source_id, enabled) when is_boolean(enabled) do
    source = Repo.get!(WebtoonSource, source_id)

    source
    |> WebtoonSource.changeset(%{enabled: enabled})
    |> Repo.update()
  end

  @doc """
  Creates a new source.
  """
  def create(attrs) do
    %WebtoonSource{}
    |> WebtoonSource.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Links a source to a webtoon.
  """
  def link_to_webtoon(source_id, webtoon_id) do
    source = Repo.get!(WebtoonSource, source_id)

    source
    |> WebtoonSource.changeset(%{webtoon_id: webtoon_id})
    |> Repo.update()
  end
end
