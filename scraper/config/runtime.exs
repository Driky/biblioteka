import Config

# Load environment variables from .env files
# In dev: loads ../.env.dev (project root)
# In prod: expects env vars to be set by the deployment
if config_env() == :dev do
  env_file = Path.expand("../../.env.dev", __DIR__)

  if File.exists?(env_file) do
    Dotenvy.source!([env_file])
  end

  # Configure R2 storage from environment variables (optional in dev)
  if r2_bucket = System.get_env("R2_BUCKET") do
    config :webtoon_shared,
      r2_account_id: System.get_env("R2_ACCOUNT_ID"),
      r2_access_key_id: System.get_env("R2_ACCESS_KEY_ID"),
      r2_secret_access_key: System.get_env("R2_SECRET_ACCESS_KEY"),
      r2_bucket: r2_bucket,
      r2_public_url: System.get_env("R2_PUBLIC_URL", "")
  end
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  config :webtoon_shared, WebtoonShared.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

  # R2 Storage configuration
  config :webtoon_shared,
    r2_account_id:
      System.get_env("R2_ACCOUNT_ID") ||
        raise("R2_ACCOUNT_ID environment variable is missing"),
    r2_access_key_id:
      System.get_env("R2_ACCESS_KEY_ID") ||
        raise("R2_ACCESS_KEY_ID environment variable is missing"),
    r2_secret_access_key:
      System.get_env("R2_SECRET_ACCESS_KEY") ||
        raise("R2_SECRET_ACCESS_KEY environment variable is missing"),
    r2_bucket:
      System.get_env("R2_BUCKET") ||
        raise("R2_BUCKET environment variable is missing"),
    r2_public_url:
      System.get_env("R2_PUBLIC_URL") ||
        raise("R2_PUBLIC_URL environment variable is missing")

  # Crawly render server URL
  render_server_url =
    System.get_env("RENDER_SERVER_URL") ||
      raise("RENDER_SERVER_URL environment variable is missing")

  config :crawly,
    fetcher:
      {Crawly.Fetchers.CrawlyRenderServer,
       [
         base_url: render_server_url
       ]}
end
