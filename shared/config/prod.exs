import Config

config :webtoon_shared, WebtoonShared.Repo,
  url: System.get_env("DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

# R2 Storage configuration
config :webtoon_shared,
  r2_account_id: System.get_env("R2_ACCOUNT_ID"),
  r2_access_key_id: System.get_env("R2_ACCESS_KEY_ID"),
  r2_secret_access_key: System.get_env("R2_SECRET_ACCESS_KEY"),
  r2_bucket: System.get_env("R2_BUCKET"),
  r2_public_url: System.get_env("R2_PUBLIC_URL")
