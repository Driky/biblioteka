defmodule WebtoonWeb.ReaderLive do
  @moduledoc """
  Chapter reader LiveView with support for:
  - Webtoon mode (vertical scroll)
  - Manga mode (double-page spread, right-to-left)
  - Chapter preloading
  - Reading progress tracking
  """

  use WebtoonWeb, :live_view

  alias Webtoon.Webtoons

  @impl true
  def mount(%{"slug" => slug, "number" => number}, _session, socket) do
    case Webtoons.get_chapter_with_images(slug, number) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Chapter not found")
         |> push_navigate(to: ~p"/")}

      %{chapter: chapter, images: images, webtoon: webtoon} ->
        prev_chapter = Webtoons.get_previous_chapter(webtoon.id, chapter.chapter_number)
        next_chapter = Webtoons.get_next_chapter(webtoon.id, chapter.chapter_number)

        # Update reading progress
        Webtoons.update_reading_progress(webtoon.id, chapter.id)

        {:ok,
         assign(socket,
           page_title: "#{webtoon.title} - Chapter #{format_chapter_number(chapter.chapter_number)}",
           webtoon: webtoon,
           chapter: chapter,
           images: images,
           prev_chapter: prev_chapter,
           next_chapter: next_chapter,
           reading_mode: :webtoon,
           current_page: 0,
           preloaded_next: false,
           show_toolbar: true
         )}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_mode", _, socket) do
    new_mode =
      case socket.assigns.reading_mode do
        :webtoon -> :manga
        :manga -> :webtoon
      end

    {:noreply, assign(socket, reading_mode: new_mode, current_page: 0)}
  end

  @impl true
  def handle_event("toggle_toolbar", _, socket) do
    {:noreply, assign(socket, show_toolbar: !socket.assigns.show_toolbar)}
  end

  @impl true
  def handle_event("prev_page", _, socket) do
    new_page = max(0, socket.assigns.current_page - 2)
    {:noreply, assign(socket, current_page: new_page)}
  end

  @impl true
  def handle_event("next_page", _, socket) do
    max_page = length(socket.assigns.images) - 1
    new_page = min(max_page, socket.assigns.current_page + 2)
    {:noreply, assign(socket, current_page: new_page)}
  end

  @impl true
  def handle_event("set_page", %{"page" => page}, socket) do
    page_num = String.to_integer(page)
    {:noreply, assign(socket, current_page: page_num)}
  end

  @impl true
  def handle_event("near_bottom", _, socket) do
    if socket.assigns.next_chapter && !socket.assigns.preloaded_next do
      next_images = Webtoons.get_chapter_images(socket.assigns.next_chapter.id)
      urls = Enum.map(next_images, & &1.url)

      {:noreply,
       socket
       |> assign(preloaded_next: true)
       |> push_event("preload_images", %{urls: urls})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("keydown", %{"key" => key}, socket) do
    case {socket.assigns.reading_mode, key} do
      {:manga, "ArrowLeft"} ->
        handle_event("next_page", %{}, socket)

      {:manga, "ArrowRight"} ->
        handle_event("prev_page", %{}, socket)

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="reader-container"
      class="min-h-screen bg-gray-900"
      phx-hook="ReaderHook"
      phx-window-keydown="keydown"
    >
      <.toolbar
        :if={@show_toolbar}
        webtoon={@webtoon}
        chapter={@chapter}
        prev_chapter={@prev_chapter}
        next_chapter={@next_chapter}
        reading_mode={@reading_mode}
        images={@images}
        current_page={@current_page}
      />

      <div class="reader-content" phx-click="toggle_toolbar">
        <%= if @reading_mode == :webtoon do %>
          <.webtoon_reader images={@images} />
        <% else %>
          <.manga_reader
            images={@images}
            current_page={@current_page}
            prev_chapter={@prev_chapter}
            next_chapter={@next_chapter}
            webtoon={@webtoon}
          />
        <% end %>
      </div>

      <.chapter_nav
        :if={@reading_mode == :webtoon}
        prev_chapter={@prev_chapter}
        next_chapter={@next_chapter}
        webtoon={@webtoon}
      />
    </div>
    """
  end

  defp toolbar(assigns) do
    ~H"""
    <div class="fixed top-0 left-0 right-0 z-50 bg-gray-800/95 text-white px-4 py-3">
      <div class="container mx-auto flex items-center justify-between">
        <div class="flex items-center gap-4">
          <.link navigate={~p"/webtoons/#{@webtoon.slug}"} class="hover:text-blue-400">
            &larr; {@webtoon.title}
          </.link>
          <span class="text-gray-400">|</span>
          <span>Chapter {format_chapter_number(@chapter.chapter_number)}</span>
        </div>

        <div class="flex items-center gap-4">
          <.chapter_selector
            webtoon={@webtoon}
            chapter={@chapter}
            prev_chapter={@prev_chapter}
            next_chapter={@next_chapter}
          />

          <button
            phx-click="toggle_mode"
            class="px-3 py-1 bg-gray-700 rounded hover:bg-gray-600"
          >
            {if @reading_mode == :webtoon, do: "Webtoon", else: "Manga"} Mode
          </button>

          <div :if={@reading_mode == :manga} class="text-sm text-gray-400">
            Page {min(@current_page + 1, length(@images))}-{min(@current_page + 2, length(@images))} / {length(@images)}
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp chapter_selector(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <.link
        :if={@prev_chapter}
        navigate={~p"/webtoons/#{@webtoon.slug}/chapters/#{format_chapter_number(@prev_chapter.chapter_number)}"}
        class="px-3 py-1 bg-gray-700 rounded hover:bg-gray-600"
      >
        Prev
      </.link>
      <span :if={!@prev_chapter} class="px-3 py-1 bg-gray-800 text-gray-500 rounded">
        Prev
      </span>

      <.link
        :if={@next_chapter}
        navigate={~p"/webtoons/#{@webtoon.slug}/chapters/#{format_chapter_number(@next_chapter.chapter_number)}"}
        class="px-3 py-1 bg-gray-700 rounded hover:bg-gray-600"
      >
        Next
      </.link>
      <span :if={!@next_chapter} class="px-3 py-1 bg-gray-800 text-gray-500 rounded">
        Next
      </span>
    </div>
    """
  end

  defp webtoon_reader(assigns) do
    ~H"""
    <div id="webtoon-scroll" class="pt-16 pb-20 flex flex-col items-center">
      <div class="max-w-4xl w-full">
        <.chapter_image :for={{image, idx} <- Enum.with_index(@images)} image={image} idx={idx} />
      </div>
    </div>
    """
  end

  defp chapter_image(assigns) do
    ~H"""
    <div
      id={"image-#{@idx}"}
      class="w-full"
      style={"aspect-ratio: #{@image.width}/#{@image.height}"}
    >
      <img
        src={@image.url}
        width={@image.width}
        height={@image.height}
        loading="lazy"
        class="w-full h-auto"
        alt={"Page #{@idx + 1}"}
      />
    </div>
    """
  end

  defp manga_reader(assigns) do
    # Get current pages (double-page spread)
    current = Enum.at(assigns.images, assigns.current_page)
    next_img = Enum.at(assigns.images, assigns.current_page + 1)
    at_start = assigns.current_page == 0
    at_end = assigns.current_page >= length(assigns.images) - 2

    assigns =
      assigns
      |> assign(:current_image, current)
      |> assign(:next_image, next_img)
      |> assign(:at_start, at_start)
      |> assign(:at_end, at_end)

    ~H"""
    <div class="pt-16 h-screen flex items-center justify-center relative">
      <button
        :if={!@at_end}
        phx-click="next_page"
        class="absolute left-4 top-1/2 -translate-y-1/2 w-1/3 h-2/3 z-10 opacity-0 hover:opacity-100 flex items-center justify-start"
      >
        <span class="bg-gray-800/80 text-white px-4 py-2 rounded">Next</span>
      </button>

      <button
        :if={@at_end && @next_chapter}
        class="absolute left-4 top-1/2 -translate-y-1/2 z-10"
      >
        <.link
          navigate={~p"/webtoons/#{@webtoon.slug}/chapters/#{format_chapter_number(@next_chapter.chapter_number)}"}
          class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700"
        >
          Next Chapter
        </.link>
      </button>

      <div class="flex gap-2 max-h-[calc(100vh-8rem)] items-center">
        <div :if={@next_image} class="manga-page">
          <img
            src={@next_image.url}
            width={@next_image.width}
            height={@next_image.height}
            style={"aspect-ratio: #{@next_image.width}/#{@next_image.height}; max-height: calc(100vh - 8rem)"}
            class="h-auto w-auto max-w-[45vw]"
            alt={"Page #{@current_page + 2}"}
          />
        </div>

        <div :if={@current_image} class="manga-page">
          <img
            src={@current_image.url}
            width={@current_image.width}
            height={@current_image.height}
            style={"aspect-ratio: #{@current_image.width}/#{@current_image.height}; max-height: calc(100vh - 8rem)"}
            class="h-auto w-auto max-w-[45vw]"
            alt={"Page #{@current_page + 1}"}
          />
        </div>
      </div>

      <button
        :if={!@at_start}
        phx-click="prev_page"
        class="absolute right-4 top-1/2 -translate-y-1/2 w-1/3 h-2/3 z-10 opacity-0 hover:opacity-100 flex items-center justify-end"
      >
        <span class="bg-gray-800/80 text-white px-4 py-2 rounded">Prev</span>
      </button>

      <button
        :if={@at_start && @prev_chapter}
        class="absolute right-4 top-1/2 -translate-y-1/2 z-10"
      >
        <.link
          navigate={~p"/webtoons/#{@webtoon.slug}/chapters/#{format_chapter_number(@prev_chapter.chapter_number)}"}
          class="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700"
        >
          Prev Chapter
        </.link>
      </button>
    </div>
    """
  end

  defp chapter_nav(assigns) do
    ~H"""
    <div class="fixed bottom-0 left-0 right-0 bg-gray-800/95 text-white px-4 py-3">
      <div class="container mx-auto flex items-center justify-between">
        <.link
          :if={@prev_chapter}
          navigate={~p"/webtoons/#{@webtoon.slug}/chapters/#{format_chapter_number(@prev_chapter.chapter_number)}"}
          class="px-4 py-2 bg-gray-700 rounded hover:bg-gray-600"
        >
          &larr; Previous Chapter
        </.link>
        <span :if={!@prev_chapter} class="px-4 py-2 bg-gray-800 text-gray-500 rounded">
          &larr; Previous Chapter
        </span>

        <.link
          :if={@next_chapter}
          navigate={~p"/webtoons/#{@webtoon.slug}/chapters/#{format_chapter_number(@next_chapter.chapter_number)}"}
          class="px-4 py-2 bg-gray-700 rounded hover:bg-gray-600"
        >
          Next Chapter &rarr;
        </.link>
        <span :if={!@next_chapter} class="px-4 py-2 bg-gray-800 text-gray-500 rounded">
          Next Chapter &rarr;
        </span>
      </div>
    </div>
    """
  end

  defp format_chapter_number(%Decimal{} = number) do
    if Decimal.equal?(number, Decimal.round(number, 0)) do
      number |> Decimal.round(0) |> Decimal.to_string()
    else
      Decimal.to_string(number)
    end
  end

  defp format_chapter_number(number), do: to_string(number)
end
