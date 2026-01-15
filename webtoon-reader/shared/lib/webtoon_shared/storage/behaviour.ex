defmodule WebtoonShared.Storage.Behaviour do
  @moduledoc """
  Behaviour for image storage backends.
  Allows swapping R2 for another provider later.
  """

  @type upload_opts :: [
          content_type: String.t(),
          metadata: map()
        ]

  @type url_opts :: [
          expires_in: pos_integer()
        ]

  @type upload_result :: %{
          path: String.t(),
          size: non_neg_integer()
        }

  @doc """
  Uploads binary data to storage at the given path.
  Returns the storage path and file size on success.
  """
  @callback upload(binary :: binary(), path :: String.t(), opts :: upload_opts()) ::
              {:ok, upload_result()} | {:error, term()}

  @doc """
  Gets the public URL for a stored object.
  """
  @callback get_url(path :: String.t(), opts :: url_opts()) :: String.t()

  @doc """
  Deletes an object from storage.
  """
  @callback delete(path :: String.t()) :: :ok | {:error, term()}

  @doc """
  Checks if an object exists in storage.
  """
  @callback exists?(path :: String.t()) :: boolean()
end
