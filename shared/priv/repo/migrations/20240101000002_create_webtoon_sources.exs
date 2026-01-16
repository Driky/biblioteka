defmodule WebtoonShared.Repo.Migrations.CreateWebtoonSources do
  use Ecto.Migration

  def change do
    create table(:webtoon_sources, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :webtoon_id, references(:webtoons, type: :binary_id, on_delete: :nilify_all)
      add :site_id, :string, null: false
      add :source_url, :string, null: false
      add :enabled, :boolean, default: true, null: false
      add :last_checked_at, :utc_datetime
      add :last_chapter_scraped, :decimal

      timestamps()
    end

    create unique_index(:webtoon_sources, [:site_id, :source_url])
    create index(:webtoon_sources, [:webtoon_id])
    create index(:webtoon_sources, [:site_id, :enabled])
  end
end
