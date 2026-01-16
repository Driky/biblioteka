defmodule WebtoonShared.Repo.Migrations.CreateChapterImages do
  use Ecto.Migration

  def change do
    create table(:chapter_images, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :chapter_id, references(:chapters, type: :binary_id, on_delete: :delete_all), null: false
      add :sequence, :integer, null: false
      add :storage_path, :string, null: false
      add :width, :integer, null: false
      add :height, :integer, null: false
      add :file_size, :integer

      timestamps()
    end

    create unique_index(:chapter_images, [:chapter_id, :sequence])
    create index(:chapter_images, [:chapter_id])
  end
end
