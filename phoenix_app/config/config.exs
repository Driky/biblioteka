import Config

# Import shared config
import_config "../../shared/config/config.exs"

config :webtoon_web,
  ecto_repos: [WebtoonShared.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :webtoon_web, WebtoonWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WebtoonWeb.ErrorHTML, json: WebtoonWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: WebtoonWeb.PubSub,
  live_view: [signing_salt: "webtoon_lv_salt"]

# Configure esbuild
config :esbuild,
  version: "0.17.11",
  webtoon_web: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind
config :tailwind,
  version: "3.4.0",
  webtoon_web: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing
config :phoenix, :json_library, Jason

# Oban configuration - mirrors scraper config so Oban Web can monitor jobs
config :webtoon_web, Oban,
  repo: WebtoonShared.Repo,
  queues: false,  # Don't process jobs in the web app, just monitor
  plugins: false  # Disable plugins in web app

# Import environment specific config
import_config "#{config_env()}.exs"
