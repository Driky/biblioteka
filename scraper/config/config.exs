import Config

# Import shared config
import_config "../../shared/config/config.exs"

config :webtoon_scraper,
  ecto_repos: [WebtoonShared.Repo],
  # Maximum number of new chapters to scrape per spider run
  # This prevents overwhelming the target site and request storage
  max_chapters_per_run: 20

# Crawly configuration
config :crawly,
  # Fetcher configuration - use custom render server fetcher for JS-rendered pages
  fetcher:
    {WebtoonScraper.Fetchers.RenderServer,
     [
       base_url: System.get_env("RENDER_SERVER_URL", "http://localhost:3000/render")
     ]},

  # Rate limiting: keep low to avoid bans
  concurrent_requests_per_domain: 1,

  # Delay between requests (milliseconds) - be polite to target sites
  request_delay: 3_000,

  # Increase manager timeout for storing many requests
  manager_operations_timeout: 30_000,

  middlewares: [
    Crawly.Middlewares.DomainFilter,
    Crawly.Middlewares.UniqueRequest,
    {Crawly.Middlewares.UserAgent,
     user_agents: [
       "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
       "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
       "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0"
     ]}
  ],

  pipelines: [
    WebtoonScraper.Pipelines.ImageProcessor,
    WebtoonScraper.Pipelines.R2Upload,
    WebtoonScraper.Pipelines.DatabaseSave
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
