defmodule TimelessPhoenix.Supervisor do
  @moduledoc false

  use Supervisor

  @embedded_owner_table TimelessPhoenix.EmbeddedOwner

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
    validate_name!(name)
    sup_name = :"tp_#{name}_sup"
    Supervisor.start_link(__MODULE__, opts, name: sup_name)
  end

  @impl true
  def init(opts) do
    name = Keyword.get(opts, :name, :default)
    validate_name!(name)
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

    log_overrides = Keyword.get(opts, :timeless_logs, [])
    trace_overrides = Keyword.get(opts, :timeless_traces, [])
    timeless_extra = Keyword.get(opts, :timeless, [])

    logs_embedded? = not external?(:timeless_logs, log_overrides)
    traces_embedded? = not external?(:timeless_traces, trace_overrides)
    metrics_embedded? = not external?(:timeless_metrics, timeless_extra)

    claim_embedded_singletons!(logs_embedded? or traces_embedded?)

    # The metrics package ships the timeless-libsql extension with its
    # precompiled natives; logs and traces load the same .so.
    shared_extension =
      Application.app_dir(:timeless_metrics, "priv/native/timeless_sqlite_ext.so")

    if (metrics_embedded? or logs_embedded? or traces_embedded?) and
         not File.regular?(shared_extension) do
      raise ArgumentError,
            "timeless_phoenix cannot start the embedded stores because the bundled " <>
              "timeless-libsql extension is missing: #{shared_extension}"
    end

    metrics_dir = Path.join(data_dir, "metrics")
    logs_dir = Path.join(data_dir, "logs")
    spans_dir = Path.join(data_dir, "spans")

    for {embedded?, dir} <- [
          {metrics_embedded?, metrics_dir},
          {logs_embedded?, logs_dir},
          {traces_embedded?, spans_dir}
        ],
        embedded? do
      File.mkdir_p!(dir)
      ensure_writable!(dir)
    end

    # Configure TimelessLogs app env before starting — unless the host
    # declared external ownership, which we must never clobber.
    logs_restart? =
      if logs_embedded? do
        log_env =
          @embedded_log_defaults
          |> Keyword.merge(engine: :libsql, extension_path: shared_extension)
          |> Keyword.merge(log_overrides)

        configure_app(:timeless_logs, [{:data_dir, logs_dir} | log_env])
      else
        false
      end

    # Configure TimelessTraces app env before starting — same rule.
    traces_restart? =
      if traces_embedded? do
        trace_env =
          @embedded_trace_defaults
          |> Keyword.merge(engine: :libsql, extension_path: shared_extension)
          |> Keyword.merge(trace_overrides)

        configure_app(:timeless_traces, [{:data_dir, spans_dir} | trace_env])
      else
        false
      end

    TimelessPhoenix.Identity.ensure_opentelemetry_resource()

    # Export OTel spans into the embedded traces store only when we own it.
    if traces_embedded?, do: configure_traces_exporter()

    # Attach OTel instrumentation for Phoenix and Bandit
    setup_opentelemetry_instrumentation()

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
    reporter_extra = Keyword.get(opts, :reporter, [])

    reporter_opts = fn ->
      defaults = [store: store, name: reporter_name]

      defaults =
        if Keyword.has_key?(reporter_extra, :metrics) do
          defaults
        else
          Keyword.put(
            defaults,
            :metrics,
            Keyword.get_lazy(opts, :metrics, &TimelessPhoenix.DefaultMetrics.all/0)
          )
        end

      Keyword.merge(defaults, reporter_extra)
    end

    # Start each owned signal independently so one store cannot cascade
    # restarts through the others.
    children =
      if(metrics_embedded?, do: [{TimelessMetrics, timeless_opts}], else: []) ++
        if(logs_embedded?,
          do: [
            {TimelessPhoenix.ApplicationMonitor,
             app: :timeless_logs,
             supervisor: TimelessLogs.Supervisor,
             restart_before_start?: logs_restart?}
          ],
          else: []
        ) ++
        if(traces_embedded?,
          do: [
            {TimelessPhoenix.ApplicationMonitor,
             app: :timeless_traces,
             supervisor: TimelessTraces.Supervisor,
             restart_before_start?: traces_restart?}
          ],
          else: []
        ) ++
        if(metrics_embedded?,
          do: [{TimelessMetricsDashboard.Reporter, reporter_opts.()}],
          else: []
        )

    Supervisor.init(children, strategy: :one_for_one)
  end

  # A signal is externally owned when the host's app env OR the caller's
  # overrides say so — TimelessPhoenix must never clobber or restart an
  # external-owner signal into embedded mode.
  defp external?(app, overrides) do
    Keyword.get(overrides, :owner, Application.get_env(app, :owner, :embedded)) == :external
  end

  defp configure_app(app, values) do
    Enum.reduce(values, false, fn {key, value}, changed? ->
      changed? = changed? or Application.get_env(app, key) != value
      Application.put_env(app, key, value)
      changed?
    end)
  end

  defp ensure_writable!(dir) do
    probe =
      Path.join(
        dir,
        ".timeless_phoenix_write_probe_#{System.unique_integer([:positive, :monotonic])}"
      )

    case File.open(probe, [:write, :exclusive]) do
      {:ok, io} ->
        File.close(io)
        File.rm(probe)
        :ok

      {:error, reason} ->
        raise ArgumentError,
              "timeless_phoenix data directory is not writable: #{dir} (#{inspect(reason)})"
    end
  end

  defp configure_traces_exporter do
    exporter = {TimelessTraces.Exporter, []}

    case Application.get_env(:opentelemetry, :traces_exporter) do
      nil ->
        Application.put_env(:opentelemetry, :traces_exporter, exporter)

      ^exporter ->
        :ok

      existing ->
        require Logger

        Logger.warning(
          "timeless_phoenix did not replace the existing OpenTelemetry traces exporter " <>
            "#{inspect(existing)}; configure #{inspect(exporter)} explicitly to store spans " <>
            "in embedded TimelessTraces"
        )
    end
  end

  defp setup_opentelemetry_instrumentation do
    unless handler_attached?([:bandit, :request, :start], {OpentelemetryBandit, :otel_bandit}) do
      case OpentelemetryBandit.setup() do
        :ok -> :ok
        {:error, :already_exists} -> :ok
      end
    end

    phoenix_handlers = [
      {[:phoenix, :endpoint, :start], {OpentelemetryPhoenix, :endpoint_start}},
      {[:phoenix, :router_dispatch, :start], {OpentelemetryPhoenix, :router_dispatch_start}}
    ]

    if Enum.any?(phoenix_handlers, fn {event, id} -> not handler_attached?(event, id) end) do
      :ok = OpentelemetryPhoenix.setup(adapter: :bandit)
    end
  end

  defp handler_attached?(event, id) do
    event
    |> :telemetry.list_handlers()
    |> Enum.any?(&(&1.id == id))
  end

  defp claim_embedded_singletons!(false), do: :ok

  defp claim_embedded_singletons!(true) do
    :ets.new(@embedded_owner_table, [:named_table, :set, :protected])
    :ok
  rescue
    ArgumentError ->
      owner = :ets.info(@embedded_owner_table, :owner)

      raise ArgumentError,
            "only one TimelessPhoenix instance may own embedded logs or traces; " <>
              "#{inspect(owner)} already owns the singleton signal applications. " <>
              "Configure owner: :external for both signals before starting additional " <>
              "named metrics instances."
  end

  defp validate_name!(name) when is_atom(name), do: :ok

  defp validate_name!(name) do
    raise ArgumentError, ":name must be an atom, got: #{inspect(name)}"
  end
end
