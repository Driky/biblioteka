defmodule WebtoonShared.Repo.Migrations.FixStorageUrls do
  use Ecto.Migration

  @doc """
  This migration converts full URLs to paths in storage-related columns.
  Previously, the scraper was storing full URLs like:
    https://pub-xxx.r2.dev/webtoons/abc123/cover.jpg

  They should be just paths:
    webtoons/abc123/cover.jpg
  """
  def up do
    # Fix webtoons.cover_url - extract path from full URLs
    execute """
    UPDATE webtoons
    SET cover_url = REGEXP_REPLACE(cover_url, '^https?://[^/]+/', '')
    WHERE cover_url LIKE 'http%'
    """

    # Fix chapter_images.storage_path - extract path from full URLs
    execute """
    UPDATE chapter_images
    SET storage_path = REGEXP_REPLACE(storage_path, '^https?://[^/]+/', '')
    WHERE storage_path LIKE 'http%'
    """
  end

  def down do
    # Cannot reliably reverse this migration since we don't know the original base URL
    # The application will still work with paths (backwards compatible)
    :ok
  end
end
