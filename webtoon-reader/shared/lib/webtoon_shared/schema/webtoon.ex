defmodule WebtoonShared.Schema.Webtoon do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "webtoons" do
    field :title, :string
    field :slug, :string
    field :cover_url, :string

    has_many :chapters, WebtoonShared.Schema.Chapter
    has_many :sources, WebtoonShared.Schema.WebtoonSource

    timestamps()
  end

  @required_fields [:title, :slug]
  @optional_fields [:cover_url]

  def changeset(webtoon, attrs) do
    webtoon
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:slug)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/, message: "must be URL-friendly (lowercase, numbers, hyphens)")
  end

  @doc """
  Generates a URL-friendly slug from a title.
  """
  def generate_slug(title) when is_binary(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^\w\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end
end
