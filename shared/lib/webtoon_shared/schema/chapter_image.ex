defmodule WebtoonShared.Schema.ChapterImage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chapter_images" do
    field :sequence, :integer
    field :storage_path, :string
    field :width, :integer
    field :height, :integer
    field :file_size, :integer

    belongs_to :chapter, WebtoonShared.Schema.Chapter

    timestamps()
  end

  @required_fields [:sequence, :storage_path, :width, :height, :chapter_id]
  @optional_fields [:file_size]

  def changeset(image, attrs) do
    image
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint([:chapter_id, :sequence])
    |> foreign_key_constraint(:chapter_id)
    |> validate_number(:sequence, greater_than_or_equal_to: 0)
    |> validate_number(:width, greater_than: 0)
    |> validate_number(:height, greater_than: 0)
  end

  @doc """
  Returns the public URL for this image.
  """
  def public_url(%__MODULE__{storage_path: path}) do
    base_url = Application.get_env(:webtoon_shared, :r2_public_url, "")
    "#{base_url}/#{path}"
  end
end
