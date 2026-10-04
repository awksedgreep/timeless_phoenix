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
    * `:name` — atom used for metrics/process naming (default: `:default`);
      embedded logs and traces are node-wide singletons
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
    validate_name!(name)

    %{
      id: {__MODULE__, name},
      start: {TimelessPhoenix.Supervisor, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc """
  Callback for LiveDashboard's `metrics_history` option.

  Delegates to `TimelessMetricsDashboard.metrics_history/3` using the Timeless store
  name for this instance.

  ## Router Configuration

      live_dashboard "/dashboard",
        metrics: MyApp.Telemetry,
        metrics_history: {TimelessPhoenix, :metrics_history, []}

  Or with a named instance:

      metrics_history: {TimelessPhoenix, :metrics_history, [:my_instance]}
  """
  def metrics_history(metric, name \\ :default, opts \\ []) when is_atom(name) do
    store = store_name(name)
    TimelessMetricsDashboard.metrics_history(metric, store, opts)
  end

  @doc """
  Returns additional_pages config for LiveDashboard with all three dashboard pages,
  and a fourth, `beam` ("TimelessAcct"), when `timeless_beam_acct` is among the
  application's dependencies: its recordings of the processes of a node.

  ## Options

    * `:name` — instance name (default: `:default`)
    * `:download_path` — path to DownloadPlug (default: `"/timeless/downloads"`)
    * `:beam_acct` — whether to include the `timeless_beam_acct` page
      (default: whether it is available)
  """
  def dashboard_pages(opts \\ []) do
    name = Keyword.get(opts, :name, :default)
    validate_name!(name)
    download_path = Keyword.get(opts, :download_path, "/timeless/downloads")
    store = store_name(name)

    [
      timeless: {TimelessMetricsDashboard.Page, store: store, download_path: download_path},
      logs: TimelessLogsDashboard.Page,
      traces: TimelessTracesDashboard.Page
    ] ++ beam_acct_page(Keyword.get(opts, :beam_acct, beam_acct_available?()))
  end

  @beam_acct_page TimelessBeamAcct.Dashboard.Page

  defp beam_acct_page(true), do: [beam: @beam_acct_page]
  defp beam_acct_page(false), do: []

  # The page is compiled only where LiveDashboard is, and timeless_beam_acct
  # is an optional companion: present in some applications, not in others.
  defp beam_acct_available?, do: Code.ensure_loaded?(@beam_acct_page)

  @doc false
  def store_name(name) when is_atom(name), do: :"tp_#{name}_timeless"

  @doc """
  Verify the 2.0 libSQL engines on a live node: engine flags, extension
  handshake, legacy-store conversion status, and data presence for all
  three signals. Prints a report unless `quiet: true`; returns `{verdict, report}` with
  verdict `:ok` | `:warn` | `:error`.

      TimelessPhoenix.doctor()
      TimelessPhoenix.doctor(:default, quiet: true)
  """
  def doctor(name \\ :default, opts \\ []) when is_atom(name) and is_list(opts) do
    TimelessPhoenix.Doctor.run(name, opts)
  end

  @doc false
  def reporter_name(name) when is_atom(name), do: :"tp_#{name}_reporter"

  defp validate_name!(name) when is_atom(name), do: :ok

  defp validate_name!(name) do
    raise ArgumentError, ":name must be an atom, got: #{inspect(name)}"
  end
end
