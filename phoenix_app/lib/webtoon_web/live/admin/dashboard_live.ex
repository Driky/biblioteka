defmodule WebtoonWeb.Admin.DashboardLive do
  @moduledoc """
  Admin dashboard showing overall system stats and recent activity.
  """

  use WebtoonWeb, :live_view

  alias Webtoon.Admin

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Refresh stats every 30 seconds
      :timer.send_interval(30_000, self(), :refresh_stats)
    end

    stats = Admin.get_dashboard_stats()
    recent_runs = Admin.get_recent_runs()
    active_jobs = Admin.get_active_oban_jobs_count()

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:active_tab, :dashboard)
     |> assign(:stats, stats)
     |> assign(:recent_runs, recent_runs)
     |> assign(:active_jobs, active_jobs),
     layout: {WebtoonWeb.Layouts, :admin}}
  end

  @impl true
  def handle_info(:refresh_stats, socket) do
    stats = Admin.get_dashboard_stats()
    recent_runs = Admin.get_recent_runs()
    active_jobs = Admin.get_active_oban_jobs_count()

    {:noreply,
     socket
     |> assign(:stats, stats)
     |> assign(:recent_runs, recent_runs)
     |> assign(:active_jobs, active_jobs)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <h1 class="text-2xl font-bold mb-6">Dashboard</h1>

      <!-- Stats Grid -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
        <.stat_card title="Webtoons" value={@stats.webtoons_count} icon="book-open" />
        <.stat_card title="Chapters" value={@stats.chapters_count} icon="document" />
        <.stat_card title="Images" value={@stats.images_count} icon="photo" />
        <.stat_card
          title="Active Jobs"
          value={@active_jobs}
          icon="cog"
          color={if @active_jobs > 0, do: "blue", else: "gray"}
        />
      </div>

      <!-- Alerts / Needs Attention -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
        <.alert_card
          title="Pending Rescrape"
          value={@stats.chapters_pending_rescrape}
          color="yellow"
        />
        <.alert_card
          title="Missing Titles"
          value={@stats.chapters_needing_title}
          color="orange"
        />
        <.alert_card
          title="Errors (24h)"
          value={@stats.errors_24h}
          color={if @stats.errors_24h > 0, do: "red", else: "green"}
        />
      </div>

      <!-- Recent Runs -->
      <div class="bg-white rounded-lg shadow">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-lg font-semibold">Recent Spider Runs</h2>
        </div>
        <div class="overflow-x-auto">
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
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <tr :for={run <- @recent_runs} class="hover:bg-gray-50">
                <td class="px-6 py-4 whitespace-nowrap">
                  <.link navigate={~p"/admin/spiders/#{run.spider_name}"} class="text-blue-600 hover:text-blue-800">
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
              </tr>
            </tbody>
          </table>

          <div :if={Enum.empty?(@recent_runs)} class="px-6 py-8 text-center text-gray-500">
            No spider runs yet
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp stat_card(assigns) do
    assigns = assign_new(assigns, :color, fn -> "gray" end)

    ~H"""
    <div class="bg-white rounded-lg shadow p-6">
      <div class="flex items-center">
        <div class={"rounded-full p-3 bg-#{@color}-100"}>
          <.icon name={@icon} class={"h-6 w-6 text-#{@color}-600"} />
        </div>
        <div class="ml-4">
          <p class="text-sm font-medium text-gray-500">{@title}</p>
          <p class="text-2xl font-semibold text-gray-900">{format_number(@value)}</p>
        </div>
      </div>
    </div>
    """
  end

  defp alert_card(assigns) do
    ~H"""
    <div class={"bg-#{@color}-50 rounded-lg p-6 border border-#{@color}-200"}>
      <p class={"text-sm font-medium text-#{@color}-800"}>{@title}</p>
      <p class={"text-2xl font-semibold text-#{@color}-900"}>{format_number(@value)}</p>
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

  defp icon(assigns) do
    # Simple icon component using heroicons-style names
    ~H"""
    <svg class={@class} fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <%= case @name do %>
        <% "book-open" -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253" />
        <% "document" -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
        <% "photo" -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
        <% "cog" -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
        <% _ -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
      <% end %>
    </svg>
    """
  end

  defp format_number(nil), do: "0"

  defp format_number(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_number(n), do: to_string(n)

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
