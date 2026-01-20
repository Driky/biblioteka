defmodule WebtoonWeb.Admin.WebtoonLive.Show do
  @moduledoc """
  Admin LiveView for viewing and managing a specific webtoon and its chapters.
  """

  use WebtoonWeb, :live_view

  alias Webtoon.Admin
  alias WebtoonShared.Schema.Chapter

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    webtoon = Admin.get_webtoon!(id)
    chapters = Admin.get_webtoon_chapters(id)
    stats = Admin.get_webtoon_stats(id)

    {:ok,
     socket
     |> assign(:page_title, webtoon.title)
     |> assign(:active_tab, :webtoons)
     |> assign(:webtoon, webtoon)
     |> assign(:chapters, chapters)
     |> assign(:stats, stats)
     |> assign(:filter, :all)
     |> assign(:selected_chapters, MapSet.new()),
     layout: {WebtoonWeb.Layouts, :admin}}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params), do: socket
  defp apply_action(socket, :edit, _params), do: assign(socket, :editing, true)

  @impl true
  def handle_event("filter_chapters", %{"filter" => filter}, socket) do
    filter = String.to_existing_atom(filter)
    chapters = Admin.get_webtoon_chapters(socket.assigns.webtoon.id, filter: filter)

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> assign(:chapters, chapters)
     |> assign(:selected_chapters, MapSet.new())}
  end

  @impl true
  def handle_event("toggle_chapter", %{"chapter-id" => chapter_id}, socket) do
    selected = socket.assigns.selected_chapters

    selected =
      if MapSet.member?(selected, chapter_id) do
        MapSet.delete(selected, chapter_id)
      else
        MapSet.put(selected, chapter_id)
      end

    {:noreply, assign(socket, :selected_chapters, selected)}
  end

  @impl true
  def handle_event("select_all", _, socket) do
    chapter_ids = Enum.map(socket.assigns.chapters, & &1.id)
    {:noreply, assign(socket, :selected_chapters, MapSet.new(chapter_ids))}
  end

  @impl true
  def handle_event("deselect_all", _, socket) do
    {:noreply, assign(socket, :selected_chapters, MapSet.new())}
  end

  @impl true
  def handle_event("mark_for_rescrape", %{"type" => type}, socket) do
    type = String.to_existing_atom(type)
    chapter_ids = MapSet.to_list(socket.assigns.selected_chapters)

    if length(chapter_ids) > 0 do
      Admin.mark_chapters_for_rescrape(chapter_ids, type)

      # Refresh chapters
      chapters = Admin.get_webtoon_chapters(socket.assigns.webtoon.id, filter: socket.assigns.filter)

      {:noreply,
       socket
       |> assign(:chapters, chapters)
       |> assign(:selected_chapters, MapSet.new())
       |> put_flash(:info, "#{length(chapter_ids)} chapters marked for #{type} rescrape")}
    else
      {:noreply, put_flash(socket, :error, "No chapters selected")}
    end
  end

  @impl true
  def handle_event("toggle_source_crawl", %{"source-id" => source_id, "enabled" => enabled}, socket) do
    enabled = enabled == "true"
    Admin.toggle_source_crawl(source_id, !enabled)
    webtoon = Admin.get_webtoon!(socket.assigns.webtoon.id)
    {:noreply, assign(socket, :webtoon, webtoon)}
  end

  @impl true
  def handle_event("mark_missing_titles_for_rescrape", _, socket) do
    count = Admin.mark_chapters_without_title_for_rescrape(socket.assigns.webtoon.id)

    # Refresh chapters and stats
    chapters = Admin.get_webtoon_chapters(socket.assigns.webtoon.id, filter: socket.assigns.filter)
    stats = Admin.get_webtoon_stats(socket.assigns.webtoon.id)

    {:noreply,
     socket
     |> assign(:chapters, chapters)
     |> assign(:stats, stats)
     |> put_flash(:info, "#{count} chapters without title marked for rescrape")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- Header -->
      <div class="flex justify-between items-start mb-6">
        <div class="flex items-center">
          <.link navigate={~p"/admin/webtoons"} class="text-gray-500 hover:text-gray-700 mr-4">
            &larr; Back
          </.link>
          <div>
            <h1 class="text-2xl font-bold">{@webtoon.title}</h1>
            <p class="text-sm text-gray-500">{@webtoon.slug}</p>
          </div>
        </div>
      </div>

      <!-- Stats -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <div class="bg-white rounded-lg shadow p-4">
          <p class="text-sm text-gray-500">Total Chapters</p>
          <p class="text-2xl font-semibold">{@stats.chapters_count}</p>
        </div>
        <div class="bg-white rounded-lg shadow p-4">
          <p class="text-sm text-gray-500">With Images</p>
          <p class="text-2xl font-semibold">{@stats.chapters_with_images}</p>
        </div>
        <div class="bg-white rounded-lg shadow p-4">
          <p class="text-sm text-gray-500">Missing Titles</p>
          <p class="text-2xl font-semibold text-orange-600">{@stats.chapters_missing_title}</p>
          <button
            :if={@stats.chapters_missing_title > 0}
            phx-click="mark_missing_titles_for_rescrape"
            class="mt-2 text-xs bg-orange-100 text-orange-800 px-2 py-1 rounded hover:bg-orange-200"
          >
            Mark all for rescrape
          </button>
        </div>
      </div>

      <!-- Sources -->
      <div class="bg-white rounded-lg shadow mb-6">
        <div class="px-6 py-4 border-b border-gray-200">
          <h2 class="text-lg font-semibold">Sources</h2>
        </div>
        <div class="p-6">
          <div :for={source <- @webtoon.sources} class="flex items-center justify-between py-2">
            <div>
              <span class="inline-flex items-center px-2.5 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800 mr-2">
                {source.site_id}
              </span>
              <a
                href={source.source_url}
                target="_blank"
                class="text-sm text-gray-600 hover:text-blue-600"
              >
                {source.source_url}
              </a>
            </div>
            <div class="flex items-center space-x-4">
              <span class="text-sm text-gray-500">
                Last chapter: {format_chapter_number(source.last_chapter_scraped)}
              </span>
              <button
                phx-click="toggle_source_crawl"
                phx-value-source-id={source.id}
                phx-value-enabled={to_string(source.crawl_enabled)}
                class={"relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none #{if source.crawl_enabled, do: "bg-blue-600", else: "bg-gray-200"}"}
              >
                <span class={"inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out #{if source.crawl_enabled, do: "translate-x-5", else: "translate-x-0"}"}>
                </span>
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Chapters -->
      <div class="bg-white rounded-lg shadow">
        <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
          <h2 class="text-lg font-semibold">Chapters</h2>
          <div class="flex items-center space-x-4">
            <!-- Filter -->
            <select
              phx-change="filter_chapters"
              name="filter"
              class="border border-gray-300 rounded-lg px-3 py-1.5 text-sm focus:ring-blue-500 focus:border-blue-500"
            >
              <option value="all" selected={@filter == :all}>All chapters</option>
              <option value="missing_title" selected={@filter == :missing_title}>
                Missing title
              </option>
              <option value="needs_rescrape" selected={@filter == :needs_rescrape}>
                Needs rescrape
              </option>
            </select>

            <!-- Bulk Actions -->
            <div :if={MapSet.size(@selected_chapters) > 0} class="flex items-center space-x-2">
              <span class="text-sm text-gray-600">
                {MapSet.size(@selected_chapters)} selected
              </span>
              <button
                phx-click="mark_for_rescrape"
                phx-value-type="full"
                class="text-sm bg-yellow-100 text-yellow-800 px-3 py-1 rounded hover:bg-yellow-200"
              >
                Mark Full Rescrape
              </button>
              <button
                phx-click="mark_for_rescrape"
                phx-value-type="title"
                class="text-sm bg-orange-100 text-orange-800 px-3 py-1 rounded hover:bg-orange-200"
              >
                Rescrape Title
              </button>
              <button
                phx-click="mark_for_rescrape"
                phx-value-type="images"
                class="text-sm bg-purple-100 text-purple-800 px-3 py-1 rounded hover:bg-purple-200"
              >
                Rescrape Images
              </button>
            </div>
          </div>
        </div>

        <div class="overflow-x-auto">
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left">
                  <button
                    :if={length(@chapters) > 0}
                    phx-click={if MapSet.size(@selected_chapters) == length(@chapters), do: "deselect_all", else: "select_all"}
                    class="text-xs text-gray-500 hover:text-gray-700"
                  >
                    {if MapSet.size(@selected_chapters) == length(@chapters), do: "Deselect all", else: "Select all"}
                  </button>
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Chapter
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Title
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Images
                </th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  Status
                </th>
              </tr>
            </thead>
            <tbody class="bg-white divide-y divide-gray-200">
              <tr :for={chapter <- @chapters} class="hover:bg-gray-50">
                <td class="px-6 py-4 whitespace-nowrap">
                  <input
                    type="checkbox"
                    checked={MapSet.member?(@selected_chapters, chapter.id)}
                    phx-click="toggle_chapter"
                    phx-value-chapter-id={chapter.id}
                    class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                  />
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                  {Chapter.format_number(chapter)}
                </td>
                <td class="px-6 py-4 text-sm text-gray-900">
                  <span :if={chapter.title}>{chapter.title}</span>
                  <span :if={!chapter.title} class="text-gray-400 italic">No title</span>
                </td>
                <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {length(chapter.images)}
                </td>
                <td class="px-6 py-4 whitespace-nowrap">
                  <div class="flex space-x-1">
                    <span
                      :if={chapter.needs_rescrape}
                      class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-yellow-100 text-yellow-800"
                    >
                      Rescrape
                    </span>
                    <span
                      :if={chapter.needs_title_rescrape}
                      class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-orange-100 text-orange-800"
                    >
                      Title
                    </span>
                    <span
                      :if={chapter.needs_images_rescrape}
                      class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-purple-100 text-purple-800"
                    >
                      Images
                    </span>
                    <span
                      :if={!chapter.needs_rescrape && !chapter.needs_title_rescrape && !chapter.needs_images_rescrape}
                      class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800"
                    >
                      OK
                    </span>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>

          <div :if={Enum.empty?(@chapters)} class="px-6 py-8 text-center text-gray-500">
            No chapters found with the current filter.
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_chapter_number(nil), do: "-"
  defp format_chapter_number(%Decimal{} = number), do: Chapter.format_number(%Chapter{chapter_number: number})
  defp format_chapter_number(number), do: to_string(number)
end
