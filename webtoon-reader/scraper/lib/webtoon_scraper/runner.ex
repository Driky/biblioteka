defmodule WebtoonScraper.Runner do
  @moduledoc """
  Runner module for starting spider jobs.
  Handles job scheduling, prevents overlapping runs, and adds jitter.
  """

  require Logger

  @doc """
  Runs a spider if it's not already running.
  Adds random jitter before starting to spread out requests.
  """
  def run_spider(spider_module) do
    if spider_running?(spider_module) do
      Logger.info("#{spider_module} already running, skipping")
      :skip
    else
      # Add random jitter (0-60 seconds) to further spread out requests
      jitter = :rand.uniform(60) * 1000
      Logger.info("#{spider_module} starting in #{div(jitter, 1000)}s (jitter)")
      Process.sleep(jitter)

      Logger.info("Starting #{spider_module}")

      case Crawly.Engine.start_spider(spider_module) do
        {:ok, _pid} ->
          Logger.info("#{spider_module} started successfully")
          :ok

        {:error, reason} ->
          Logger.error("Failed to start #{spider_module}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Stops a running spider.
  """
  def stop_spider(spider_module) do
    case Crawly.Engine.stop_spider(spider_module) do
      :ok ->
        Logger.info("#{spider_module} stopped")
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
end
