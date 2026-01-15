defmodule WebtoonShared.Schema.Chapter do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chapters" do
    field :chapter_number, :decimal
    field :title, :string
    field :source_url, :string

    belongs_to :webtoon, WebtoonShared.Schema.Webtoon
    has_many :images, WebtoonShared.Schema.ChapterImage

    timestamps()
  end

  @required_fields [:chapter_number, :source_url, :webtoon_id]
  @optional_fields [:title]

  def changeset(chapter, attrs) do
    chapter
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:webtoon_id, :chapter_number])
    |> foreign_key_constraint(:webtoon_id)
    |> validate_number(:chapter_number, greater_than_or_equal_to: 0)
  end

  @doc """
  Formats the chapter number for display.
  Removes trailing zeros for whole numbers (e.g., 10.0 -> "10")
  """
  def format_number(%__MODULE__{chapter_number: number}) do
    format_number(number)
  end

  def format_number(%Decimal{} = number) do
    if Decimal.equal?(number, Decimal.round(number, 0)) do
      number |> Decimal.round(0) |> Decimal.to_string()
    else
      Decimal.to_string(number)
    end
  end
end
