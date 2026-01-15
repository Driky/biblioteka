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

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT", "4000"))

  config :webtoon_web, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :webtoon_web, WebtoonWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
end
