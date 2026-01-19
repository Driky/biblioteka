defmodule WebtoonShared.Repo.Migrations.CreateSpiderConfigs do
  use Ecto.Migration

  def change do
    create table(:spider_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :spider_name, :string, null: false
      add :enabled, :boolean, default: true
      add :max_chapters_per_run, :integer, default: 10
      add :request_delay_ms, :integer, default: 1000
      add :last_run_at, :utc_datetime

      timestamps()
    end

    create unique_index(:spider_configs, [:spider_name])
  end
end
