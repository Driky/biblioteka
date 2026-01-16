defmodule WebtoonScraper.MixProject do
  use Mix.Project

  def project do
    [
      app: :webtoon_scraper,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {WebtoonScraper.Application, []}
    ]
  end

  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Shared library
      {:webtoon_shared, path: "../shared"},

      # Crawling
      {:crawly, "~> 0.16"},
      {:floki, "~> 0.36"},

      # Scheduling
      {:quantum, "~> 3.5"},

      # Image processing
      {:image, "~> 0.48"},

      # HTTP client (for image downloads)
      {:req, "~> 0.4"},

      # JSON
      {:jason, "~> 1.4"}
    ]
  end
end
