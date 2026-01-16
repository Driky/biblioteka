import Config

# Database configuration
config :webtoon_shared, WebtoonShared.Repo,
  username: System.get_env("POSTGRES_USER", "webtoon"),
  password: System.get_env("POSTGRES_PASSWORD", "webtoon"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: System.get_env("POSTGRES_DB", "webtoon_test"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :webtoon_shared,
  r2_account_id: "test_account",
  r2_access_key_id: "test_key",
  r2_secret_access_key: "test_secret",
  r2_bucket: "test-bucket",
  r2_public_url: "https://test.example.com"

# Endpoint configuration for tests
config :webtoon_web, WebtoonWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_that_is_at_least_64_bytes_long_for_testing_purposes",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
