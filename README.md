# Webtoon Reader

A self-hosted webtoon/manga reader application with automated scraping capabilities.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Phoenix App   │────▶│   PostgreSQL    │◀────│    Scraper      │
│   (LiveView)    │     │                 │     │   (Crawly)      │
└────────┬────────┘     └─────────────────┘     └────────┬────────┘
         │                                               │
         │              ┌─────────────────┐              │
         └─────────────▶│  Cloudflare R2  │◀─────────────┘
                        │  (Image CDN)    │
                        └─────────────────┘
```

- **Phoenix App**: LiveView frontend for browsing and reading webtoons
- **Scraper**: Crawly-based service that scrapes webtoon sites via headless Chrome
- **Shared Library**: Common schemas, migrations, and R2 storage abstraction
- **PostgreSQL**: Stores webtoon metadata, chapters, and reading progress
- **Cloudflare R2**: S3-compatible storage for chapter images

## Prerequisites

- Elixir 1.19+
- Erlang/OTP 27+
- PostgreSQL 16+
- Docker & Docker Compose (for deployment)
- Node.js 20+ (for asset compilation)

## Project Structure

```
webtoon-reader/
├── shared/           # Shared Elixir library (schemas, storage)
├── phoenix_app/      # Phoenix LiveView frontend
├── scraper/          # Crawly scraper service
├── nginx/            # Nginx configuration
└── scripts/          # Deployment and SSL scripts
```

## Development Setup

### 1. Clone and Install Dependencies

```bash
cd webtoon-reader

# Install dependencies for each app
cd shared && mix deps.get && cd ..
cd phoenix_app && mix deps.get && cd ..
cd scraper && mix deps.get && cd ..
```

### 2. Configure Environment

```bash
cp .env.example .env.dev
```

Edit `.env.dev` with your local settings:

```bash
# PostgreSQL (local)
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=webtoon_dev

# R2 (use real credentials or mock for dev)
R2_ACCOUNT_ID=your_account_id
R2_ACCESS_KEY_ID=your_access_key
R2_SECRET_ACCESS_KEY=your_secret_key
R2_BUCKET=webtoon-dev
R2_PUBLIC_URL=https://your-r2-public-url.com

# Phoenix
SECRET_KEY_BASE=$(mix phx.gen.secret)
PHX_HOST=localhost
```

### 3. Setup Database

```bash
# Start PostgreSQL (if using Docker)
docker run -d \
  --name webtoon_postgres_dev \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=webtoon_dev \
  -p 5432:5432 \
  postgres:16-alpine

# Run migrations
cd shared
DATABASE_URL=ecto://postgres:postgres@localhost/webtoon_dev mix ecto.create
DATABASE_URL=ecto://postgres:postgres@localhost/webtoon_dev mix ecto.migrate

# Optional: seed sample data
DATABASE_URL=ecto://postgres:postgres@localhost/webtoon_dev mix run priv/repo/seeds.exs
```

### 4. Start the Phoenix App

```bash
cd phoenix_app

# Set environment
export DATABASE_URL=ecto://postgres:postgres@localhost/webtoon_dev
export SECRET_KEY_BASE=$(mix phx.gen.secret)
export R2_PUBLIC_URL=https://your-r2-url.com

# Install assets
mix assets.setup

# Start the server
mix phx.server
```

Visit http://localhost:4000

### 5. Start the Scraper (Optional)

The scraper requires a render server (headless Chrome) for JavaScript-rendered sites:

```bash
# Build and start the render server from local Dockerfile
cd render-server
docker build -t crawly-render-server .
docker run -d \
  --name crawly_render \
  -p 3000:3000 \
  crawly-render-server

# Start the scraper
cd ../scraper
export DATABASE_URL=ecto://postgres:postgres@localhost/webtoon_dev
export RENDER_SERVER_URL=http://localhost:3000/render
iex -S mix
```

Alternatively, use Docker Compose to start all services including the render server:

```bash
docker compose up -d render-server
```

### 6. Running Tests

```bash
# Shared library tests
cd shared && mix test

# Phoenix app tests
cd phoenix_app && mix test

# Scraper tests
cd scraper && mix test
```

## Running a Spider (Development)

To run a spider, you need to set up the database records first, then start the spider.

### 1. Create a Webtoon and Source

Start an IEx session from the scraper directory:

```bash
cd scraper
export DATABASE_URL=ecto://postgres:postgres@localhost/webtoon_dev
iex -S mix
```

Then create the required database records:

```elixir
alias WebtoonShared.Repo
alias WebtoonShared.Schema.{Webtoon, WebtoonSource}

# Create a webtoon
{:ok, webtoon} = Repo.insert(%Webtoon{
  title: "Solo Leveling",
  slug: "solo-leveling"
})

# Create a source linking to the webtoon
# site_id must match the spider's site_id (e.g., "mangahub", "mangadex")
{:ok, source} = Repo.insert(%WebtoonSource{
  webtoon_id: webtoon.id,
  site_id: "mangahub",
  source_url: "https://mangahub.io/manga/solo-leveling",
  enabled: true
})
```

### 2. Start the Render Server

The render server must be running for JavaScript-rendered sites:

```bash
# In a separate terminal
cd render-server
docker build -t crawly-render-server .
docker run -d --name crawly_render -p 3000:3000 crawly-render-server
```

### 3. Run the Spider

In the IEx session:

```elixir
# Run the spider (with jitter delay)
WebtoonScraper.Runner.run_spider(WebtoonScraper.Spiders.MangaHub)

# Or start immediately without jitter
Crawly.Engine.start_spider(WebtoonScraper.Spiders.MangaHub)

# Check running spiders
Crawly.Engine.running_spiders()

