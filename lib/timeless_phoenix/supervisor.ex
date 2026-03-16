defmodule TimelessPhoenix.Supervisor do
  @moduledoc false

  use Supervisor

  @embedded_log_defaults [
    retention_max_age: 3 * 86_400,
    retention_max_size: 128 * 1_048_576,
    retention_check_interval: 60_000,
    max_term_index_entries: 100_000
  ]

  @embedded_trace_defaults [
    retention_max_age: 3 * 86_400,
    retention_max_size: 128 * 1_048_576,
    retention_check_interval: 60_000,
    max_term_index_entries: 50_000
  ]

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

    # HTTP endpoint config
    http = Keyword.get(opts, :http, [])

    # Configure TimelessLogs app env before starting
    log_overrides = Keyword.get(opts, :timeless_logs, [])
    merged_logs = Keyword.merge(@embedded_log_defaults, log_overrides)

    log_env = [{:data_dir, logs_dir} | merged_logs]

    log_env =
      case Keyword.fetch(http, :logs) do
        {:ok, port} -> [{:http, [port: port]} | log_env]
        :error -> log_env
      end

    for {key, val} <- log_env do
      Application.put_env(:timeless_logs, key, val)
    end

    # Configure TimelessTraces app env before starting
    trace_overrides = Keyword.get(opts, :timeless_traces, [])
    merged_traces = Keyword.merge(@embedded_trace_defaults, trace_overrides)

    trace_env = [{:data_dir, spans_dir} | merged_traces]

    trace_env =
      case Keyword.fetch(http, :traces) do
        {:ok, port} -> [{:http, [port: port]} | trace_env]
        :error -> trace_env
      end

    for {key, val} <- trace_env do
      Application.put_env(:timeless_traces, key, val)
    end

    # Configure OpenTelemetry to export to TimelessTraces
    Application.put_env(:opentelemetry, :traces_exporter, {TimelessTraces.Exporter, []})

    # Attach OTel instrumentation for Phoenix and Bandit
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)

    # Propagate OTel trace context into Logger metadata so logs carry trace_id/span_id
    TimelessPhoenix.LoggerPropagator.attach()

    # Timeless opts
    store = TimelessPhoenix.store_name(name)
    reporter_name = TimelessPhoenix.reporter_name(name)
    timeless_extra = Keyword.get(opts, :timeless, [])

    timeless_opts =
      [
        name: store,
        data_dir: metrics_dir,
        raw_retention_seconds: 3 * 86_400,
        daily_retention_seconds: 90 * 86_400,
        max_blocks: 50
      ]
      |> Keyword.merge(timeless_extra)

    # Reporter opts
    metrics = Keyword.get_lazy(opts, :metrics, &TimelessPhoenix.DefaultMetrics.all/0)
    reporter_extra = Keyword.get(opts, :reporter, [])

    reporter_opts =
      [store: store, metrics: metrics, name: reporter_name] ++ reporter_extra

    # Optionally start the metrics HTTP endpoint
    children =
      [
        # Start TimelessMetrics (named instance)
        {TimelessMetrics, timeless_opts}
      ] ++
        case Keyword.fetch(http, :metrics) do
          {:ok, port} -> [{TimelessMetrics.HTTP, store: store, port: port}]
          :error -> []
        end ++
        [
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
