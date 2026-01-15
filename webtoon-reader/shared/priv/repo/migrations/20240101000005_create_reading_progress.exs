defmodule WebtoonShared.Repo.Migrations.CreateReadingProgress do
  use Ecto.Migration

  def change do
    create table(:reading_progress, primary_key: false) do
      add :user_id, :binary_id, primary_key: true
      add :webtoon_id, references(:webtoons, type: :binary_id, on_delete: :delete_all), primary_key: true
      add :last_chapter_id, references(:chapters, type: :binary_id, on_delete: :nilify_all)
      add :last_read_at, :utc_datetime

      timestamps(updated_at: false)
    end

    create index(:reading_progress, [:webtoon_id])
    create index(:reading_progress, [:user_id])
  end
end
