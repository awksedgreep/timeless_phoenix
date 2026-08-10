defmodule TimelessPhoenix.Supervisor do
  @moduledoc false

  use Supervisor

  @embedded_log_defaults [
    retention_max_age: 7 * 86_400,
    retention_max_size: nil,
    retention_check_interval: 60_000,
    max_term_index_entries: nil
  ]

  @embedded_trace_defaults [
    retention_max_age: 7 * 86_400,
    retention_max_size: nil,
    retention_check_interval: 60_000,
    max_term_index_entries: nil
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

    # 2.0: the embedded Elixir engines no longer serve HTTP — the Rust
    # services own the HTTP surface, and both modes share one on-disk
    # format, so the services can take over the same databases.
    if Keyword.get(opts, :http, []) != [] do
      raise ArgumentError,
            "timeless_phoenix 2.0 no longer serves signal HTTP APIs from the embedded " <>
              "engines. Remove the :http option and run the timeless-metrics-api / " <>
              "timeless-logs-api / timeless-traces-api services from the timeless-libsql " <>
              "release bundle against the same data directories instead — embedded and " <>
              "Rust modes share one storage format. See the production guide."
    end

    metrics_dir = Path.join(data_dir, "metrics")
    logs_dir = Path.join(data_dir, "logs")
    spans_dir = Path.join(data_dir, "spans")

    # The metrics package ships the timeless-libsql extension with its
    # precompiled natives; logs and traces load the same .so.
    shared_extension =
      Application.app_dir(:timeless_metrics, "priv/native/timeless_sqlite_ext.so")

    # Configure TimelessLogs app env before starting — unless the host
    # declared external ownership, which we must never clobber.
    log_overrides = Keyword.get(opts, :timeless_logs, [])
    logs_embedded? = not external?(:timeless_logs, log_overrides)

    if logs_embedded? do
      File.mkdir_p!(logs_dir)

      log_env =
        @embedded_log_defaults
        |> Keyword.merge(engine: :libsql, extension_path: shared_extension)
        |> Keyword.merge(log_overrides)

      for {key, val} <- [{:data_dir, logs_dir} | log_env] do
        Application.put_env(:timeless_logs, key, val)
      end
    end

    # Configure TimelessTraces app env before starting — same rule.
    trace_overrides = Keyword.get(opts, :timeless_traces, [])
    traces_embedded? = not external?(:timeless_traces, trace_overrides)

    if traces_embedded? do
      File.mkdir_p!(spans_dir)

      trace_env =
        @embedded_trace_defaults
        |> Keyword.merge(engine: :libsql, extension_path: shared_extension)
        |> Keyword.merge(trace_overrides)

      for {key, val} <- [{:data_dir, spans_dir} | trace_env] do
        Application.put_env(:timeless_traces, key, val)
      end
    end

    TimelessPhoenix.Identity.ensure_opentelemetry_resource()

    # Export OTel spans into the embedded traces store only when we own it.
    if traces_embedded? do
      Application.put_env(:opentelemetry, :traces_exporter, {TimelessTraces.Exporter, []})
    end

    # Attach OTel instrumentation for Phoenix and Bandit
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)

    # Propagate OTel trace context into Logger metadata so logs carry trace_id/span_id
    TimelessPhoenix.LoggerPropagator.attach()

    # Metrics declares its engine here for the same reason logs and traces do
    # above, rather than inheriting timeless_metrics' default. Relying on the
    # default meant this composition layer pinned two signals explicitly and let
    # the third drift with its package, so a change to that default would have
    # silently moved metrics — and only metrics — onto a different engine. The
    # value matches what the default already resolves to, so nothing changes
    # today; what changes is that all three now say so in one place.
    # Override per-signal through the :timeless keyword (e.g. engine: :rust,
    # or auto_migrate: false to keep a legacy store unconverted).
    store = TimelessPhoenix.store_name(name)
    reporter_name = TimelessPhoenix.reporter_name(name)
    timeless_extra = Keyword.get(opts, :timeless, [])
    metrics_embedded? = Keyword.get(timeless_extra, :owner, :embedded) != :external

    if metrics_embedded?, do: File.mkdir_p!(metrics_dir)

    timeless_opts =
      [
        name: store,
        engine: :libsql,
        data_dir: metrics_dir,
        raw_retention_seconds: 7 * 86_400,
        daily_retention_seconds: 90 * 86_400,
        max_blocks: 50
      ]
      |> Keyword.merge(Keyword.delete(timeless_extra, :owner))

    # Reporter opts
    metrics = Keyword.get_lazy(opts, :metrics, &TimelessPhoenix.DefaultMetrics.all/0)
    reporter_extra = Keyword.get(opts, :reporter, [])

    reporter_opts =
      [store: store, metrics: metrics, name: reporter_name] ++ reporter_extra

    # Optionally start the metrics HTTP endpoint
    children =
      if(metrics_embedded?, do: [{TimelessMetrics, timeless_opts}], else: []) ++
        if(logs_embedded?,
          do: [%{id: :timeless_logs_app, start: {__MODULE__, :ensure_app, [:timeless_logs]}}],
          else: []
        ) ++
        if(traces_embedded?,
          do: [%{id: :timeless_traces_app, start: {__MODULE__, :ensure_app, [:timeless_traces]}}],
          else: []
        ) ++
        if(metrics_embedded?, do: [{TimelessMetricsDashboard.Reporter, reporter_opts}], else: [])

    Supervisor.init(children, strategy: :rest_for_one)
  end

  # A signal is externally owned when the host's app env OR the caller's
  # overrides say so — TimelessPhoenix must never clobber or restart an
  # external-owner signal into embedded mode.
  defp external?(app, overrides) do
    Keyword.get(overrides, :owner, Application.get_env(app, :owner, :embedded)) == :external
  end

  @doc false
  def ensure_app(app) do
    # Only reached for EMBEDDED signals (external ones are never bounced):
    # the app may have been auto-started by OTP with default config before
    # our Application.put_env calls above. Stop it first so it restarts
    # with the correct config.
    Application.stop(app)

    case Application.ensure_all_started(app) do
      {:ok, _} -> :ignore
      {:error, reason} -> {:error, reason}
    end
  end
end
