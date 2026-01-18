import Config
import Dotenvy

# Load environment variables from .env files
# In dev: loads ../.env.dev (project root)
# In prod: expects env vars to be set by deployment
env_dir = Path.expand("../..", __DIR__)

source!([
  Path.absname(".env.dev", env_dir),
  System.get_env()
])

# Debug output (can be removed later)
IO.puts("[runtime.exs] Environment: #{config_env()}")
IO.puts("[runtime.exs] R2_BUCKET: #{inspect(env!("R2_BUCKET", :string?))}")

# Configure R2 storage (required values use :string!, optional use :string?)
if r2_bucket = env!("R2_BUCKET", :string?) do
  IO.puts("[runtime.exs] Configuring R2 with bucket: #{r2_bucket}")
  config :webtoon_shared,
    r2_account_id: env!("R2_ACCOUNT_ID", :string),
    r2_access_key_id: env!("R2_ACCESS_KEY_ID", :string),
    r2_secret_access_key: env!("R2_SECRET_ACCESS_KEY", :string),
    r2_bucket: r2_bucket,
    r2_public_url: env!("R2_PUBLIC_URL", :string) || ""
else
  IO.puts("[runtime.exs] WARNING: R2_BUCKET not set, R2 storage will not be configured")
end

if config_env() == :prod do
  config :webtoon_shared, WebtoonShared.Repo,
    url: env!("DATABASE_URL", :string!),
    pool_size: env!("POOL_SIZE", :integer) || 10

  # Crawly render server URL - use our custom fetcher with scrolling support
  config :crawly,
    fetcher:
      {WebtoonScraper.Fetchers.RenderServer,
       [
         base_url: env!("RENDER_SERVER_URL", :string!)
       ]},
    timeout: 120_000
end
