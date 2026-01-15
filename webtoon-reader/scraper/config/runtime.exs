import Config

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
