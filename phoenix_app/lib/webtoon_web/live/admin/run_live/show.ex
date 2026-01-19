defmodule WebtoonWeb.Admin.RunLive.Show do
  @moduledoc """
  Admin LiveView for viewing a specific spider run with errors.
  """

  use WebtoonWeb, :live_view

  alias Webtoon.Admin
  alias WebtoonShared.Schema.Chapter

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    run = Admin.get_run!(id)
    errors = Admin.get_run_errors(id)

    {:ok,
     socket
     |> assign(:page_title, "Run Details")
     |> assign(:active_tab, :runs)
     |> assign(:run, run)
     |> assign(:errors, errors)
     |> assign(:expanded_errors, MapSet.new()),
     layout: {WebtoonWeb.Layouts, :admin}}
  end

  @impl true
  def handle_event("toggle_error", %{"error-id" => error_id}, socket) do
    expanded = socket.assigns.expanded_errors

    expanded =
      if MapSet.member?(expanded, error_id) do
        MapSet.delete(expanded, error_id)
      else
        MapSet.put(expanded, error_id)
      end

    {:noreply, assign(socket, :expanded_errors, expanded)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex items-center mb-6">
        <.link navigate={~p"/admin/runs"} class="text-gray-500 hover:text-gray-700 mr-4">
          &larr; Back
        </.link>
        <h1 class="text-2xl font-bold">Run Details</h1>
      </div>

      <!-- Run Info -->
      <div class="bg-white rounded-lg shadow mb-6">
        <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
          <h2 class="text-lg font-semibold">{@run.spider_name}</h2>
          <.status_badge status={@run.status} />
        </div>
        <div class="p-6 grid grid-cols-2 md:grid-cols-4 gap-6">
          <div>
            <p class="text-sm text-gray-500">Chapters Found</p>
            <p class="text-2xl font-semibold">{@run.chapters_found}</p>
          </div>
          <div>
            <p class="text-sm text-gray-500">Chapters Processed</p>
            <p class="text-2xl font-semibold">{@run.chapters_processed}</p>
          </div>
          <div>
            <p class="text-sm text-gray-500">Images Downloaded</p>
            <p class="text-2xl font-semibold">{@run.images_downloaded}</p>
          </div>
          <div>
            <p class="text-sm text-gray-500">Errors</p>
            <p class={"text-2xl font-semibold #{if @run.errors_count > 0, do: "text-red-600"}"}>{@run.errors_count}</p>
          </div>
        </div>
        <div class="px-6 pb-6 grid grid-cols-2 md:grid-cols-3 gap-6 border-t border-gray-100 pt-4">
          <div>
            <p class="text-sm text-gray-500">Started</p>
            <p class="text-sm font-medium">{format_datetime(@run.started_at)}</p>
          </div>
          <div>
            <p class="text-sm text-gray-500">Completed</p>
            <p class="text-sm font-medium">{format_datetime(@run.completed_at) || "In progress..."}</p>
          </div>
          <div>
            <p class="text-sm text-gray-500">Duration</p>
            <p class="text-sm font-medium">{format_duration(@run.started_at, @run.completed_at)}</p>
          </div>
        </div>
      </div>

      <!-- Errors -->
      <div class="bg-white rounded-lg shadow">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-lg font-semibold">
            Errors
            <span :if={length(@errors) > 0} class="text-sm text-red-600 ml-2">
              ({length(@errors)})
            </span>
          </h2>
        </div>

        <div :if={Enum.empty?(@errors)} class="px-6 py-8 text-center text-gray-500">
          No errors recorded for this run.
        </div>

        <div :if={length(@errors) > 0} class="divide-y divide-gray-200">
          <div :for={error <- @errors} class="px-6 py-4">
            <div class="flex items-start justify-between">
              <div class="flex-1">
                <div class="flex items-center space-x-2">
                  <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800">
                    {error.error_type}
                  </span>
                  <span :if={error.webtoon} class="text-sm text-gray-600">
                    {error.webtoon.title}
                  </span>
                  <span :if={error.chapter_number} class="text-sm text-gray-500">
                    Chapter {format_chapter_number(error.chapter_number)}
                  </span>
                </div>
                <p class="mt-1 text-sm text-gray-800">{error.error_message}</p>
                <p class="mt-1 text-xs text-gray-400">{format_datetime(error.occurred_at)}</p>
              </div>
              <button
                :if={error.stacktrace}
                phx-click="toggle_error"
                phx-value-error-id={error.id}
                class="ml-4 text-sm text-blue-600 hover:text-blue-800"
              >
                {if MapSet.member?(@expanded_errors, error.id), do: "Hide", else: "Show"} Stacktrace
              </button>
            </div>

            <div
              :if={error.stacktrace && MapSet.member?(@expanded_errors, error.id)}
              class="mt-3 p-3 bg-gray-50 rounded-lg overflow-x-auto"
            >
              <pre class="text-xs text-gray-600 whitespace-pre-wrap">{error.stacktrace}</pre>
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

  defp format_chapter_number(nil), do: "-"
  defp format_chapter_number(%Decimal{} = number), do: Chapter.format_number(%Chapter{chapter_number: number})
  defp format_chapter_number(number), do: to_string(number)

  defp format_datetime(nil), do: nil

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
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
