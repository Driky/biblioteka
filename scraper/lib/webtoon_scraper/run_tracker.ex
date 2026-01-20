defmodule WebtoonScraper.RunTracker do
  @moduledoc """
  GenServer that owns the ETS table for tracking spider runs.
  Also handles run completion detection with a grace period to allow
  in-flight HTTP requests to complete.
  """

  use GenServer

  require Logger

  @ets_table :spider_run_tracking
  @check_interval 10_000
  # Grace period to wait after Crawly marks spider as done,
  # allowing in-flight HTTP requests to complete
  @completion_grace_period_ms 120_000

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def store_run(spider_name, run_id) do
    GenServer.call(__MODULE__, {:store_run, spider_name, run_id})
  end

  def get_run_id(spider_name) do
    case :ets.lookup(@ets_table, spider_name) do
      [{^spider_name, run_id, _spider_module, _stopped_at}] -> run_id
      [{^spider_name, run_id, _spider_module}] -> run_id
      [{^spider_name, run_id}] -> run_id
      [] -> nil
    end
  end

  def clear_run(spider_name) do
    # Use cast to avoid deadlock when called from within RunTracker
    GenServer.cast(__MODULE__, {:clear_run, spider_name})
  end

  def track_completion(spider_name, spider_module) do
    GenServer.cast(__MODULE__, {:track_completion, spider_name, spider_module})
  end

  # Server callbacks

  @impl true
  def init([]) do
    # Create ETS table owned by this GenServer
    :ets.new(@ets_table, [:named_table, :public, :set])
    # Schedule periodic completion checks
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:store_run, spider_name, run_id}, _from, state) do
    # Format: {spider_name, run_id, spider_module, stopped_at}
    # stopped_at is nil while running, set to timestamp when spider stops
    :ets.insert(@ets_table, {spider_name, run_id, nil, nil})
    Logger.info("RunTracker: Stored run #{run_id} for #{spider_name}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:clear_run, spider_name}, state) do
    :ets.delete(@ets_table, spider_name)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:track_completion, spider_name, spider_module}, state) do
    # Update the entry to include the spider module for completion tracking
    Logger.info("RunTracker: Registering completion tracking for #{spider_name} (#{spider_module})")

    case :ets.lookup(@ets_table, spider_name) do
      [{^spider_name, run_id, _, _}] ->
        :ets.insert(@ets_table, {spider_name, run_id, spider_module, nil})
        Logger.info("RunTracker: Updated entry with spider_module for run #{run_id}")

      [{^spider_name, run_id, _}] ->
        :ets.insert(@ets_table, {spider_name, run_id, spider_module, nil})
        Logger.info("RunTracker: Updated entry with spider_module for run #{run_id}")

      [{^spider_name, run_id}] ->
        :ets.insert(@ets_table, {spider_name, run_id, spider_module, nil})
        Logger.info("RunTracker: Updated entry with spider_module for run #{run_id}")

      [] ->
        Logger.warning("RunTracker: No entry found for #{spider_name}, cannot track completion")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:check_completions, state) do
    check_all_completions()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_completions, @check_interval)
  end

  defp check_all_completions do
    # Crawly.Engine.running_spiders() returns a map like %{SpiderModule => {pid, crawl_id}}
    running_spiders_map = Crawly.Engine.running_spiders()
    running_spider_modules = Map.keys(running_spiders_map)
    tracked_runs = :ets.tab2list(@ets_table)

    if length(tracked_runs) > 0 do
      Logger.debug("RunTracker: Checking #{length(tracked_runs)} tracked runs, running_spiders=#{inspect(running_spider_modules)}")
    end

    now = System.monotonic_time(:millisecond)

    tracked_runs
    |> Enum.each(fn
      {spider_name, run_id, spider_module, stopped_at} when not is_nil(spider_module) ->
        spider_running = spider_module in running_spider_modules

        cond do
          spider_running and stopped_at != nil ->
            # Spider is running again (maybe restarted?), clear stopped_at
            Logger.info("RunTracker: Spider #{spider_name} is running again, clearing stopped_at")
            :ets.insert(@ets_table, {spider_name, run_id, spider_module, nil})

          spider_running ->
            # Spider still running, nothing to do
            Logger.debug("RunTracker: Spider #{spider_name} still running")

          stopped_at == nil ->
            # Spider just stopped, record the time but wait for grace period
            Logger.info("RunTracker: Spider #{spider_name} stopped, starting #{@completion_grace_period_ms}ms grace period for in-flight requests")
            :ets.insert(@ets_table, {spider_name, run_id, spider_module, now})

          now - stopped_at >= @completion_grace_period_ms ->
            # Grace period elapsed, mark run as complete
            Logger.info("RunTracker: Grace period elapsed for #{spider_name}, completing run #{run_id}")
            WebtoonScraper.SpiderRuns.complete_run(spider_name, "completed")

          true ->
            # Still in grace period
            remaining = @completion_grace_period_ms - (now - stopped_at)
            Logger.debug("RunTracker: Spider #{spider_name} in grace period, #{remaining}ms remaining")
        end

      {spider_name, run_id, nil, _} ->
        Logger.debug("RunTracker: Run #{run_id} for #{spider_name} has no spider_module set, skipping completion check")

      # Handle old format entries (backwards compatibility)
      {spider_name, run_id, spider_module} when not is_nil(spider_module) ->
        if spider_module not in running_spider_modules do
          # Migrate to new format with stopped_at
          Logger.info("RunTracker: Migrating #{spider_name} to new format, starting grace period")
          :ets.insert(@ets_table, {spider_name, run_id, spider_module, now})
        end

      _ ->
        :ok
    end)
  end
end
