import Config

config :webtoon_shared, WebtoonShared.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
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
