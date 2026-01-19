defmodule WebtoonShared.Repo.Migrations.CreateSpiderRuns do
  use Ecto.Migration

  def change do
    create table(:spider_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :spider_name, :string, null: false
      add :crawl_id, :string
      add :status, :string, default: "running"
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :chapters_found, :integer, default: 0
      add :chapters_processed, :integer, default: 0
      add :images_downloaded, :integer, default: 0
      add :errors_count, :integer, default: 0

      timestamps()
    end

    create index(:spider_runs, [:spider_name])
    create index(:spider_runs, [:status])
    create index(:spider_runs, [:started_at])
  end
end
