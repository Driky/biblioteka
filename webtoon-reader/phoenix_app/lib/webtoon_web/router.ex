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

  # Enable LiveDashboard in development
  if Application.compile_env(:webtoon_web, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: WebtoonWeb.Telemetry
    end
  end
end
