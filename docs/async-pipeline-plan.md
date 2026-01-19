# Webtoon Scraper: Async Pipeline & Back-office Implementation Plan

## Overview

This plan outlines the implementation of an async processing pipeline using Oban and a back-office admin interface for managing the webtoon scraper application.

**Repository:** `/home/user/biblioteka`

**Current Stack:**
- Elixir/Phoenix with LiveView (frontend in `/frontend`)
- Crawly 0.17.2 for web scraping (scraper in `/scraper`)
- PostgreSQL database (shared schemas in `/shared`)
- Cloudflare R2 for image storage
- Custom Puppeteer render server (in `/render-server`)

---

## Problem Statement

When processing many chapters (e.g., 20 instead of 5), Crawly's internal GenServer times out:

```
GenServer.call(Crawly.DataStorage, {:stats, WebtoonScraper.Spiders.MangaHub}, 5000)
** (EXIT) time out
```

**Root Cause:** The current pipeline runs synchronously inside Crawly's DataStorage GenServer:
- `ImageProcessor` - Downloads all chapter images (heavy I/O)
- `R2Upload` - Uploads all images to Cloudflare R2 (heavy I/O)
- `DatabaseSave` - Saves chapter and images to PostgreSQL

When the Manager asks for stats, the GenServer is blocked on I/O and can't respond within 5 seconds.

---

## Phase 1: Fix Image Count Detection Bug

### Problem

The expected image count extraction is returning 10x the actual value:
```
Expected image count from page: 392 → Found: 39
Expected image count from page: 122 → Found: 12
Expected image count from page: 272 → Found: 27
```

### Location

`/home/user/biblioteka/scraper/lib/webtoon_scraper/spiders/mangahub.ex`

Look for the `extract_expected_image_count/1` function. The regex is likely capturing extra digits from the page indicator (e.g., capturing "392" instead of "39" from something like "1/39").

### Fix

Debug and fix the regex pattern. The page indicator format on MangaHub needs to be verified - it's likely something like "1/39" but the extraction is grabbing adjacent characters.

---

## Phase 2: Async Pipeline with Oban

### 2.1 Add Oban Dependency

**File:** `/home/user/biblioteka/scraper/mix.exs`

Add to deps:
```elixir
{:oban, "~> 2.17"}
```

**File:** `/home/user/biblioteka/scraper/config/config.exs`

Add Oban configuration:
```elixir
config :webtoon_scraper, Oban,
  repo: WebtoonShared.Repo,
  queues: [
    chapters: 5,      # 5 concurrent chapter processing jobs
    default: 10
  ],
  plugins: [
    Oban.Plugins.Pruner,  # Clean old jobs
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(30)}
  ]
```

**File:** `/home/user/biblioteka/scraper/lib/webtoon_scraper/application.ex`

Add Oban to supervision tree:
```elixir
children = [
  {Oban, Application.fetch_env!(:webtoon_scraper, Oban)},
  # ... existing children
]
```

### 2.2 Create Oban Migration

Run: `mix ecto.gen.migration add_oban_jobs_table`

**Migration content:**
```elixir
defmodule WebtoonShared.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up, do: Oban.Migration.up(version: 12)
  def down, do: Oban.Migration.down(version: 12)
end
```

### 2.3 Create ChapterWorker

**File:** `/home/user/biblioteka/scraper/lib/webtoon_scraper/workers/chapter_worker.ex`

