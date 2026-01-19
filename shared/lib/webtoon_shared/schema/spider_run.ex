defmodule WebtoonShared.Schema.SpiderRun do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "spider_runs" do
    field :spider_name, :string
    field :crawl_id, :string
    field :status, :string, default: "running"
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :chapters_found, :integer, default: 0
    field :chapters_processed, :integer, default: 0
    field :images_downloaded, :integer, default: 0
    field :errors_count, :integer, default: 0

    has_many :errors, WebtoonShared.Schema.SpiderRunError

    timestamps()
  end

  @required_fields [:spider_name]
  @optional_fields [
    :crawl_id,
    :status,
    :started_at,
    :completed_at,
    :chapters_found,
    :chapters_processed,
    :images_downloaded,
    :errors_count
  ]

  def changeset(run, attrs) do
    run
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ["running", "completed", "failed"])
  end
end
