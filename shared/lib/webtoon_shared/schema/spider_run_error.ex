defmodule WebtoonShared.Schema.SpiderRunError do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "spider_run_errors" do
    field :chapter_number, :decimal
    field :error_type, :string
    field :error_message, :string
    field :stacktrace, :string
    field :occurred_at, :utc_datetime

    belongs_to :spider_run, WebtoonShared.Schema.SpiderRun
    belongs_to :webtoon, WebtoonShared.Schema.Webtoon

    timestamps()
  end

  @required_fields [:spider_run_id, :error_type, :error_message]
  @optional_fields [:webtoon_id, :chapter_number, :stacktrace, :occurred_at]

  def changeset(error, attrs) do
    error
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:spider_run_id)
    |> foreign_key_constraint(:webtoon_id)
  end
end
