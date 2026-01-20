defmodule WebtoonScraper.Pipelines.DatabaseSave do
  @moduledoc """
  Pipeline that saves cover images to the database.
  Chapter data is saved asynchronously by Oban ChapterWorker.
  """

  @behaviour Crawly.Pipeline

  require Logger

  alias WebtoonShared.Repo
  alias WebtoonShared.Schema.Webtoon

  @impl Crawly.Pipeline
  def run(item, state) do
    case item do
      # Chapters are handled asynchronously by Oban ChapterWorker
      %{type: :chapter} ->
        {item, state}

      %{type: :cover} ->
        save_cover(item, state)

      _ ->
        {item, state}
    end
  end

  defp save_cover(item, state) do
    case item do
      %{webtoon_id: webtoon_id, storage_path: storage_path} ->
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
end
