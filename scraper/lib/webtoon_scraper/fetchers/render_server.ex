defmodule WebtoonScraper.Fetchers.RenderServer do
  @moduledoc """
  Custom fetcher that uses a render server (headless Chrome) for JavaScript-rendered pages.
  Supports scrolling for lazy-loaded content and automatic retries.

  ## Options (passed via request.options)

  - `:scroll` - Whether to scroll the page to load lazy content (default: false)
  - `:expected_images` - Expected number of images (helps scrolling know when to stop)
  """

  @behaviour Crawly.Fetchers.Fetcher

  require Logger

  @max_retries 3
  @retry_delays [2_000, 4_000, 8_000]

  @impl true
  def fetch(request, client_options) do
    base_url = Keyword.get(client_options, :base_url, "http://localhost:3000/render")

    Logger.info("RenderServer.fetch called for: #{inspect(request.url)}")

    # Ensure we have a valid request - handle various input types
    {url, options} =
      case request do
        %Crawly.Request{url: url, options: opts} when is_binary(url) ->
          {url, opts || []}

        %{url: url, options: opts} when is_binary(url) ->
          {url, opts || []}

        %{url: url} when is_binary(url) ->
          {url, []}

        url when is_binary(url) ->
          {url, []}

        :ok ->
          Logger.warning("RenderServer received :ok instead of request - queue may be empty")
          {nil, []}

        nil ->
          Logger.warning("RenderServer received nil request")
          {nil, []}

        other ->
          Logger.error("RenderServer received invalid request type: #{inspect(other)}")
          {nil, []}
      end

    if is_nil(url) do
      {:error, :invalid_request}
    else
      do_fetch_with_retry(url, options, base_url, 0)
    end
  end

  defp do_fetch_with_retry(url, options, base_url, attempt) do
    attempt_info = if attempt > 0, do: " (retry #{attempt}/#{@max_retries})", else: ""
    Logger.info("RenderServer fetching: #{url}#{attempt_info}")

    # Check if scrolling is requested (for chapter pages with lazy images)
    scroll = Keyword.get(options, :scroll, false)
    expected_images = Keyword.get(options, :expected_images)

    Logger.debug("RenderServer options for #{url}: scroll=#{scroll}, expected_images=#{inspect(expected_images)}, all_options=#{inspect(Keyword.keys(options))}")

    # Build the render server request
    body_map = %{
      url: url,
      headers: format_headers_from_options(options),
      scroll: scroll
    }

    # Add expected_images only if provided
    body_map =
      if expected_images do
        Map.put(body_map, :expectedImages, expected_images)
      else
        body_map
      end

    body = Jason.encode!(body_map)
    headers = [{"Content-Type", "application/json"}]

    # Timeout settings - increase for scrolling pages
    timeout = if scroll, do: 120_000, else: 60_000

    http_options = [
      recv_timeout: timeout,
      timeout: timeout,
      connect_timeout: 10_000,
      # Disable connection pooling to avoid pool timeout issues
      hackney: [pool: false]
    ]

    Logger.debug("RenderServer making HTTP request to #{base_url} with timeout #{timeout}ms")

    case HTTPoison.post(base_url, body, headers, http_options) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        Logger.debug("RenderServer got 200 response, decoding JSON")
        case Jason.decode(response_body) do
          {:ok, %{"body" => html}} when is_binary(html) and html != "" ->
            Logger.info("RenderServer success for #{url}, body length: #{String.length(html)}")
            {:ok, %HTTPoison.Response{
              status_code: 200,
              body: html,
              headers: [],
              request_url: url
            }}

          {:ok, %{"body" => nil}} ->
            Logger.warning("RenderServer returned null body for #{url}")
            maybe_retry(url, options, base_url, attempt, :null_body)

          {:ok, %{"body" => ""}} ->
            Logger.warning("RenderServer returned empty body for #{url}")
            maybe_retry(url, options, base_url, attempt, :empty_body)

          {:ok, %{"error" => error}} ->
            Logger.error("Render server error for #{url}: #{error}")
            maybe_retry(url, options, base_url, attempt, error)

          {:error, decode_error} ->
            Logger.error("Failed to decode render server response: #{inspect(decode_error)}")
            maybe_retry(url, options, base_url, attempt, :decode_error)
        end

      {:ok, %HTTPoison.Response{status_code: status_code, body: resp_body}} when status_code in [408, 429, 500, 502, 503, 504] ->
        Logger.warning("Render server returned #{status_code} for #{url}")
        maybe_retry(url, options, base_url, attempt, {:http_error, status_code})

      {:ok, %HTTPoison.Response{status_code: status_code, body: resp_body}} ->
        Logger.error("Render server returned #{status_code} for #{url}: #{String.slice(resp_body || "", 0, 200)}")
        {:error, {:http_error, status_code}}

      {:error, %HTTPoison.Error{reason: reason}} when reason in [:timeout, :connect_timeout, :closed, :econnrefused] ->
        Logger.warning("RenderServer request failed (retryable) for #{url}: #{inspect(reason)}")
        maybe_retry(url, options, base_url, attempt, reason)

      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error("RenderServer request failed for #{url}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp maybe_retry(url, options, base_url, attempt, error) when attempt < @max_retries do
    delay = Enum.at(@retry_delays, attempt, 8_000)
    Logger.info("RenderServer retrying #{url} in #{delay}ms (attempt #{attempt + 1}/#{@max_retries})...")
    Process.sleep(delay)
    do_fetch_with_retry(url, options, base_url, attempt + 1)
  end

  defp maybe_retry(url, _options, _base_url, attempt, error) do
    Logger.error("RenderServer giving up on #{url} after #{attempt + 1} attempts, error: #{inspect(error)}")
    {:error, error}
  end

  defp format_headers_from_options(options) do
    Keyword.get(options, :headers, [])
  end
end
