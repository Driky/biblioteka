defmodule WebtoonShared.Repo.Migrations.CreateWebtoons do
  use Ecto.Migration

  def change do
    create table(:webtoons, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :slug, :string, null: false
      add :cover_url, :string

      timestamps()
    end

    create unique_index(:webtoons, [:slug])
    create index(:webtoons, [:title])
  end
end
