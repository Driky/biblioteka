defmodule WebtoonShared.Storage.R2 do
  @moduledoc """
  Cloudflare R2 storage implementation.
  Uses S3-compatible API via ex_aws_s3.
  """

  @behaviour WebtoonShared.Storage.Behaviour

  require Logger

  @impl true
  def upload(binary, path, opts \\ []) do
    bucket = bucket_name()
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")

    request =
      ExAws.S3.put_object(bucket, path, binary,
        content_type: content_type
      )

    case ExAws.request(request, config()) do
      {:ok, _response} ->
        {:ok, %{path: path, size: byte_size(binary)}}

      {:error, reason} ->
        Logger.error("R2 upload failed for #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def get_url(path, _opts \\ []) do
    public_url = Application.get_env(:webtoon_shared, :r2_public_url, "")
    "#{public_url}/#{path}"
  end

  @impl true
  def delete(path) do
    bucket = bucket_name()

    case ExAws.request(ExAws.S3.delete_object(bucket, path), config()) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def exists?(path) do
    bucket = bucket_name()

    case ExAws.request(ExAws.S3.head_object(bucket, path), config()) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Generates a storage path for a chapter image.
  Format: webtoons/{slug}/chapters/{chapter_number}/{sequence}.{ext}
  """
  def image_path(webtoon_slug, chapter_number, sequence, extension) do
    chapter_str = format_chapter_number(chapter_number)
    "webtoons/#{webtoon_slug}/chapters/#{chapter_str}/#{sequence}.#{extension}"
  end

  defp format_chapter_number(number) when is_float(number) do
    if number == Float.floor(number) do
      number |> trunc() |> to_string()
    else
      to_string(number)
    end
  end

  defp format_chapter_number(%Decimal{} = number) do
    if Decimal.equal?(number, Decimal.round(number, 0)) do
      number |> Decimal.round(0) |> Decimal.to_string()
    else
      Decimal.to_string(number)
    end
  end

  defp format_chapter_number(number) when is_integer(number), do: to_string(number)
  defp format_chapter_number(number) when is_binary(number), do: number

  defp bucket_name do
    Application.get_env(:webtoon_shared, :r2_bucket) ||
      raise "R2_BUCKET not configured"
  end

  defp config do
    account_id =
      Application.get_env(:webtoon_shared, :r2_account_id) ||
        raise "R2_ACCOUNT_ID not configured"

    [
      access_key_id:
        Application.get_env(:webtoon_shared, :r2_access_key_id) ||
          raise("R2_ACCESS_KEY_ID not configured"),
      secret_access_key:
        Application.get_env(:webtoon_shared, :r2_secret_access_key) ||
          raise("R2_SECRET_ACCESS_KEY not configured"),
      host: "#{account_id}.r2.cloudflarestorage.com",
      region: "auto"
    ]
  end
end
