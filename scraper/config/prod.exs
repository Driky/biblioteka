import Config

# Database configuration
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

# Scheduler jobs - staggered to avoid load peaks
# Spider 1: runs at minute 5, 35 (every 30 min)
# Spider 2: runs at minute 15, 45 (every 30 min, offset by 10 min)
config :webtoon_scraper, WebtoonScraper.Scheduler,
  jobs: [
    {"5,35 * * * *",
     {WebtoonScraper.Runner, :run_spider, [WebtoonScraper.Spiders.MangaDex]}}
    # Add more spiders with staggered times:
    # {"15,45 * * * *", {WebtoonScraper.Runner, :run_spider, [WebtoonScraper.Spiders.WebtoonsCom]}},
    # {"25,55 * * * *", {WebtoonScraper.Runner, :run_spider, [WebtoonScraper.Spiders.AnotherSite]}},
  ]

# Crawly render server
config :crawly,
  fetcher:
    {Crawly.Fetchers.CrawlyRenderServer,
     [
       base_url: System.get_env("RENDER_SERVER_URL", "http://render-server:3000/render")
     ]}
