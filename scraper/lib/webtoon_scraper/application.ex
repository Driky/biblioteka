defmodule WebtoonScraper.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Repo is started by WebtoonShared.Application
      # Start Oban for async job processing
      {Oban, Application.fetch_env!(:webtoon_scraper, Oban)},
      # Start the scheduler
      WebtoonScraper.Scheduler
    ]

    opts = [strategy: :one_for_one, name: WebtoonScraper.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
