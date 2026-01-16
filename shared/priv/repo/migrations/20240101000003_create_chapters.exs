defmodule WebtoonShared.Repo.Migrations.CreateChapters do
  use Ecto.Migration

  def change do
    create table(:chapters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :webtoon_id, references(:webtoons, type: :binary_id, on_delete: :delete_all), null: false
      add :chapter_number, :decimal, null: false
      add :title, :string
      add :source_url, :string, null: false

      timestamps()
    end

    create unique_index(:chapters, [:webtoon_id, :chapter_number])
    create index(:chapters, [:webtoon_id])
  end
end
