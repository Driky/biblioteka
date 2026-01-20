defmodule WebtoonWeb.HomeLive do
  @moduledoc """
  Home page LiveView displaying the list of webtoons.
  """

  use WebtoonWeb, :live_view

  alias Webtoon.Webtoons

  @impl true
  def mount(_params, _session, socket) do
    webtoons = Webtoons.list_webtoons()
    progress = Webtoons.get_all_reading_progress()

    {:ok,
     assign(socket,
       page_title: "Webtoon Reader",
       webtoons: webtoons,
       reading_progress: progress
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <h1 class="text-3xl font-bold mb-8">Webtoons</h1>

      <div :if={Enum.empty?(@webtoons)} class="text-gray-500 text-center py-12">
        No webtoons available yet.
      </div>

      <div class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-6">
        <.webtoon_card
          :for={{webtoon_data, _idx} <- Enum.with_index(@webtoons)}
          webtoon={webtoon_data.webtoon}
          chapter_count={webtoon_data.chapter_count}
          progress={Map.get(@reading_progress, webtoon_data.webtoon.id)}
        />
      </div>
    </div>
    """
  end

  defp webtoon_card(assigns) do
    # Calculate the next chapter number (after last read) for continue reading
    next_chapter_number =
      if assigns.progress do
        assigns.progress.last_chapter.chapter_number
        |> Decimal.add(1)
        |> format_chapter_number()
      else
        nil
      end

    assigns = assign(assigns, :next_chapter_number, next_chapter_number)

    ~H"""
    <div class="group relative bg-white rounded-lg shadow-md overflow-hidden hover:shadow-lg transition-shadow">
      <%!-- Main link covering entire card (z-0) --%>
      <.link
        navigate={~p"/webtoons/#{@webtoon.slug}"}
        class="absolute inset-0 z-0"
        aria-label={"View #{@webtoon.title}"}
      >
        <span class="sr-only">View {@webtoon.title}</span>
      </.link>

      <%!-- Visual content - pointer-events-none so clicks pass through to main link --%>
      <div class="relative z-10 pointer-events-none">
        <div class="aspect-[3/4] bg-gray-200 relative">
          <img
            :if={@webtoon.cover_url}
            src={storage_url(@webtoon.cover_url)}
            alt={@webtoon.title}
            class="w-full h-full object-cover"
          />
          <div
            :if={!@webtoon.cover_url}
            class="w-full h-full flex items-center justify-center text-gray-400"
          >
            No Cover
          </div>

          <div
            :if={@progress}
            class="absolute bottom-2 right-2 bg-blue-600 text-white text-xs px-2 py-1 rounded"
          >
            Ch. {format_chapter_number(@progress.last_chapter.chapter_number)}
          </div>
        </div>

        <div class="p-4">
          <h2 class="font-semibold text-gray-800 group-hover:text-blue-600 line-clamp-2">
            {@webtoon.title}
          </h2>
          <p class="text-sm text-gray-500 mt-1">
            {@chapter_count} chapters
          </p>

          <%!-- Continue Reading link - pointer-events-auto to capture clicks --%>
          <.link
            :if={@progress}
            navigate={~p"/webtoons/#{@webtoon.slug}/chapters/#{@next_chapter_number}"}
            class="mt-2 block text-sm text-blue-600 hover:text-blue-800 pointer-events-auto"
          >
            Continue Reading
          </.link>
        </div>
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
