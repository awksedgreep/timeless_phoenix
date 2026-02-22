defmodule TimelessPhoenix.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(opts) do
    name = Keyword.get(opts, :name, :default)
    sup_name = :"tp_#{name}_sup"
    Supervisor.start_link(__MODULE__, opts, name: sup_name)
  end

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, :default)
    data_dir = Keyword.fetch!(opts, :data_dir)

    metrics_dir = Path.join(data_dir, "metrics")
    logs_dir = Path.join(data_dir, "logs")
    spans_dir = Path.join(data_dir, "spans")

    File.mkdir_p!(metrics_dir)
    File.mkdir_p!(logs_dir)
    File.mkdir_p!(spans_dir)

    # Configure TimelessLogs app env before starting
    log_overrides = Keyword.get(opts, :timeless_logs, [])

    for {key, val} <- [{:data_dir, logs_dir} | log_overrides] do
      Application.put_env(:timeless_logs, key, val)
    end

    # Configure TimelessTraces app env before starting
    trace_overrides = Keyword.get(opts, :timeless_traces, [])

    for {key, val} <- [{:data_dir, spans_dir} | trace_overrides] do
      Application.put_env(:timeless_traces, key, val)
    end

    # Configure OpenTelemetry to export to TimelessTraces
    Application.put_env(:opentelemetry, :traces_exporter, {TimelessTraces.Exporter, []})

    # Attach OTel instrumentation for Phoenix and Bandit
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup()

    # Timeless opts
    store = TimelessPhoenix.store_name(name)
    reporter_name = TimelessPhoenix.reporter_name(name)
    timeless_extra = Keyword.get(opts, :timeless, [])

    timeless_opts =
      [name: store, data_dir: metrics_dir] ++ timeless_extra

    # Reporter opts
    metrics = Keyword.get_lazy(opts, :metrics, &TimelessPhoenix.DefaultMetrics.all/0)
    reporter_extra = Keyword.get(opts, :reporter, [])

    reporter_opts =
      [store: store, metrics: metrics, name: reporter_name] ++ reporter_extra

    children = [
      # Start TimelessMetrics (named instance)
      {TimelessMetrics, timeless_opts},

      # Start TimelessLogs and TimelessTraces as OTP apps (singleton)
      %{id: :timeless_logs_app, start: {__MODULE__, :ensure_app, [:timeless_logs]}},
      %{id: :timeless_traces_app, start: {__MODULE__, :ensure_app, [:timeless_traces]}},

      # Start the telemetry reporter
      {TimelessMetricsDashboard.Reporter, reporter_opts}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc false
  def ensure_app(app) do
    case Application.ensure_all_started(app) do
      {:ok, _} -> :ignore
      {:error, reason} -> {:error, reason}
    end
  end
end
