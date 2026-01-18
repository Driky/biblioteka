defmodule WebtoonWeb.StorageHelpers do
  @moduledoc """
  Helper functions for generating storage URLs.
  """

  @doc """
  Converts a storage path to a full public URL.
  If the path is nil or empty, returns nil.
  If the path is already a full URL (starts with http), returns it as-is.
  """
  def storage_url(nil), do: nil
  def storage_url(""), do: nil

  def storage_url(path) when is_binary(path) do
    if String.starts_with?(path, "http") do
      # Already a full URL (for backwards compatibility)
      path
    else
      # Build URL from path
      WebtoonShared.Storage.get_url(path)
    end
  end
end
