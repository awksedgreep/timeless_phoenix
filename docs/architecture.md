# Architecture

TimelessPhoenix is an orchestration layer that starts and configures three independent storage engines and presents them as a unified LiveDashboard experience.

## Supervision tree

```
TimelessPhoenix.Supervisor (:one_for_one)
├── TimelessMetrics (named instance)
│   └── Per-series actor engine, SQLite index, Gorilla+Zstd compression
├── TimelessLogs application monitor
│   └── Logger handler, Buffer, Writer, Index, Compactor, Retention
├── TimelessTraces application monitor
│   └── OTel Exporter, Buffer, Writer, Index, Compactor, Retention
└── TimelessMetricsDashboard.Reporter
    └── Telemetry event handler → writes metrics to TimelessMetrics
```

The supervisor uses `:one_for_one` so a failure in one signal does not restart
the independent stores. Permanent monitor children start the TimelessLogs and
TimelessTraces OTP applications and re-establish them if their application
supervisors exit.

## Data flow

```
Phoenix App
    │
    ├── Logger calls ──────────► TimelessLogs ──► priv/observability/logs/
    │                              (automatic via :logger handler)
    │
    ├── OpenTelemetry spans ───► TimelessTraces ──► priv/observability/spans/
    │   (auto: Phoenix + Bandit)   (via Exporter)
    │
    └── Telemetry events ──────► Reporter ──► TimelessMetrics ──► priv/observability/metrics/
        (VM, Phoenix, LiveView,    (aggregates & writes)
         Ecto, custom)
```

### Metrics path

1. Your app emits telemetry events (Phoenix requests, Ecto queries, VM stats, custom events)
2. The `TimelessMetricsDashboard.Reporter` attaches to all configured `Telemetry.Metrics` definitions
3. Reporter aggregates measurements and writes them to the named TimelessMetrics store
4. TimelessMetrics compresses data into blocks using Gorilla + Zstd encoding
5. LiveDashboard reads historical data via `TimelessPhoenix.metrics_history/3`

### Logs path

1. Your app (and libraries) call `Logger.info/2`, `Logger.error/2`, etc.
2. TimelessLogs installs an OTP `:logger` handler that captures all log events
3. Log entries buffer in a GenServer and flush every 1 second or 1000 entries
4. Raw blocks are written to disk, then compacted into OpenZL-compressed blocks
5. An SQLite index + ETS cache enable fast querying by level, time, metadata, message

### Traces path

1. TimelessPhoenix calls `OpentelemetryBandit.setup()` and `OpentelemetryPhoenix.setup(adapter: :bandit)` during supervisor init
2. All HTTP requests automatically create OpenTelemetry spans
3. The `TimelessTraces.Exporter` reads spans directly from the OTel SDK's ETS table (no HTTP, no protobuf)
4. Spans buffer and flush to raw blocks, then compact into OpenZL-compressed blocks
5. An SQLite index with trace index and term index enables fast trace lookup and span queries

## Initialization sequence

When the supervisor starts:

1. **Create directories**: `metrics/`, `logs/`, `spans/` under `data_dir`
2. **Configure TimelessLogs**: Set application env (`:data_dir`, plus any overrides from `:timeless_logs` option)
3. **Configure TimelessTraces**: Set application env (`:data_dir`, plus any overrides from `:timeless_traces` option)
4. **Configure OpenTelemetry**: Use `TimelessTraces.Exporter` when no exporter is configured; preserve and warn about any existing exporter
5. **Attach OTel instrumentation**: `OpentelemetryBandit.setup()` and `OpentelemetryPhoenix.setup(adapter: :bandit)`
6. **Start children**: TimelessMetrics, monitored TimelessLogs/TimelessTraces applications, and Reporter under independent supervision

## Router integration

The `timeless_phoenix_dashboard` macro expands to:

```elixir
# 1. Mount the metrics backup download plug
forward "/timeless/downloads", TimelessMetricsDashboard.DownloadPlug, store: store

# 2. Mount LiveDashboard with all pages
live_dashboard "/dashboard",
  metrics: MetricsModule,
  metrics_history: {TimelessPhoenix, :metrics_history, [instance_name]},
  additional_pages: [
    timeless: {TimelessMetricsDashboard.Page, store: store, download_path: path},
    logs: TimelessLogsDashboard.Page,
    traces: TimelessTracesDashboard.Page
  ]
```

## Storage layout

```
priv/observability/
├── metrics/          # TimelessMetrics TSDB
│   ├── timeless.db   # SQLite index
│   └── series/       # Gorilla+Zstd compressed blocks per series
├── logs/             # TimelessLogs
│   ├── index.db      # SQLite index
│   └── blocks/       # OpenZL compressed log blocks
└── spans/            # TimelessTraces
    ├── index.db      # SQLite index
    └── blocks/       # OpenZL compressed span blocks
```

## Compression ratios

| Engine | Format | Ratio |
|--------|--------|-------|
| TimelessMetrics | Gorilla + Zstd | ~11.5x |
| TimelessLogs | OpenZL columnar | ~12.5x |
| TimelessTraces | OpenZL columnar | ~10x |
