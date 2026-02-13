defmodule TimelessPhoenix do
  @moduledoc """
  Unified observability for Phoenix: persistent metrics, logs, and traces in LiveDashboard.

  One dep, one child_spec, one router macro.

  ## Quick Start

      # 1. Supervision tree (one line)
      {TimelessPhoenix, data_dir: "/var/lib/obs"}

      # 2. Router (one macro)
      import TimelessPhoenix.Router
      timeless_phoenix_dashboard("/dashboard")

  ## Child Spec Options

    * `:data_dir` (required) — base directory; creates `metrics/`, `logs/`, `spans/` subdirs
    * `:name` — instance name for process naming (default: `:default`)
    * `:metrics` — `Telemetry.Metrics` list for reporter (default: `TimelessPhoenix.DefaultMetrics.all()`)
    * `:timeless` — extra opts forwarded to TimelessMetrics
    * `:timeless_logs` — application env overrides for TimelessLogs
    * `:timeless_traces` — application env overrides for TimelessTraces
    * `:reporter` — extra opts for Reporter (`:flush_interval`, `:prefix`)
  """

  @doc """
  Returns a child spec that starts all three observability engines + reporter.
  """
  def child_spec(opts) do
    name = Keyword.get(opts, :name, :default)

    %{
      id: {__MODULE__, name},
      start: {TimelessPhoenix.Supervisor, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Callback for LiveDashboard's `metrics_history` option.

  Delegates to `TimelessDashboard.metrics_history/3` using the Timeless store
  name for this instance.

  ## Router Configuration

      live_dashboard "/dashboard",
        metrics: MyApp.Telemetry,
        metrics_history: {TimelessPhoenix, :metrics_history, []}

  Or with a named instance:

      metrics_history: {TimelessPhoenix, :metrics_history, [:my_instance]}
  """
  def metrics_history(metric, name \\ :default, opts \\ []) do
    store = store_name(name)
    TimelessDashboard.metrics_history(metric, store, opts)
  end

  @doc """
  Returns additional_pages config for LiveDashboard with all three dashboard pages.

  ## Options

    * `:name` — instance name (default: `:default`)
    * `:download_path` — path to DownloadPlug (default: `"/timeless/downloads"`)
  """
  def dashboard_pages(opts \\ []) do
    name = Keyword.get(opts, :name, :default)
    download_path = Keyword.get(opts, :download_path, "/timeless/downloads")
    store = store_name(name)

    [
      timeless: {TimelessDashboard.Page, store: store, download_path: download_path},
      logs: TimelessLogsDashboard.Page,
      spans: TimelessTracesDashboard.Page
    ]
  end

  @doc false
  def store_name(name), do: :"tp_#{name}_timeless"

  @doc false
  def reporter_name(name), do: :"tp_#{name}_reporter"
end
