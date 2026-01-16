import Config

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
