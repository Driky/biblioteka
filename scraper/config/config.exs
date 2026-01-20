import Config

# Import shared config
import_config "../../shared/config/config.exs"

config :webtoon_scraper,
  ecto_repos: [WebtoonShared.Repo],
  # Maximum number of new chapters to scrape per spider run
  # This prevents overwhelming the target site and request storage
  max_chapters_per_run: 20

# Oban configuration for async job processing
config :webtoon_scraper, Oban,
  repo: WebtoonShared.Repo,
  queues: [
    # Chapter fetching: includes rendering page + downloading/uploading images
    # Keep concurrency low to avoid overwhelming render server and target sites
    chapter_fetch: 2,
    default: 10
  ],
  plugins: [
    Oban.Plugins.Pruner,  # Clean old jobs
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)}
  ]

# Crawly configuration
config :crawly,
  # Fetcher configuration - use custom render server fetcher for JS-rendered pages
  fetcher:
    {WebtoonScraper.Fetchers.RenderServer,
     [
       base_url: System.get_env("RENDER_SERVER_URL", "http://localhost:3000/render")
     ]},

  # Timeout for fetch requests (milliseconds) - must be longer than render server timeout
  # Default Crawly timeout is very short, we need longer for JS rendering
  timeout: 120_000,

  # Rate limiting: keep low to avoid bans
  concurrent_requests_per_domain: 1,

  # Delay between requests (milliseconds) - be polite to target sites
  request_delay: 3_000,

  # Increase manager timeout for storing many requests
  manager_operations_timeout: 30_000,

  # Note: Retries are handled by our custom RenderServer fetcher
  # to avoid conflicts with Crawly's request deduplication

  middlewares: [
    Crawly.Middlewares.DomainFilter,
    {Crawly.Middlewares.UserAgent,
     user_agents: [
       "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:134.0) Gecko/20100101 Firefox/134.0",
       "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:134.0) Gecko/20100101 Firefox/134.0",
       "Mozilla/5.0 (X11; Linux x86_64; rv:134.0) Gecko/20100101 Firefox/134.0"
     ]}
  ],

  # Pipelines for cover images only
  # Chapter processing is handled by Oban jobs (ChapterFetchWorker)
  pipelines: [
    WebtoonScraper.Pipelines.ImageProcessor,
    WebtoonScraper.Pipelines.R2Upload,
    WebtoonScraper.Pipelines.DatabaseSave
  ]

# Import environment specific config
import_config "#{config_env()}.exs"
