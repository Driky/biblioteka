defmodule WebtoonWeb.Admin.RunLive.Index do
  @moduledoc """
  Admin LiveView for listing all spider runs.
  """

  use WebtoonWeb, :live_view

  alias Webtoon.Admin

  @impl true
  def mount(_params, _session, socket) do
    runs = Admin.list_runs(limit: 50)

    {:ok,
     socket
     |> assign(:page_title, "All Runs")
     |> assign(:active_tab, :runs)
     |> assign(:runs, runs)
     |> assign(:status_filter, nil)
     |> assign(:spider_filter, nil),
     layout: {WebtoonWeb.Layouts, :admin}}
  end

  @impl true
  def handle_event("filter", params, socket) do
    status = if params["status"] == "", do: nil, else: params["status"]
    spider = if params["spider"] == "", do: nil, else: params["spider"]

    opts = [limit: 50]
    opts = if status, do: Keyword.put(opts, :status, status), else: opts
    opts = if spider, do: Keyword.put(opts, :spider_name, spider), else: opts

    runs = Admin.list_runs(opts)

    {:noreply,
     socket
     |> assign(:runs, runs)
     |> assign(:status_filter, status)
     |> assign(:spider_filter, spider)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold mb-6">All Runs</h1>

      <!-- Filters -->
      <div class="bg-white rounded-lg shadow p-4 mb-6">
        <form phx-change="filter" class="flex items-center space-x-4">
          <div>
            <label class="block text-xs text-gray-500 mb-1">Spider</label>
            <select
              name="spider"
              class="border border-gray-300 rounded-lg px-3 py-2 text-sm focus:ring-blue-500 focus:border-blue-500"
            >
              <option value="" selected={is_nil(@spider_filter)}>All spiders</option>
              <option :for={name <- Admin.known_spiders()} value={name} selected={@spider_filter == name}>
                {name}
              </option>
            </select>
          </div>
          <div>
            <label class="block text-xs text-gray-500 mb-1">Status</label>
            <select
              name="status"
              class="border border-gray-300 rounded-lg px-3 py-2 text-sm focus:ring-blue-500 focus:border-blue-500"
            >
              <option value="" selected={is_nil(@status_filter)}>All statuses</option>
              <option value="running" selected={@status_filter == "running"}>Running</option>
              <option value="completed" selected={@status_filter == "completed"}>Completed</option>
              <option value="failed" selected={@status_filter == "failed"}>Failed</option>
            </select>
          </div>
        </form>
      </div>

      <div class="bg-white rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Spider
              </th>
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
            <tr :for={run <- @runs} class="hover:bg-gray-50">
              <td class="px-6 py-4 whitespace-nowrap">
                <.link
                  navigate={~p"/admin/spiders/#{run.spider_name}"}
                  class="text-blue-600 hover:text-blue-800"
                >
                  {run.spider_name}
                </.link>
              </td>
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
                <span class={if run.errors_count > 0, do: "text-red-600 font-medium", else: "text-gray-500"}>
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
                <.link navigate={~p"/admin/runs/#{run.id}"} class="text-blue-600 hover:text-blue-900">
                  Details
                </.link>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={Enum.empty?(@runs)} class="px-6 py-8 text-center text-gray-500">
          No runs found.
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

  defp format_datetime(nil), do: "-"

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