```elixir
defmodule WebtoonScraper.Workers.ChapterWorker do
  @moduledoc """
  Oban worker that processes a single chapter:
  1. Downloads all images (parallel, max 3 concurrent)
  2. Uploads all images to R2 (parallel, max 3 concurrent)
  3. Saves chapter and images to database
  4. Records stats for spider run tracking
  """

  use Oban.Worker,
    queue: :chapters,
    max_attempts: 3,
    unique: [period: 300, fields: [:args], keys: [:webtoon_id, :chapter_number]]

  require Logger

  alias WebtoonShared.Repo
  alias WebtoonShared.Schema.{Chapter, ChapterImage}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "webtoon_id" => webtoon_id,
      "source_id" => source_id,
      "chapter_number" => chapter_number,
      "chapter_title" => chapter_title,
      "source_url" => source_url,
      "images" => images,  # List of %{"url" => url, "headers" => headers, "sequence" => seq}
      "spider_run_id" => spider_run_id  # Optional, for tracking
    } = args

    Logger.info("ChapterWorker processing chapter #{chapter_number} with #{length(images)} images")

    with {:ok, processed_images} <- download_images(images),
         {:ok, uploaded_images} <- upload_images(processed_images, webtoon_id, chapter_number),
         {:ok, chapter} <- save_to_database(webtoon_id, source_id, chapter_number, chapter_title, source_url, uploaded_images) do

      # Update spider run stats if tracking
      if spider_run_id do
        update_spider_run_stats(spider_run_id, length(uploaded_images))
      end

      Logger.info("ChapterWorker completed chapter #{chapter_number}")
      :ok
    else
      {:error, reason} ->
        Logger.error("ChapterWorker failed for chapter #{chapter_number}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp download_images(images) do
    results =
      images
      |> Task.async_stream(
        fn img -> download_single_image(img) end,
        max_concurrency: 3,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, {:ok, result}} -> result
        {:ok, {:error, _}} -> nil
        {:exit, _} -> nil
      end)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(results) do
      {:error, :no_images_downloaded}
    else
      {:ok, results}
    end
  end

  defp download_single_image(%{"url" => url, "headers" => headers, "sequence" => sequence}) do
    # Reuse logic from existing ImageProcessor
    # Returns {:ok, %{sequence: seq, binary: data, width: w, height: h, ...}}
    # See: /home/user/biblioteka/scraper/lib/webtoon_scraper/pipelines/image_processor.ex
  end

  defp upload_images(images, webtoon_id, chapter_number) do
    results =
      images
      |> Task.async_stream(
        fn img -> upload_single_image(img, webtoon_id, chapter_number) end,
        max_concurrency: 3,
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, {:ok, result}} -> result
        {:ok, {:error, _}} -> nil
        {:exit, _} -> nil
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, results}
  end

  defp upload_single_image(image, webtoon_id, chapter_number) do
    # Reuse logic from existing R2Upload
    # See: /home/user/biblioteka/scraper/lib/webtoon_scraper/pipelines/r2_upload.ex
  end

  defp save_to_database(webtoon_id, source_id, chapter_number, chapter_title, source_url, images) do
    # Reuse logic from existing DatabaseSave
    # See: /home/user/biblioteka/scraper/lib/webtoon_scraper/pipelines/database_save.ex
  end

  defp update_spider_run_stats(spider_run_id, image_count) do
    # Update spider_runs table with progress
    # Increment chapters_processed and images_downloaded
  end
end
```

### 2.4 Create EnqueuePipeline

**File:** `/home/user/biblioteka/scraper/lib/webtoon_scraper/pipelines/enqueue.ex`

```elixir
defmodule WebtoonScraper.Pipelines.Enqueue do
  @moduledoc """
  Pipeline that enqueues chapter processing as Oban jobs instead of
  processing synchronously. This prevents Crawly GenServer timeouts.
  """

  @behaviour Crawly.Pipeline

  require Logger

  @impl Crawly.Pipeline
  def run(item, state) do
    case item do
      %{type: :chapter, images: images} when length(images) > 0 ->
        enqueue_chapter_job(item, state)

      %{type: :cover} ->
        # Keep cover processing synchronous (it's just one image)
        {item, state}

      _ ->
        {item, state}
    end
  end

  defp enqueue_chapter_job(item, state) do
    job_args = %{
      webtoon_id: item.webtoon_id,
      source_id: item.source_id,
      chapter_number: Decimal.to_string(item.chapter_number),
      chapter_title: item.chapter_title,
      source_url: item.source_url,
      images: Enum.map(item.images, fn img ->
        %{
          url: img.url,
          headers: img.headers,
          sequence: img.sequence
        }
      end),
      spider_run_id: Map.get(state, :spider_run_id)
    }

    case WebtoonScraper.Workers.ChapterWorker.new(job_args) |> Oban.insert() do
      {:ok, job} ->
        Logger.info("Enqueued chapter #{item.chapter_number} as Oban job #{job.id}")
        # Return false to stop further pipeline processing for this item
        {false, state}

      {:error, reason} ->
        Logger.error("Failed to enqueue chapter #{item.chapter_number}: #{inspect(reason)}")
        {false, state}
    end
  end
end
```

### 2.5 Update Crawly Pipeline Configuration

**File:** `/home/user/biblioteka/scraper/config/config.exs`

Change pipelines from:
```elixir
pipelines: [
  WebtoonScraper.Pipelines.ImageProcessor,
  WebtoonScraper.Pipelines.R2Upload,
  WebtoonScraper.Pipelines.DatabaseSave
]
```

To:
```elixir
pipelines: [
  WebtoonScraper.Pipelines.Enqueue,
  # Keep these for cover images only (they check item.type)
  WebtoonScraper.Pipelines.ImageProcessor,
  WebtoonScraper.Pipelines.R2Upload,
  WebtoonScraper.Pipelines.DatabaseSave
]
```

