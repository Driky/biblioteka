defmodule WebtoonShared.Repo.Migrations.CreateSpiderRunErrors do
  use Ecto.Migration

  def change do
    create table(:spider_run_errors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :spider_run_id, references(:spider_runs, type: :binary_id, on_delete: :delete_all)
      add :webtoon_id, references(:webtoons, type: :binary_id, on_delete: :nilify_all)
      add :chapter_number, :decimal
      add :error_type, :string
      add :error_message, :text
      add :stacktrace, :text
      add :occurred_at, :utc_datetime

      timestamps()
    end

    create index(:spider_run_errors, [:spider_run_id])
    create index(:spider_run_errors, [:webtoon_id])
  end
end
