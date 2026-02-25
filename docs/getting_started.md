# Getting Started

TimelessPhoenix adds persistent metrics, logs, and traces to your Phoenix app with a single dependency. Everything shows up in LiveDashboard -- no external infrastructure required.

## What you get

- **Metrics** -- Telemetry metrics stored in TimelessMetrics (Gorilla + Zstd TSDB) that survive restarts
- **Logs** -- All Logger output captured and indexed in TimelessLogs (SQLite + OpenZL compressed blocks)
- **Traces** -- OpenTelemetry spans stored in TimelessTraces with automatic Phoenix + Bandit instrumentation
- **Dashboard** -- All three as LiveDashboard pages with charts, search, and historical data

## Installation with Igniter (recommended)

If you have [Igniter](https://hex.pm/packages/igniter) installed:

```bash
mix igniter.install timeless_phoenix
```

This automatically:

1. Adds `{TimelessPhoenix, data_dir: "priv/observability"}` to your supervision tree
2. Configures OpenTelemetry to export spans to TimelessTraces
3. Adds `import TimelessPhoenix.Router` to your Phoenix router
4. Adds `timeless_phoenix_dashboard "/dashboard"` to your browser scope
5. Updates `.formatter.exs`

For development or when you don't need persistent logs/traces:

```bash
mix igniter.install timeless_phoenix --storage memory
```

Memory mode stores logs and traces in memory only (lost on restart). Metrics are always persisted to disk.

## Manual installation

Add the dependency to `mix.exs`:

```elixir
{:timeless_phoenix, path: "../timeless_phoenix"}
```

Add to your supervision tree (`lib/my_app/application.ex`):

```elixir
children = [
  # ... existing children ...
  {TimelessPhoenix, data_dir: "priv/observability"}
]
```

Add to your router (`lib/my_app_web/router.ex`):

```elixir
import TimelessPhoenix.Router

scope "/" do
  pipe_through :browser
  timeless_phoenix_dashboard "/dashboard"
end
```

If your router has a default LiveDashboard route (typically in a `dev_routes` block), remove it to avoid a `live_session` conflict.

## Verify it's working

Start your application:

```bash
mix phx.server
```

Open http://localhost:4000/dashboard and you'll see:

- **Home** -- Standard LiveDashboard with historical metrics charts
- **Timeless** -- Metrics TSDB dashboard with compression stats and backups
- **Logs** -- Searchable log viewer with level/time filtering
- **Traces** -- Trace/span viewer with service, kind, and status filtering

Metrics, logs, and traces start populating immediately. Metrics persist across restarts in `priv/observability/metrics/`, and if using disk storage, logs and traces persist in `logs/` and `spans/` respectively.

## Generate demo traffic

To populate the dashboards with interesting data:

```bash
mix timeless_phoenix.gen_demo
```

This creates a GenServer that simulates HTTP requests, database queries, background jobs, cache operations, warnings, and errors every 2 seconds. See the [Demo Traffic](demo_traffic.md) guide for details.

## Interactive demo

For a hands-on walkthrough without a Phoenix app, open the [demo livebook](../livebook/demo.livemd)
in Livebook. It starts all three engines, generates data, renders inline SVG charts, and shows
compression stats interactively.

## Next steps

- [Configuration Reference](configuration.md) -- all options with defaults
- [Architecture](architecture.md) -- how the three engines are orchestrated
- [Dashboard](dashboard.md) -- LiveDashboard pages and customization
- [Metrics](metrics.md) -- default metrics and adding your own
- [Production Deployment](production.md) -- auth, data directories, proxies
- [Demo Traffic](demo_traffic.md) -- the demo traffic generator
