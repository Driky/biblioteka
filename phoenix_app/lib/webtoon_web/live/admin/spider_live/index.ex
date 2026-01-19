defmodule WebtoonWeb.Admin.SpiderLive.Index do
  @moduledoc """
  Admin LiveView for listing and managing spiders.
  """

  use WebtoonWeb, :live_view

  alias Webtoon.Admin

  @impl true
  def mount(_params, _session, socket) do
    spiders = get_spider_list()

    {:ok,
     socket
     |> assign(:page_title, "Spiders")
     |> assign(:active_tab, :spiders)
     |> assign(:spiders, spiders),
     layout: {WebtoonWeb.Layouts, :admin}}
  end

  defp get_spider_list do
    # Get known spiders and their configs
    Admin.known_spiders()
    |> Enum.map(fn name ->
      config = Admin.get_spider_config!(name)
      last_run = get_last_run(name)

      %{
        name: name,
        config: config,
        last_run: last_run
      }
    end)
  end

  defp get_last_run(spider_name) do
    Admin.list_runs(spider_name: spider_name, limit: 1)
    |> List.first()
  end

  @impl true
  def handle_event("toggle_spider", %{"name" => name, "enabled" => enabled}, socket) do
    enabled = enabled == "true"
    Admin.toggle_spider(name, !enabled)
    spiders = get_spider_list()
    {:noreply, assign(socket, :spiders, spiders)}
  end

  @impl true
  def handle_event("update_config", %{"name" => name, "field" => field, "value" => value}, socket) do
    config = Admin.get_or_create_spider_config(name)

    attrs =
      case field do
        "max_chapters_per_run" -> %{max_chapters_per_run: String.to_integer(value)}
        "request_delay_ms" -> %{request_delay_ms: String.to_integer(value)}
        _ -> %{}
      end

    Admin.update_spider_config(config, attrs)
    spiders = get_spider_list()
    {:noreply, assign(socket, :spiders, spiders)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold mb-6">Spiders</h1>

      <div class="grid gap-6">
        <div :for={spider <- @spiders} class="bg-white rounded-lg shadow">
          <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
            <div class="flex items-center">
              <h2 class="text-lg font-semibold">{spider.name}</h2>
              <span class={"ml-3 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{if spider.config.enabled, do: "bg-green-100 text-green-800", else: "bg-red-100 text-red-800"}"}>
                {if spider.config.enabled, do: "Enabled", else: "Disabled"}
              </span>
            </div>
            <div class="flex items-center space-x-4">
              <.link
                navigate={~p"/admin/spiders/#{spider.name}/runs"}
                class="text-blue-600 hover:text-blue-800 text-sm"
              >
                View Runs
              </.link>
              <button
                phx-click="toggle_spider"
                phx-value-name={spider.name}
                phx-value-enabled={to_string(spider.config.enabled)}
                class={"relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none #{if spider.config.enabled, do: "bg-blue-600", else: "bg-gray-200"}"}
              >
                <span class={"inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out #{if spider.config.enabled, do: "translate-x-5", else: "translate-x-0"}"}>
                </span>
              </button>
            </div>
          </div>

          <div class="p-6">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
              <!-- Config -->
              <div>
                <h3 class="text-sm font-medium text-gray-500 mb-3">Configuration</h3>
                <div class="space-y-3">
                  <div>
                    <label class="block text-xs text-gray-500">Max chapters per run</label>
                    <input
                      type="number"
                      min="1"
                      max="100"
                      value={spider.config.max_chapters_per_run}
                      phx-blur="update_config"
                      phx-value-name={spider.name}
                      phx-value-field="max_chapters_per_run"
                      class="mt-1 block w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:ring-blue-500 focus:border-blue-500"
                    />
                  </div>
                  <div>
                    <label class="block text-xs text-gray-500">Request delay (ms)</label>
                    <input
                      type="number"
                      min="0"
                      step="100"
                      value={spider.config.request_delay_ms}
                      phx-blur="update_config"
                      phx-value-name={spider.name}
                      phx-value-field="request_delay_ms"
                      class="mt-1 block w-full border border-gray-300 rounded-lg px-3 py-2 text-sm focus:ring-blue-500 focus:border-blue-500"
                    />
                  </div>
                </div>
              </div>

              <!-- Last Run -->
              <div>
                <h3 class="text-sm font-medium text-gray-500 mb-3">Last Run</h3>
                <div :if={spider.last_run}>
                  <div class="flex items-center mb-2">
                    <.status_badge status={spider.last_run.status} />
                    <span class="ml-2 text-sm text-gray-500">
                      {format_datetime(spider.last_run.started_at)}
                    </span>
                  </div>
                  <div class="text-sm text-gray-600">
                    <p>Chapters: {spider.last_run.chapters_processed}/{spider.last_run.chapters_found}</p>
                    <p>Images: {spider.last_run.images_downloaded}</p>
                    <p :if={spider.last_run.errors_count > 0} class="text-red-600">
                      Errors: {spider.last_run.errors_count}
                    </p>
                  </div>
                </div>
                <p :if={!spider.last_run} class="text-sm text-gray-400">No runs yet</p>
              </div>

              <!-- Quick Stats -->
              <div>
                <h3 class="text-sm font-medium text-gray-500 mb-3">Stats</h3>
                <p class="text-sm text-gray-600">
                  Last run at: {format_datetime(spider.config.last_run_at) || "Never"}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    color =
      case assigns.status do
        "running" -> "blue"
        "completed" -> "green"
        "failed" -> "red"
        _ -> "gray"
      end

    assigns = assign(assigns, :color, color)

    ~H"""
    <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-#{@color}-100 text-#{@color}-800"}>
      {@status}
    </span>
    """
  end

  defp format_datetime(nil), do: nil

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end
end
