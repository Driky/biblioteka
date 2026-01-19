defmodule WebtoonScraper.Runner do
  @moduledoc """
  Runner module for starting spider jobs.
  Handles job scheduling, prevents overlapping runs, and adds jitter.
  Integrates with SpiderRuns for tracking run progress.
  """

  require Logger

  alias WebtoonScraper.SpiderRuns

  @doc """
  Runs a spider if it's not already running.
  Adds random jitter before starting to spread out requests.
  Creates a spider run for tracking if tracking is enabled.
  """
  def run_spider(spider_module) do
    spider_name = get_spider_name(spider_module)

    # Check if spider is enabled in config
    if not SpiderRuns.spider_enabled?(spider_name) do
      Logger.info("#{spider_module} is disabled in config, skipping")
      :disabled
    else
      if spider_running?(spider_module) do
        Logger.info("#{spider_module} already running, skipping")
        :skip
      else
        # Create spider run for tracking
        {:ok, run} = SpiderRuns.start_run(spider_name)
        Logger.info("Created spider run #{run.id} for #{spider_name}")

        # Add random jitter (0-60 seconds) to further spread out requests
        jitter = :rand.uniform(60) * 1000
        Logger.info("#{spider_module} starting in #{div(jitter, 1000)}s (jitter)")
        Process.sleep(jitter)

        Logger.info("Starting #{spider_module}")

        case Crawly.Engine.start_spider(spider_module) do
          {:ok, _pid} ->
            Logger.info("#{spider_module} started successfully")
            # Schedule run completion check
            schedule_run_completion_check(spider_module, spider_name)
            :ok

          {:error, reason} ->
            Logger.error("Failed to start #{spider_module}: #{inspect(reason)}")
            SpiderRuns.complete_run(spider_name, "failed")
            {:error, reason}
        end
      end
    end
  end

  @doc """
  Stops a running spider and completes its run.
  """
  def stop_spider(spider_module) do
    spider_name = get_spider_name(spider_module)

    case Crawly.Engine.stop_spider(spider_module) do
      :ok ->
        Logger.info("#{spider_module} stopped")
        SpiderRuns.complete_run(spider_name, "completed")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to stop #{spider_module}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Returns the list of currently running spiders.
  """
  def running_spiders do
    Crawly.Engine.running_spiders()
  end

  defp spider_running?(spider_module) do
    spider_module in running_spiders()
  end

  defp get_spider_name(spider_module) do
    # Extract site_id from spider module
    # e.g., WebtoonScraper.Spiders.MangaHub -> "mangahub"
    if function_exported?(spider_module, :site_id, 0) do
      spider_module.site_id()
    else
      spider_module
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
    end
  end

  # Schedules a check to see if the spider has finished
  # This is needed because Crawly doesn't provide a clean callback for spider completion
  defp schedule_run_completion_check(spider_module, spider_name) do
    Task.start(fn ->
      check_spider_completion(spider_module, spider_name, 0)
    end)
  end

  defp check_spider_completion(spider_module, spider_name, checks) do
    # Check every 10 seconds for up to 2 hours (720 checks)
    max_checks = 720

    if checks >= max_checks do
      Logger.warning("Spider #{spider_name} run check timed out after #{max_checks * 10}s")
      SpiderRuns.complete_run(spider_name, "completed")
    else
      Process.sleep(10_000)

      if spider_running?(spider_module) do
        check_spider_completion(spider_module, spider_name, checks + 1)
      else
        Logger.info("Spider #{spider_name} finished, completing run")
        SpiderRuns.complete_run(spider_name, "completed")
      end
    end
  end
end