# Stop a spider
Crawly.Engine.stop_spider(WebtoonScraper.Spiders.MangaHub)
```

### 4. Monitor Progress

```elixir
# Check scraped chapters
alias WebtoonShared.Schema.Chapter
Repo.all(Chapter) |> length()

# Check source status
Repo.get(WebtoonSource, source.id) |> Map.take([:last_checked_at, :last_chapter_scraped])
```

## Adding a New Spider

1. Create a new spider module in `scraper/lib/webtoon_scraper/spiders/`:

```elixir
defmodule WebtoonScraper.Spiders.MySite do
  use WebtoonScraper.Spiders.Base

  @impl true
  def site_id, do: "mysite"

  @impl true
  def base_url, do: "https://mysite.com"

  @impl true
  def parse_chapter_list(response) do
    # Parse HTML and return list of %{chapter_number, title, url}
  end

  @impl true
  def parse_chapter_images(response) do
    # Parse HTML and return list of image URLs
  end
end
```

2. Add a schedule in `scraper/config/config.exs`:

```elixir
config :scraper, WebtoonScraper.Scheduler,
  jobs: [
    {"5,35 * * * *", {WebtoonScraper.Runner, :run_spider, [WebtoonScraper.Spiders.MySite]}}
  ]
```

3. Add a source to the database:

```elixir
WebtoonScraper.Sources.create(%{
  site_id: "mysite",
  source_url: "https://mysite.com/manga/example",
  enabled: true
})
```

## Production Deployment

### 1. Server Preparation

```bash
# Install Docker and Docker Compose
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install Nginx and Certbot
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx

# Create app directory
sudo mkdir -p /opt/webtoon-reader
sudo chown $USER:$USER /opt/webtoon-reader
```

### 2. Configure Environment

```bash
cd /opt/webtoon-reader
cp .env.example .env
```

Edit `.env` with production values:

```bash
# PostgreSQL
POSTGRES_USER=webtoon
POSTGRES_PASSWORD=<generate-secure-password>
POSTGRES_DB=webtoon_prod

# Phoenix
SECRET_KEY_BASE=<run: mix phx.gen.secret>
PHX_HOST=webtoon.yourdomain.com

# Cloudflare R2
R2_ACCOUNT_ID=<your-account-id>
R2_ACCESS_KEY_ID=<your-access-key>
R2_SECRET_ACCESS_KEY=<your-secret-key>
R2_BUCKET=webtoon-images
R2_PUBLIC_URL=https://images.yourdomain.com
```

### 3. Setup SSL Certificate

```bash
# Edit the domain in the script
nano scripts/init-ssl.sh

# Run SSL setup
sudo ./scripts/init-ssl.sh
```

### 4. Configure Nginx

```bash
# Edit domain in nginx config
sudo nano nginx/webtoon.conf

# Copy to sites-available
sudo cp nginx/webtoon.conf /etc/nginx/sites-available/webtoon

# Enable the site
sudo ln -s /etc/nginx/sites-available/webtoon /etc/nginx/sites-enabled/

# Test and reload
sudo nginx -t
sudo systemctl reload nginx
```

### 5. Setup SSL Auto-Renewal

```bash
sudo cp scripts/certbot-renewal.timer /etc/systemd/system/
sudo cp scripts/certbot-renewal.service /etc/systemd/system/
sudo systemctl enable --now certbot-renewal.timer
```

### 6. Deploy with Docker Compose

```bash
# Build and start all services
docker compose up -d --build

# Run migrations
docker compose exec phoenix /app/bin/webtoon_web eval "WebtoonWeb.Release.migrate()"

# Check logs
docker compose logs -f

# Check status
docker compose ps
```

### 7. Updating the Application

```bash
cd /opt/webtoon-reader

# Pull latest changes
git pull origin main

# Rebuild and restart
docker compose up -d --build

# Run any new migrations
docker compose exec phoenix /app/bin/webtoon_web eval "WebtoonWeb.Release.migrate()"
```

Or use the deploy script:

```bash
./scripts/deploy.sh
```

## Cloudflare R2 Setup

1. Create an R2 bucket in your Cloudflare dashboard
2. Create an API token with R2 read/write permissions
3. Set up a custom domain for public access (optional but recommended)
4. Configure CORS if needed:

```json
[
  {
    "AllowedOrigins": ["https://webtoon.yourdomain.com"],
    "AllowedMethods": ["GET"],
    "AllowedHeaders": ["*"],
    "MaxAgeSeconds": 86400
  }
]
```

## Monitoring

### View Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f phoenix
docker compose logs -f scraper
```

### Database Access

```bash
docker compose exec postgres psql -U webtoon -d webtoon_prod
```

### Scraper Status

Access the scraper's IEx console:

```bash
docker compose exec scraper /app/bin/webtoon_scraper remote

# Check running spiders
Crawly.Engine.running_spiders()

# Manually trigger a spider
WebtoonScraper.Runner.run_spider(WebtoonScraper.Spiders.MangaDex)
```

## Troubleshooting

### Images not loading

- Verify R2_PUBLIC_URL is correct and accessible
- Check R2 bucket permissions and CORS settings
- Ensure images were uploaded (check `chapter_images` table)

### Scraper not finding chapters

- Check if the spider selectors match the current site HTML
- Verify the source URL is correct in `webtoon_sources` table
- Check render server is running: `docker compose logs render-server`

### Database connection issues

- Verify DATABASE_URL format: `ecto://user:pass@host/database`
- Check PostgreSQL is healthy: `docker compose ps postgres`
- Ensure migrations ran: `docker compose exec phoenix /app/bin/webtoon_web eval "WebtoonWeb.Release.migrate()"`

## License

MIT
