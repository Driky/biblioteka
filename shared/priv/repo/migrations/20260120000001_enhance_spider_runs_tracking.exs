defmodule WebtoonShared.Repo.Migrations.EnhanceSpiderRunsTracking do
  use Ecto.Migration

  def change do
    alter table(:spider_runs) do
      # Job tracking
      add :jobs_total, :integer, default: 0
      add :jobs_completed, :integer, default: 0
      add :jobs_failed, :integer, default: 0

      # Timing metrics
      add :discovery_started_at, :utc_datetime
      add :discovery_completed_at, :utc_datetime
      add :total_execution_time_ms, :bigint, default: 0

      # Additional image metrics
      add :images_found, :integer, default: 0
      add :images_uploaded, :integer, default: 0

      # Error tracking
      add :last_error, :text
    end

    # Add index for finding runs by status
    create index(:spider_runs, [:status])
  end
end
