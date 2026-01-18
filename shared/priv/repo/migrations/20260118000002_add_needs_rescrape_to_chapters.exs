defmodule WebtoonShared.Repo.Migrations.AddNeedsRescrapeToChapters do
  use Ecto.Migration

  def change do
    alter table(:chapters) do
      add :needs_rescrape, :boolean, default: false, null: false
    end

    # Index for efficient filtering of chapters needing rescrape
    create index(:chapters, [:webtoon_id, :needs_rescrape], where: "needs_rescrape = true")
  end
end
