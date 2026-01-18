defmodule WebtoonScraper.Fetchers.RenderServer do
  @moduledoc """
  Custom fetcher that uses a render server (headless Chrome) for JavaScript-rendered pages.
  """

  @behaviour Crawly.Fetchers.Fetcher

  require Logger

  @impl true
  def fetch(request, client_options) do
    base_url = Keyword.get(client_options, :base_url, "http://localhost:3000/render")

    # Ensure we have a valid request
    url =
      case request do
        %{url: url} when is_binary(url) -> url
        url when is_binary(url) -> url
        other ->
          Logger.error("Invalid request received: #{inspect(other)}")
          nil
      end

    if is_nil(url) do
      {:error, :invalid_request}
    else
      Logger.debug("RenderServer fetching: #{url}")

      # Build the render server request
      body = Jason.encode!(%{url: url, headers: format_headers(request)})
      headers = [{"Content-Type", "application/json"}]

      case HTTPoison.post(base_url, body, headers, recv_timeout: 30_000, timeout: 30_000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, %{"body" => html}} ->
              {:ok, %HTTPoison.Response{
                status_code: 200,
                body: html,
                headers: [],
                request_url: url
              }}

            {:ok, %{"error" => error}} ->
              Logger.error("Render server error for #{url}: #{error}")
              {:error, error}

            {:error, decode_error} ->
              Logger.error("Failed to decode render server response: #{inspect(decode_error)}")
              {:error, :decode_error}
          end

        {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
          Logger.error("Render server returned #{status_code}: #{body}")
          {:error, {:http_error, status_code}}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("Render server request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp format_headers(%{headers: headers}) when is_list(headers), do: headers
  defp format_headers(_), do: []
end
