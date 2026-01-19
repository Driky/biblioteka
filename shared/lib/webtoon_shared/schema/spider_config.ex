defmodule WebtoonShared.Schema.SpiderConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "spider_configs" do
    field :spider_name, :string
    field :enabled, :boolean, default: true
    field :max_chapters_per_run, :integer, default: 10
    field :request_delay_ms, :integer, default: 1000
    field :last_run_at, :utc_datetime

    timestamps()
  end

  @required_fields [:spider_name]
  @optional_fields [:enabled, :max_chapters_per_run, :request_delay_ms, :last_run_at]

  def changeset(config, attrs) do
    config
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:spider_name)
    |> validate_number(:max_chapters_per_run, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_number(:request_delay_ms, greater_than_or_equal_to: 0)
  end
end
