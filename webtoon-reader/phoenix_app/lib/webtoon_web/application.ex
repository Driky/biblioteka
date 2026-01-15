defmodule WebtoonWeb.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WebtoonShared.Repo,
      WebtoonWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:webtoon_web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: WebtoonWeb.PubSub},
      WebtoonWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: WebtoonWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    WebtoonWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