**Note:** Update `ImageProcessor`, `R2Upload`, and `DatabaseSave` to only process `:cover` type items, passing through others unchanged.

---

## Phase 3: Database Schema for Tracking

### 3.1 Create Migrations

**Migration 1: Spider Runs**

```elixir
defmodule WebtoonShared.Repo.Migrations.CreateSpiderRuns do
  use Ecto.Migration

  def change do
    create table(:spider_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :spider_name, :string, null: false
      add :crawl_id, :string
      add :status, :string, default: "running"  # running, completed, failed
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :chapters_found, :integer, default: 0
      add :chapters_processed, :integer, default: 0
      add :images_downloaded, :integer, default: 0
      add :errors_count, :integer, default: 0

      timestamps()
    end

    create index(:spider_runs, [:spider_name])
    create index(:spider_runs, [:status])
    create index(:spider_runs, [:started_at])
  end
end
```

**Migration 2: Spider Run Errors**

```elixir
defmodule WebtoonShared.Repo.Migrations.CreateSpiderRunErrors do
  use Ecto.Migration

  def change do
    create table(:spider_run_errors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :spider_run_id, references(:spider_runs, type: :binary_id, on_delete: :delete_all)
      add :webtoon_id, references(:webtoons, type: :binary_id, on_delete: :nilify_all)
      add :chapter_number, :decimal
      add :error_type, :string
      add :error_message, :text
      add :stacktrace, :text
      add :occurred_at, :utc_datetime

      timestamps()
    end

    create index(:spider_run_errors, [:spider_run_id])
    create index(:spider_run_errors, [:webtoon_id])
  end
end
```

**Migration 3: Spider Configs**

```elixir
defmodule WebtoonShared.Repo.Migrations.CreateSpiderConfigs do
  use Ecto.Migration

  def change do
    create table(:spider_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :spider_name, :string, null: false
      add :enabled, :boolean, default: true
      add :max_chapters_per_run, :integer, default: 10
      add :request_delay_ms, :integer, default: 1000
      add :last_run_at, :utc_datetime

      timestamps()
    end

    create unique_index(:spider_configs, [:spider_name])
  end
end
```

**Migration 4: Extend Existing Tables**

```elixir
defmodule WebtoonShared.Repo.Migrations.ExtendTablesForBackoffice do
  use Ecto.Migration

  def change do
    # Add crawl_enabled to webtoon_sources
    alter table(:webtoon_sources) do
      add :crawl_enabled, :boolean, default: true
    end

    # Add granular rescrape flags to chapters
    alter table(:chapters) do
      add :needs_title_rescrape, :boolean, default: false
      add :needs_images_rescrape, :boolean, default: false
    end
  end
end
```

### 3.2 Create Schemas

**File:** `/home/user/biblioteka/shared/lib/webtoon_shared/schema/spider_run.ex`

```elixir
defmodule WebtoonShared.Schema.SpiderRun do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "spider_runs" do
    field :spider_name, :string
    field :crawl_id, :string
    field :status, :string, default: "running"
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :chapters_found, :integer, default: 0
    field :chapters_processed, :integer, default: 0
    field :images_downloaded, :integer, default: 0
    field :errors_count, :integer, default: 0

    has_many :errors, WebtoonShared.Schema.SpiderRunError

    timestamps()
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:spider_name, :crawl_id, :status, :started_at, :completed_at,
                    :chapters_found, :chapters_processed, :images_downloaded, :errors_count])
    |> validate_required([:spider_name])
    |> validate_inclusion(:status, ["running", "completed", "failed"])
  end
end
```

**File:** `/home/user/biblioteka/shared/lib/webtoon_shared/schema/spider_run_error.ex`

```elixir
defmodule WebtoonShared.Schema.SpiderRunError do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "spider_run_errors" do
    field :chapter_number, :decimal
    field :error_type, :string
    field :error_message, :string
    field :stacktrace, :string
    field :occurred_at, :utc_datetime

    belongs_to :spider_run, WebtoonShared.Schema.SpiderRun
    belongs_to :webtoon, WebtoonShared.Schema.Webtoon

    timestamps()
  end

  def changeset(error, attrs) do
    error
    |> cast(attrs, [:spider_run_id, :webtoon_id, :chapter_number, :error_type,
                    :error_message, :stacktrace, :occurred_at])
    |> validate_required([:spider_run_id, :error_type, :error_message])
  end
end
```

**File:** `/home/user/biblioteka/shared/lib/webtoon_shared/schema/spider_config.ex`

