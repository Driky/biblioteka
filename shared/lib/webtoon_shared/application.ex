defmodule WebtoonShared.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WebtoonShared.Repo
    ]

    opts = [strategy: :one_for_one, name: WebtoonShared.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
