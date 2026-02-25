# Dashboard

TimelessPhoenix extends Phoenix LiveDashboard with three additional pages for metrics, logs, and traces. It also provides historical data for the built-in metrics charts.

## Dashboard pages

### Home (built-in)

The standard LiveDashboard home page, enhanced with `metrics_history` so charts show historical data instead of only real-time values. This means you see metric history from before you opened the page.

### Timeless (metrics)

The TimelessMetrics dashboard page. Shows:

- List of all stored metrics with current values
- Interactive time-series charts
- Compression statistics (ratio, block counts, storage size)
- Backup/download functionality via the download plug

### Logs

The TimelessLogs dashboard page. Provides:

- Searchable log viewer with real-time updates
- Filter by log level (debug, info, warning, error)
- Time range filtering
- Message substring search
- Metadata filtering

### Traces

The TimelessTraces dashboard page. Provides:

- Trace search with service, kind, and status filters
- Duration filtering (find slow spans)
- Full trace waterfall view
- Span detail inspection (attributes, events, resource)

## Router macro

The simplest setup uses the `timeless_phoenix_dashboard` macro:

```elixir
import TimelessPhoenix.Router

scope "/" do
  pipe_through :browser
  timeless_phoenix_dashboard "/dashboard"
end
```

This mounts:
1. A download plug at `/timeless/downloads` for metrics backups
2. LiveDashboard at `/dashboard` with all pages configured

### Customizing the macro

```elixir
timeless_phoenix_dashboard "/dashboard",
  name: :default,
  metrics: MyApp.Telemetry,
  download_path: "/obs/downloads",
  live_dashboard: [
    on_mount: [{MyAppWeb.AdminAuth, :ensure_admin, []}],
    csp_nonce_assign_key: :csp_nonce
  ]
```

## Manual LiveDashboard setup

If you need full control over the LiveDashboard configuration, skip the macro and configure it directly:

```elixir
import Phoenix.LiveDashboard.Router

# Mount the download plug
forward "/timeless/downloads", TimelessMetricsDashboard.DownloadPlug,
  store: :tp_default_timeless

# Mount LiveDashboard with all pages
live_dashboard "/dashboard",
  metrics: MyApp.Telemetry,
  metrics_history: {TimelessPhoenix, :metrics_history, []},
  additional_pages: TimelessPhoenix.dashboard_pages()
```

### With a named instance

```elixir
live_dashboard "/dashboard",
  metrics: MyApp.Telemetry,
  metrics_history: {TimelessPhoenix, :metrics_history, [:my_instance]},
  additional_pages: TimelessPhoenix.dashboard_pages(name: :my_instance)
```

## Metrics history

TimelessPhoenix provides a `metrics_history/3` callback that LiveDashboard uses to retrieve historical chart data. When you open the dashboard, charts immediately show past data instead of starting empty.

The callback delegates to `TimelessMetricsDashboard.metrics_history/3` using the named TimelessMetrics store for the instance.

## Adding dashboard pages selectively

`TimelessPhoenix.dashboard_pages/1` returns all three pages. If you only want some of them, build the `additional_pages` list manually:

```elixir
live_dashboard "/dashboard",
  metrics: MyApp.Telemetry,
  metrics_history: {TimelessPhoenix, :metrics_history, []},
  additional_pages: [
    timeless: {TimelessMetricsDashboard.Page,
      store: :tp_default_timeless,
      download_path: "/timeless/downloads"},
    logs: TimelessLogsDashboard.Page
    # traces page omitted
  ]
```
