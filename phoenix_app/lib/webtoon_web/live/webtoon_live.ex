defmodule WebtoonWeb.WebtoonLive do
  @moduledoc """
  Webtoon detail page showing chapter list.
  """

  use WebtoonWeb, :live_view

  alias Webtoon.Webtoons

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Webtoons.get_webtoon_with_chapters(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Webtoon not found")
         |> push_navigate(to: ~p"/")}

      %{webtoon: webtoon, chapters: chapters} ->
        progress = Webtoons.get_reading_progress(webtoon.id)

        {:ok,
         assign(socket,
           page_title: webtoon.title,
           webtoon: webtoon,
           chapters: chapters,
           progress: progress
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4 py-8">
      <.link navigate={~p"/"} class="text-blue-600 hover:text-blue-800 mb-4 inline-block">
        &larr; Back to Home
      </.link>

      <div class="flex flex-col md:flex-row gap-8 mb-8">
        <div class="w-full md:w-64 flex-shrink-0">
          <div class="aspect-[3/4] bg-gray-200 rounded-lg overflow-hidden">
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
          </div>
        </div>

        <div class="flex-1">
          <h1 class="text-3xl font-bold mb-4">{@webtoon.title}</h1>

          <div class="flex items-center gap-4 mb-4">
            <span class="text-gray-600">{length(@chapters)} chapters</span>
          </div>

          <div :if={@progress} class="mb-4">
            <.link
              navigate={~p"/webtoons/#{@webtoon.slug}/chapters/#{format_chapter_number(@progress.last_chapter.chapter_number)}"}
              class="inline-flex items-center px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
            >
              Continue Reading - Chapter {format_chapter_number(@progress.last_chapter.chapter_number)}
            </.link>
          </div>

          <div :if={!@progress && length(@chapters) > 0} class="mb-4">
            <.link
              navigate={~p"/webtoons/#{@webtoon.slug}/chapters/#{format_chapter_number(List.last(@chapters).chapter_number)}"}
              class="inline-flex items-center px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
            >
              Start Reading
            </.link>
          </div>
        </div>
      </div>

      <div class="bg-white rounded-lg shadow">
        <h2 class="text-xl font-semibold p-4 border-b">Chapters</h2>

        <div :if={Enum.empty?(@chapters)} class="p-4 text-gray-500 text-center">
          No chapters available yet.
        </div>

        <div class="divide-y">
          <.chapter_row
            :for={chapter <- @chapters}
            chapter={chapter}
            webtoon={@webtoon}
            is_current={@progress && @progress.last_chapter_id == chapter.id}
          />
        </div>
      </div>
    </div>
    """
  end

  defp chapter_row(assigns) do
    ~H"""
    <.link
      navigate={~p"/webtoons/#{@webtoon.slug}/chapters/#{format_chapter_number(@chapter.chapter_number)}"}
      class={"flex items-center justify-between p-4 hover:bg-gray-50 #{if @is_current, do: "bg-blue-50", else: ""}"}
    >
      <div class="flex items-center gap-4">
        <span class="font-medium">
          Chapter {format_chapter_number(@chapter.chapter_number)}
        </span>
        <span :if={@chapter.title} class="text-gray-600">
          - {@chapter.title}
        </span>
        <span :if={@is_current} class="text-xs bg-blue-600 text-white px-2 py-1 rounded">
          Current
        </span>
      </div>
      <span class="text-gray-400 text-sm">
        {Calendar.strftime(@chapter.inserted_at, "%b %d, %Y")}
      </span>
    </.link>
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
