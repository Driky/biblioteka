defmodule WebtoonShared.Schema.WebtoonSource do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "webtoon_sources" do
    field :site_id, :string
    field :source_url, :string
    field :enabled, :boolean, default: true
    field :crawl_enabled, :boolean, default: true
    field :last_checked_at, :utc_datetime
    field :last_chapter_scraped, :decimal

    belongs_to :webtoon, WebtoonShared.Schema.Webtoon

    timestamps()
  end

  @required_fields [:site_id, :source_url]
  @optional_fields [:webtoon_id, :enabled, :crawl_enabled, :last_checked_at, :last_chapter_scraped]

  def changeset(source, attrs) do
    source
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:site_id, :source_url])
    |> validate_url(:source_url)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case URI.parse(value) do
        %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
          []

        _ ->
          [{field, "must be a valid HTTP(S) URL"}]
      end
    end)
  end
end
