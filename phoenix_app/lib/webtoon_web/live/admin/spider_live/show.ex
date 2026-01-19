defmodule WebtoonWeb.Admin.SpiderLive.Show do
  @moduledoc """
  Admin LiveView for viewing a specific spider's details.
  """

  use WebtoonWeb, :live_view

  alias Webtoon.Admin

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    config = Admin.get_spider_config!(name)
    recent_runs = Admin.list_runs(spider_name: name, limit: 10)

    {:ok,
     socket
     |> assign(:page_title, "Spider: #{name}")
     |> assign(:active_tab, :spiders)
     |> assign(:spider_name, name)
     |> assign(:config, config)
     |> assign(:recent_runs, recent_runs),
     layout: {WebtoonWeb.Layouts, :admin}}
  end

  @impl true
  def handle_event("toggle_spider", _, socket) do
    Admin.toggle_spider(socket.assigns.spider_name, !socket.assigns.config.enabled)
    config = Admin.get_spider_config!(socket.assigns.spider_name)
    {:noreply, assign(socket, :config, config)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center mb-6">
        <.link navigate={~p"/admin/spiders"} class="text-gray-500 hover:text-gray-700 mr-4">
          &larr; Back
        </.link>
        <h1 class="text-2xl font-bold">{@spider_name}</h1>
        <span class={"ml-3 inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{if @config.enabled, do: "bg-green-100 text-green-800", else: "bg-red-100 text-red-800"}"}>
          {if @config.enabled, do: "Enabled", else: "Disabled"}
        </span>
      </div>

      <!-- Configuration -->
      <div class="bg-white rounded-lg shadow mb-6">
        <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
          <h2 class="text-lg font-semibold">Configuration</h2>
          <button
            phx-click="toggle_spider"
            class={"px-4 py-2 rounded-lg text-sm font-medium #{if @config.enabled, do: "bg-red-100 text-red-800 hover:bg-red-200", else: "bg-green-100 text-green-800 hover:bg-green-200"}"}
          >
            {if @config.enabled, do: "Disable Spider", else: "Enable Spider"}
          </button>
        </div>
        <div class="p-6 grid grid-cols-1 md:grid-cols-3 gap-6">
          <div>
            <p class="text-sm text-gray-500">Max chapters per run</p>
            <p class="text-lg font-semibold">{@config.max_chapters_per_run}</p>
          </div>
          <div>
            <p class="text-sm text-gray-500">Request delay</p>
            <p class="text-lg font-semibold">{@config.request_delay_ms}ms</p>
          </div>
          <div>
            <p class="text-sm text-gray-500">Last run</p>
            <p class="text-lg font-semibold">{format_datetime(@config.last_run_at) || "Never"}</p>
          </div>
        </div>
      </div>

      <!-- Recent Runs -->
      <div class="bg-white rounded-lg shadow">
        <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
          <h2 class="text-lg font-semibold">Recent Runs</h2>
          <.link
            navigate={~p"/admin/spiders/#{@spider_name}/runs"}
            class="text-blue-600 hover:text-blue-800 text-sm"
          >
            View All
          </.link>
        </div>
        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Status
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Chapters
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Images
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Errors
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Started
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Duration
                </th>
                <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <tr :for={run <- @recent_runs} class="hover:bg-gray-50">
                <td class="px-6 py-4 whitespace-nowrap">
                  <.status_badge status={run.status} />
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {run.chapters_processed}/{run.chapters_found}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {run.images_downloaded}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm">
                  <span class={if run.errors_count > 0, do: "text-red-600", else: "text-gray-500"}>
                    {run.errors_count}
                  </span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {format_datetime(run.started_at)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {format_duration(run.started_at, run.completed_at)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                  <.link
                    navigate={~p"/admin/runs/#{run.id}"}
                    class="text-blue-600 hover:text-blue-900"
                  >
                    Details
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>

          <div :if={Enum.empty?(@recent_runs)} class="px-6 py-8 text-center text-gray-500">
            No runs yet
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

  defp format_duration(nil, _), do: "-"
  defp format_duration(_, nil), do: "running..."

  defp format_duration(started, completed) do
    seconds = DateTime.diff(completed, started)

    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      true -> "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
    end
  end
end
