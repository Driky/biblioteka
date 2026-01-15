defmodule WebtoonScraper.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the shared repo
      WebtoonShared.Repo,
      # Start the scheduler
      WebtoonScraper.Scheduler
    ]

    opts = [strategy: :one_for_one, name: WebtoonScraper.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
