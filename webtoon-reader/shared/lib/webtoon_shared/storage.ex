defmodule WebtoonShared.Storage do
  @moduledoc """
  Storage facade that delegates to the configured storage backend.
  """

  @doc """
  Uploads binary data to storage.
  """
  def upload(binary, path, opts \\ []) do
    backend().upload(binary, path, opts)
  end

  @doc """
  Gets the public URL for a stored object.
  """
  def get_url(path, opts \\ []) do
    backend().get_url(path, opts)
  end

  @doc """
  Deletes an object from storage.
  """
  def delete(path) do
    backend().delete(path)
  end

  @doc """
  Checks if an object exists.
  """
  def exists?(path) do
    backend().exists?(path)
  end

  @doc """
  Generates a storage path for a chapter image.
  """
  defdelegate image_path(webtoon_slug, chapter_number, sequence, extension),
    to: WebtoonShared.Storage.R2

  defp backend do
    Application.get_env(:webtoon_shared, :storage_backend, WebtoonShared.Storage.R2)
  end
end
