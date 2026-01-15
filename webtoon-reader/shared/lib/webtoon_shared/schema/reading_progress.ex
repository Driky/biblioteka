defmodule WebtoonShared.Schema.ReadingProgress do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :binary_id

  schema "reading_progress" do
    field :user_id, :binary_id, primary_key: true
    field :last_read_at, :utc_datetime

    belongs_to :webtoon, WebtoonShared.Schema.Webtoon, primary_key: true
    belongs_to :last_chapter, WebtoonShared.Schema.Chapter

    timestamps(updated_at: false)
  end

  # Default user ID for single-user mode
  @default_user_id "00000000-0000-0000-0000-000000000001"

  def default_user_id, do: @default_user_id

  @required_fields [:user_id, :webtoon_id]
  @optional_fields [:last_chapter_id, :last_read_at]

  def changeset(progress, attrs) do
    progress
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:webtoon_id)
    |> foreign_key_constraint(:last_chapter_id)
  end

  @doc """
  Creates a changeset for updating reading progress.
  Uses the default user ID if not provided.
  """
  def update_changeset(progress, attrs) do
    attrs = Map.put_new(attrs, :user_id, @default_user_id)

    progress
    |> changeset(attrs)
    |> put_change(:last_read_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
