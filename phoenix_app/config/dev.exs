import Config

# Database configuration
config :webtoon_shared, WebtoonShared.Repo,
  username: System.get_env("POSTGRES_USER", "webtoon"),
  password: System.get_env("POSTGRES_PASSWORD", "webtoon"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: System.get_env("POSTGRES_DB", "webtoon_dev"),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# R2 Storage configuration
config :webtoon_shared,
  r2_account_id: System.get_env("R2_ACCOUNT_ID"),
  r2_access_key_id: System.get_env("R2_ACCESS_KEY_ID"),
  r2_secret_access_key: System.get_env("R2_SECRET_ACCESS_KEY"),
  r2_bucket: System.get_env("R2_BUCKET"),
  r2_public_url: System.get_env("R2_PUBLIC_URL", "")

# Endpoint configuration for development
config :webtoon_web, WebtoonWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_that_is_at_least_64_bytes_long_for_development_only",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:webtoon_web, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:webtoon_web, ~w(--watch)]}
  ]

# Watch static and templates for browser reloading
config :webtoon_web, WebtoonWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/webtoon_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Enable dev routes
config :webtoon_web, dev_routes: true

# Disable swoosh api client
config :swoosh, :api_client, false

# Set a higher stacktrace during development
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  enable_expensive_runtime_checks: true
