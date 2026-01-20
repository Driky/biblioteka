defmodule WebtoonWeb.Router do
  use WebtoonWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WebtoonWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", WebtoonWeb do
    pipe_through :browser

    # Home page - list of webtoons
    live "/", HomeLive, :index

    # Webtoon detail page
    live "/webtoons/:slug", WebtoonLive, :show

    # Chapter reader
    live "/webtoons/:slug/chapters/:number", ReaderLive, :show
  end

  # Admin back-office routes
  scope "/admin", WebtoonWeb.Admin do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/webtoons", WebtoonLive.Index, :index
    live "/webtoons/new", WebtoonLive.Index, :new
    live "/webtoons/:id", WebtoonLive.Show, :show
    live "/webtoons/:id/edit", WebtoonLive.Show, :edit
    live "/spiders", SpiderLive.Index, :index
    live "/spiders/:name", SpiderLive.Show, :show
    live "/spiders/:name/runs", SpiderLive.Runs, :index
    live "/runs", RunLive.Index, :index
    live "/runs/:id", RunLive.Show, :show
  end

  # LiveDashboard with Oban monitoring - available in admin for all environments
  import Phoenix.LiveDashboard.Router

  scope "/admin" do
    pipe_through :browser

    live_dashboard "/dashboard",
      metrics: WebtoonWeb.Telemetry,
      additional_pages: [
        oban: Oban.LiveDashboard
      ]
  end

  # Enable additional dev routes in development
  if Application.compile_env(:webtoon_web, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dev-dashboard", metrics: WebtoonWeb.Telemetry
    end
  end
end