```elixir
defmodule WebtoonShared.Schema.SpiderConfig do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "spider_configs" do
    field :spider_name, :string
    field :enabled, :boolean, default: true
    field :max_chapters_per_run, :integer, default: 10
    field :request_delay_ms, :integer, default: 1000
    field :last_run_at, :utc_datetime

    timestamps()
  end

  def changeset(config, attrs) do
    config
    |> cast(attrs, [:spider_name, :enabled, :max_chapters_per_run, :request_delay_ms, :last_run_at])
    |> validate_required([:spider_name])
    |> unique_constraint(:spider_name)
    |> validate_number(:max_chapters_per_run, greater_than: 0, less_than_or_equal_to: 100)
    |> validate_number(:request_delay_ms, greater_than_or_equal_to: 0)
  end
end
```

### 3.3 Update Existing Schemas

**File:** `/home/user/biblioteka/shared/lib/webtoon_shared/schema/webtoon_source.ex`

Add field:
```elixir
field :crawl_enabled, :boolean, default: true
```

Update changeset to cast `:crawl_enabled`.

**File:** `/home/user/biblioteka/shared/lib/webtoon_shared/schema/chapter.ex`

Add fields:
```elixir
field :needs_title_rescrape, :boolean, default: false
field :needs_images_rescrape, :boolean, default: false
```

Update `@optional_fields` to include these.

---

## Phase 4: Back-office UI

### 4.1 Admin Layout

**File:** `/home/user/biblioteka/frontend/lib/webtoon_frontend_web/components/layouts/admin.html.heex`

Create admin-specific layout with sidebar navigation:
- Dashboard
- Webtoons
- Spiders
- Runs

### 4.2 Routes

**File:** `/home/user/biblioteka/frontend/lib/webtoon_frontend_web/router.ex`

```elixir
scope "/admin", WebtoonFrontendWeb.Admin do
  pipe_through [:browser, :require_authenticated_user]  # Add auth if needed

  live "/", DashboardLive, :index
  live "/webtoons", WebtoonLive.Index, :index
  live "/webtoons/new", WebtoonLive.Index, :new
  live "/webtoons/:id", WebtoonLive.Show, :show
  live "/webtoons/:id/edit", WebtoonLive.Show, :edit
  live "/spiders", SpiderLive.Index, :index
  live "/spiders/:name", SpiderLive.Show, :show
  live "/spiders/:name/runs", SpiderLive.Runs, :index
  live "/runs/:id", RunLive.Show, :show
end
```

### 4.3 Dashboard LiveView

**File:** `/home/user/biblioteka/frontend/lib/webtoon_frontend_web/live/admin/dashboard_live.ex`

Display:
- Total webtoons, chapters, images counts
- Chapters pending scrape (not yet scraped)
- Chapters needing rescrape (needs_rescrape, needs_title_rescrape, needs_images_rescrape)
- Recent spider runs with status (last 10)
- Active Oban jobs count
- Error rate (last 24h)

### 4.4 Webtoon Management LiveView

**File:** `/home/user/biblioteka/frontend/lib/webtoon_frontend_web/live/admin/webtoon_live/index.ex`

Features:
- List all webtoons with stats per webtoon:
  - Total chapters available (from source)
  - Chapters scraped
  - Chapters with missing images
  - Chapters with missing titles
- Enable/disable crawling per webtoon (toggle crawl_enabled on source)
- Add new webtoon with source URL
- Link to detailed view

**File:** `/home/user/biblioteka/frontend/lib/webtoon_frontend_web/live/admin/webtoon_live/show.ex`

Features:
- Webtoon details and edit form
- Chapter list with status indicators
- Bulk actions:
  - Mark selected chapters for full rescrape
  - Mark selected chapters for title-only rescrape
  - Mark selected chapters for images-only rescrape
- Filter chapters by status (complete, missing title, missing images)

### 4.5 Spider Management LiveView

**File:** `/home/user/biblioteka/frontend/lib/webtoon_frontend_web/live/admin/spider_live/index.ex`

Features:
- List all configured spiders
- Show last run time, status
- Enable/disable spider
- Configure max_chapters_per_run, request_delay_ms
- Manual trigger button (start spider run)

**File:** `/home/user/biblioteka/frontend/lib/webtoon_frontend_web/live/admin/spider_live/runs.ex`

Features:
- Run history for a specific spider
- Filter by status, date range
- Show per-run stats: chapters found/processed, images, errors, duration

### 4.6 Run Detail LiveView

**File:** `/home/user/biblioteka/frontend/lib/webtoon_frontend_web/live/admin/run_live/show.ex`

