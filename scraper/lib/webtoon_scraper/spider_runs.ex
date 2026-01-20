defmodule WebtoonScraper.SpiderRuns do
  @moduledoc """
  Context module for tracking spider runs.

  Run lifecycle:
  1. `running` - Crawly is discovering chapters
  2. `processing` - Discovery complete, Oban jobs are processing chapters
  3. `completed` - All jobs finished successfully
  4. `completed_with_errors` - All jobs finished, some failed
  5. `failed` - Critical failure during discovery

  Uses RunTracker GenServer for ETS-backed run ID storage.
  """

  require Logger
  import Ecto.Query

  alias WebtoonShared.Repo
  alias WebtoonShared.Schema.{SpiderRun, SpiderRunError}

  # Legacy function - kept for backward compatibility
  def init_ets, do: :ok

  @doc """
  Creates a new spider run and stores it for the given spider name.
  Returns {:ok, run} or {:error, changeset}.
  """
  def start_run(spider_name, crawl_id \\ nil) do
    Logger.info("SpiderRuns.start_run called for #{spider_name}")
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    result =
      %SpiderRun{}
      |> SpiderRun.changeset(%{
        spider_name: spider_name,
        crawl_id: crawl_id,
        status: "running",
        started_at: now,
        discovery_started_at: now
      })
      |> Repo.insert()

    case result do
      {:ok, run} ->
        Logger.info("SpiderRun #{run.id} created in database for #{spider_name}")

        # Store in RunTracker's ETS table (with error handling)
        try do
          WebtoonScraper.RunTracker.store_run(spider_name, run.id)
          Logger.debug("Run #{run.id} stored in RunTracker ETS")
        rescue
          e ->
            Logger.error("Failed to store run in RunTracker: #{inspect(e)}")
        end

        # Also update spider config last_run_at
        update_config_last_run(spider_name)
        {:ok, run}

      {:error, changeset} ->
        Logger.error("Failed to create spider run: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  @doc """
  Gets the current run ID for a spider name from ETS.
  """
  def get_current_run_id(spider_name) do
    WebtoonScraper.RunTracker.get_run_id(spider_name)
  end

  @doc """
  Updates the crawl_id for a run (set after Crawly assigns it).
  """
  def update_crawl_id(run_id, crawl_id) do
    SpiderRun
    |> Repo.get(run_id)
    |> case do
      nil -> {:error, :not_found}
      run -> run |> SpiderRun.changeset(%{crawl_id: crawl_id}) |> Repo.update()
    end
  end

  @doc """
  Updates discovery metrics: chapters_found and jobs_total.
  Called when the spider finishes discovering chapters.
  """
  def update_discovery_metrics(run_id, chapters_found, jobs_total) do
    SpiderRun
    |> Repo.get(run_id)
    |> case do
      nil ->
        {:error, :not_found}

      run ->
        run
        |> SpiderRun.changeset(%{
          chapters_found: chapters_found,
          jobs_total: jobs_total
        })
        |> Repo.update()
    end
  end

  @doc """
  Marks discovery as complete and transitions to 'processing' status.
  Called when Crawly finishes and Oban jobs are created.
  """
  def complete_discovery(spider_name) do
    case get_current_run_id(spider_name) do
      nil ->
        {:error, :no_active_run}

      run_id ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        SpiderRun
        |> Repo.get(run_id)
        |> case do
          nil ->
            {:error, :not_found}

          run ->
            # If no jobs were created, mark as completed immediately
            new_status = if run.jobs_total == 0, do: "completed", else: "processing"

            run
            |> SpiderRun.changeset(%{
              status: new_status,
              discovery_completed_at: now,
              completed_at: if(new_status == "completed", do: now, else: nil)
            })
            |> Repo.update()
        end
    end
  end

  @doc """
  Records a completed job and updates run metrics.
  Checks if all jobs are done and updates final status.
  """
  def record_job_completed(run_id, job_metrics) do
    %{
      execution_time_ms: execution_time_ms,
      images_found: images_found,
      images_downloaded: images_downloaded,
      images_uploaded: images_uploaded
    } = job_metrics

    # Atomically increment counters
    {1, [run]} =
      from(r in SpiderRun,
        where: r.id == ^run_id,
        update: [
          inc: [
            jobs_completed: 1,
            chapters_processed: 1,
            images_found: ^images_found,
            images_downloaded: ^images_downloaded,
            images_uploaded: ^images_uploaded,
            total_execution_time_ms: ^execution_time_ms
          ]
        ],
        select: r
      )
      |> Repo.update_all([])

    # Check if all jobs are done
    check_run_completion(run)
  end

  @doc """
  Records a failed job and updates run metrics.
  Checks if all jobs are done and updates final status.
  """
  def record_job_failed(run_id, error_message) do
    # Atomically increment failure counter and set last_error
    {1, [run]} =
      from(r in SpiderRun,
        where: r.id == ^run_id,
        update: [
          inc: [jobs_failed: 1, errors_count: 1],
          set: [last_error: ^error_message]
        ],
        select: r
      )
      |> Repo.update_all([])

    # Check if all jobs are done
    check_run_completion(run)
  end

  defp check_run_completion(run) do
    # run already has updated counts from update_all with select
    total_finished = run.jobs_completed + run.jobs_failed

    if total_finished >= run.jobs_total and run.jobs_total > 0 do
      finalize_run(run.id)
    else
      {:ok, run}
    end
  end

  defp finalize_run(run_id) do
    run = Repo.get(SpiderRun, run_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Determine final status based on job results
    final_status =
      cond do
        run.jobs_failed == 0 -> "completed"
        run.jobs_completed == 0 -> "failed"
        true -> "completed_with_errors"
      end

    Logger.info(
      "Finalizing run #{run_id}: #{run.jobs_completed} completed, #{run.jobs_failed} failed -> #{final_status}"
    )

    # Clear from RunTracker
    WebtoonScraper.RunTracker.clear_run(run.spider_name)

    run
    |> SpiderRun.changeset(%{
      status: final_status,
      completed_at: now
    })
    |> Repo.update()
  end

  @doc """
  Legacy function - updates chapters_found count for a run.
  Use update_discovery_metrics/3 for new code.
  """
  def update_chapters_found(run_id, count) do
    SpiderRun
    |> Repo.get(run_id)
    |> case do
      nil -> {:error, :not_found}
      run -> run |> SpiderRun.changeset(%{chapters_found: count}) |> Repo.update()
    end
  end

  @doc """
  Sets the jobs_total count for a run.
  Called after all Oban jobs have been created.
  """
  def set_jobs_total(run_id, count) do
    SpiderRun
    |> Repo.get(run_id)
    |> case do
      nil -> {:error, :not_found}
      run -> run |> SpiderRun.changeset(%{jobs_total: count}) |> Repo.update()
    end
  end

  @doc """
  Legacy function - increments chapters_processed and images_downloaded.
  Use record_job_completed/2 for new code.
  """
  def increment_stats(run_id, chapters \\ 1, images \\ 0) do
    from(r in SpiderRun,
      where: r.id == ^run_id,
      update: [
        inc: [chapters_processed: ^chapters, images_downloaded: ^images]
      ]
    )
    |> Repo.update_all([])
  end

  @doc """
  Increments the error count for a run.
  """
  def increment_errors(run_id, count \\ 1) do
    from(r in SpiderRun,
      where: r.id == ^run_id,
      update: [inc: [errors_count: ^count]]
    )
    |> Repo.update_all([])
  end

  @doc """
  Completes a spider run with the given status.
  Used for immediate completion (e.g., failed discovery).
  For normal completion, use complete_discovery/1 and let job completion handle the rest.
  """
  def complete_run(spider_name, status \\ "completed") do
    case get_current_run_id(spider_name) do
      nil ->
        {:error, :no_active_run}

      run_id ->
        # Clear from RunTracker
        WebtoonScraper.RunTracker.clear_run(spider_name)

        SpiderRun
        |> Repo.get(run_id)
        |> case do
          nil ->
            {:error, :not_found}

          run ->
            now = DateTime.utc_now() |> DateTime.truncate(:second)

            run
            |> SpiderRun.changeset(%{
              status: status,
              completed_at: now,
              discovery_completed_at: run.discovery_completed_at || now
            })
            |> Repo.update()
        end
    end
  end

  @doc """
  Records an error for a spider run.
  """
  def record_error(run_id, attrs) do
    %SpiderRunError{}
    |> SpiderRunError.changeset(
      Map.merge(attrs, %{
        spider_run_id: run_id,
        occurred_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    )
    |> Repo.insert()
    |> case do
      {:ok, _error} ->
        increment_errors(run_id)
        :ok

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Gets the spider config for a given spider name.
  Returns default values if no config exists.
  """
  def get_config(spider_name) do
    alias WebtoonShared.Schema.SpiderConfig

    case Repo.get_by(SpiderConfig, spider_name: spider_name) do
      nil ->
        %{
          enabled: true,
          max_chapters_per_run: Application.get_env(:webtoon_scraper, :max_chapters_per_run, 10),
          request_delay_ms: 1000
        }

      config ->
        %{
          enabled: config.enabled,
          max_chapters_per_run: config.max_chapters_per_run,
          request_delay_ms: config.request_delay_ms
        }
    end
  end

  @doc """
  Checks if a spider is enabled.
  """
  def spider_enabled?(spider_name) do
    get_config(spider_name).enabled
  end

  defp update_config_last_run(spider_name) do
    alias WebtoonShared.Schema.SpiderConfig

    case Repo.get_by(SpiderConfig, spider_name: spider_name) do
      nil ->
        # Create config if it doesn't exist
        %SpiderConfig{}
        |> SpiderConfig.changeset(%{
          spider_name: spider_name,
          last_run_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      config ->
        config
        |> SpiderConfig.changeset(%{
          last_run_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()
    end
  end
end
