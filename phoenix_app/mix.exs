defmodule WebtoonWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :webtoon_web,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  def application do
    [
      mod: {WebtoonWeb.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Shared library
      {:webtoon_shared, path: "../shared"},

      # Phoenix
      {:phoenix, "~> 1.8"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.8"},

      # Assets
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
      {:heroicons, "~> 0.5"},

      # HTTP server
      {:bandit, "~> 1.2"},

      # Telemetry
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},

      # JSON
      {:jason, "~> 1.4"},

      # DNS cluster (for releases)
      {:dns_cluster, "~> 0.1"},

      # Environment variables from .env files
      {:dotenvy, "~> 0.8"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind webtoon_web", "esbuild webtoon_web"],
      "assets.deploy": [
        "tailwind webtoon_web --minify",
        "esbuild webtoon_web --minify",
        "phx.digest"
      ]
    ]
  end
end
