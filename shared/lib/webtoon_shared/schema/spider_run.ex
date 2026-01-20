defmodule WebtoonShared.Schema.SpiderRun do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ["running", "processing", "completed", "completed_with_errors", "failed"]

  schema "spider_runs" do
    field :spider_name, :string
    field :crawl_id, :string
    field :status, :string, default: "running"

    # Timing
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :discovery_started_at, :utc_datetime
    field :discovery_completed_at, :utc_datetime

    # Discovery metrics
    field :chapters_found, :integer, default: 0

    # Job tracking
    field :jobs_total, :integer, default: 0
    field :jobs_completed, :integer, default: 0
    field :jobs_failed, :integer, default: 0

    # Aggregate metrics from jobs
    field :chapters_processed, :integer, default: 0
    field :images_found, :integer, default: 0
    field :images_downloaded, :integer, default: 0
    field :images_uploaded, :integer, default: 0
    field :total_execution_time_ms, :integer, default: 0

    # Error tracking
    field :errors_count, :integer, default: 0
    field :last_error, :string

    has_many :errors, WebtoonShared.Schema.SpiderRunError

    timestamps()
  end

  @required_fields [:spider_name]
  @optional_fields [
    :crawl_id,
    :status,
    :started_at,
    :completed_at,
    :discovery_started_at,
    :discovery_completed_at,
    :chapters_found,
    :jobs_total,
    :jobs_completed,
    :jobs_failed,
    :chapters_processed,
    :images_found,
    :images_downloaded,
    :images_uploaded,
    :total_execution_time_ms,
    :errors_count,
    :last_error
  ]

  def changeset(run, attrs) do
    run
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @statuses)
  end

  def statuses, do: @statuses
end