Features:
- Full run details
- List of chapters processed
- Error log with:
  - Error type and message
  - Associated webtoon/chapter
  - Timestamp
  - Expandable stacktrace
- Retry failed chapters button

---

## Phase 5: Integration Points

### 5.1 Spider Run Tracking

Update spider to create SpiderRun record at start and update at end:

**File:** `/home/user/biblioteka/scraper/lib/webtoon_scraper/spiders/base.ex`

In `init/0`:
```elixir
{:ok, run} = create_spider_run(spider_name, crawl_id)
# Store run.id in spider state or process dictionary
```

When spider completes, update run status to "completed" with final stats.

### 5.2 Error Recording

In `ChapterWorker`, on failure:
```elixir
def perform(%Oban.Job{args: args}) do
  # ... processing ...
rescue
  error ->
    record_error(args["spider_run_id"], args["webtoon_id"], args["chapter_number"], error)
    reraise error, __STACKTRACE__
end

defp record_error(spider_run_id, webtoon_id, chapter_number, error) do
  %SpiderRunError{}
  |> SpiderRunError.changeset(%{
    spider_run_id: spider_run_id,
    webtoon_id: webtoon_id,
    chapter_number: chapter_number,
    error_type: error.__struct__ |> to_string(),
    error_message: Exception.message(error),
    stacktrace: Exception.format_stacktrace(__STACKTRACE__),
    occurred_at: DateTime.utc_now()
  })
  |> Repo.insert()
end
```

### 5.3 Respecting Spider Config

Update spider to read from SpiderConfig:

```elixir
def get_spider_config(spider_name) do
  case Repo.get_by(SpiderConfig, spider_name: spider_name) do
    nil -> %{enabled: true, max_chapters_per_run: 10, request_delay_ms: 1000}
    config -> config
  end
end
```

Check `enabled` before starting spider. Use `max_chapters_per_run` to limit chapters. Use `request_delay_ms` for rate limiting.

### 5.4 Respecting Source crawl_enabled

Update chapter filtering in base spider to also check `source.crawl_enabled`:

```elixir
def get_sources_to_scrape(spider_name) do
  WebtoonSource
  |> where([s], s.site_id == ^spider_name and s.crawl_enabled == true)
  |> preload(:webtoon)
  |> Repo.all()
end
```

---

## Implementation Order

| Step | Task | Files | Effort |
|------|------|-------|--------|
| 1 | Fix image count detection | `mangahub.ex` | Small |
| 2 | Add Oban dependency | `mix.exs`, `config.exs`, `application.ex` | Small |
| 3 | Create Oban migration | Migration file | Small |
| 4 | Create ChapterWorker | `workers/chapter_worker.ex` | Medium |
| 5 | Create EnqueuePipeline | `pipelines/enqueue.ex` | Small |
| 6 | Update existing pipelines to skip chapters | `image_processor.ex`, `r2_upload.ex`, `database_save.ex` | Small |
| 7 | Create tracking migrations | 4 migration files | Small |
| 8 | Create tracking schemas | 3 schema files | Small |
| 9 | Update existing schemas | `webtoon_source.ex`, `chapter.ex` | Small |
| 10 | Create admin layout | `admin.html.heex` | Small |
| 11 | Add admin routes | `router.ex` | Small |
| 12 | Create Dashboard LiveView | `dashboard_live.ex` | Medium |
| 13 | Create Webtoon management | `webtoon_live/*.ex` | Medium |
| 14 | Create Spider management | `spider_live/*.ex` | Medium |
| 15 | Create Run detail view | `run_live/show.ex` | Medium |
| 16 | Integrate spider run tracking | `base.ex`, update spiders | Medium |
| 17 | Integrate error recording | `chapter_worker.ex` | Small |

---

## Testing Checklist

- [ ] Spider completes without GenServer timeout with 20+ chapters
- [ ] Oban jobs process chapters in background
- [ ] Failed jobs retry automatically (up to 3 times)
- [ ] Spider run records created and updated correctly
- [ ] Errors recorded with full context
- [ ] Dashboard shows accurate stats
- [ ] Can enable/disable webtoon crawling from UI
- [ ] Can mark chapters for rescrape from UI
- [ ] Can enable/disable spiders from UI
- [ ] Run history displays correctly with filters
- [ ] Error logs display with expandable stacktraces

---

## Notes

- The shared schemas live in `/home/user/biblioteka/shared/` and are used by both scraper and frontend
- Database is PostgreSQL, accessed via `WebtoonShared.Repo`
- Current chapter schema already has `needs_rescrape` boolean field
- Cover images should continue using synchronous pipeline (single image, fast)
- Consider adding Oban Web UI for job monitoring (optional, separate package)
