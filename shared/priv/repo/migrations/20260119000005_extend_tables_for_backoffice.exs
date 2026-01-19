defmodule WebtoonShared.Repo.Migrations.ExtendTablesForBackoffice do
  use Ecto.Migration

  def change do
    # Add crawl_enabled to webtoon_sources
    alter table(:webtoon_sources) do
      add :crawl_enabled, :boolean, default: true
    end

    # Add granular rescrape flags to chapters
    alter table(:chapters) do
      add :needs_title_rescrape, :boolean, default: false
      add :needs_images_rescrape, :boolean, default: false
    end
  end
end
