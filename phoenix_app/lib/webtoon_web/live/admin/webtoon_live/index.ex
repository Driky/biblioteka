defmodule WebtoonWeb.Admin.WebtoonLive.Index do
  @moduledoc """
  Admin LiveView for listing and managing webtoons.
  """

  use WebtoonWeb, :live_view

  alias Webtoon.Admin
  alias WebtoonShared.Schema.Webtoon

  @impl true
  def mount(_params, _session, socket) do
    webtoons = Admin.list_webtoons()

    {:ok,
     socket
     |> assign(:page_title, "Webtoons")
     |> assign(:active_tab, :webtoons)
     |> assign(:webtoons, webtoons)
     |> assign(:show_modal, false)
     |> assign(:form, to_form(%{})),
     layout: {WebtoonWeb.Layouts, :admin}}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:show_modal, true)
    |> assign(:form, to_form(%{"title" => "", "source_url" => "", "site_id" => "mangahub"}))
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:show_modal, false)
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/webtoons")}
  end

  @impl true
  def handle_event("create_webtoon", %{"title" => title, "source_url" => source_url, "site_id" => site_id}, socket) do
    slug = Webtoon.generate_slug(title)

    case Admin.create_webtoon(%{title: title, slug: slug}) do
      {:ok, webtoon} ->
        # Also create the source
        Admin.add_source_to_webtoon(webtoon.id, %{
          source_url: source_url,
          site_id: site_id
        })

        webtoons = Admin.list_webtoons()

        {:noreply,
         socket
         |> assign(:webtoons, webtoons)
         |> put_flash(:info, "Webtoon created successfully")
         |> push_patch(to: ~p"/admin/webtoons")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create webtoon")}
    end
  end

  @impl true
  def handle_event("toggle_crawl", %{"source-id" => source_id, "enabled" => enabled}, socket) do
    enabled = enabled == "true"
    Admin.toggle_source_crawl(source_id, !enabled)
    webtoons = Admin.list_webtoons()

    {:noreply, assign(socket, :webtoons, webtoons)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex justify-between items-center mb-6">
        <h1 class="text-2xl font-bold">Webtoons</h1>
        <.link
          patch={~p"/admin/webtoons/new"}
          class="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700"
        >
          Add Webtoon
        </.link>
      </div>

      <!-- Webtoons Table -->
      <div class="bg-white rounded-lg shadow overflow-hidden">
        <table class="min-w-full divide-y divide-gray-200">
          <thead class="bg-gray-50">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Webtoon
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Source
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Chapters
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Issues
              </th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Crawl
              </th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="bg-white divide-y divide-gray-200">
            <tr :for={webtoon <- @webtoons} class="hover:bg-gray-50">
              <td class="px-6 py-4 whitespace-nowrap">
                <div class="flex items-center">
                  <div
                    :if={webtoon.cover_url}
                    class="h-10 w-10 rounded bg-gray-200 overflow-hidden mr-3"
                  >
                    <img src={storage_url(webtoon.cover_url)} class="h-full w-full object-cover" />
                  </div>
                  <div :if={!webtoon.cover_url} class="h-10 w-10 rounded bg-gray-200 mr-3"></div>
                  <div>
                    <.link
                      navigate={~p"/admin/webtoons/#{webtoon.id}"}
                      class="text-sm font-medium text-gray-900 hover:text-blue-600"
                    >
                      {webtoon.title}
                    </.link>
                    <p class="text-xs text-gray-500">{webtoon.slug}</p>
                  </div>
                </div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <div :for={source <- webtoon.sources} class="text-sm">
                  <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-800">
                    {source.site_id}
                  </span>
                </div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                {webtoon.stats.chapters_count}
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-sm">
                <span :if={webtoon.stats.chapters_missing_title > 0} class="text-orange-600">
                  {webtoon.stats.chapters_missing_title} missing titles
                </span>
                <span :if={webtoon.stats.chapters_missing_title == 0} class="text-green-600">
                  None
                </span>
              </td>
              <td class="px-6 py-4 whitespace-nowrap">
                <div :for={source <- webtoon.sources}>
                  <button
                    phx-click="toggle_crawl"
                    phx-value-source-id={source.id}
                    phx-value-enabled={to_string(source.crawl_enabled)}
                    class={"relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none #{if source.crawl_enabled, do: "bg-blue-600", else: "bg-gray-200"}"}
                  >
                    <span class={"inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out #{if source.crawl_enabled, do: "translate-x-5", else: "translate-x-0"}"}>
                    </span>
                  </button>
                </div>
              </td>
              <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                <.link
                  navigate={~p"/admin/webtoons/#{webtoon.id}"}
                  class="text-blue-600 hover:text-blue-900"
                >
                  Manage
                </.link>
              </td>
            </tr>
          </tbody>
        </table>

        <div :if={Enum.empty?(@webtoons)} class="px-6 py-8 text-center text-gray-500">
          No webtoons yet.
          <.link patch={~p"/admin/webtoons/new"} class="text-blue-600 hover:text-blue-800">
            Add one now
          </.link>
        </div>
      </div>

      <!-- New Webtoon Modal -->
      <div
        :if={@show_modal}
        class="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50"
        phx-click="close_modal"
      >
        <div class="bg-white rounded-lg shadow-xl p-6 w-full max-w-md" phx-click-away="close_modal">
          <h2 class="text-lg font-semibold mb-4">Add New Webtoon</h2>
          <form phx-submit="create_webtoon">
            <div class="mb-4">
              <label class="block text-sm font-medium text-gray-700 mb-1">Title</label>
              <input
                type="text"
                name="title"
                required
                class="w-full border border-gray-300 rounded-lg px-3 py-2 focus:ring-blue-500 focus:border-blue-500"
                placeholder="Webtoon title"
              />
            </div>
            <div class="mb-4">
              <label class="block text-sm font-medium text-gray-700 mb-1">Source Site</label>
              <select
                name="site_id"
                class="w-full border border-gray-300 rounded-lg px-3 py-2 focus:ring-blue-500 focus:border-blue-500"
              >
                <option value="mangahub">MangaHub</option>
                <option value="mangadex">MangaDex</option>
              </select>
            </div>
            <div class="mb-6">
              <label class="block text-sm font-medium text-gray-700 mb-1">Source URL</label>
              <input
                type="url"
                name="source_url"
                required
                class="w-full border border-gray-300 rounded-lg px-3 py-2 focus:ring-blue-500 focus:border-blue-500"
                placeholder="https://mangahub.io/manga/..."
              />
            </div>
            <div class="flex justify-end space-x-3">
              <button
                type="button"
                phx-click="close_modal"
                class="px-4 py-2 text-gray-700 hover:text-gray-900"
              >
                Cancel
              </button>
              <button
                type="submit"
                class="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700"
              >
                Create
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
