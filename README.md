<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo-dark.svg">
    <source media="(prefers-color-scheme: light)" srcset="docs/logo-light.svg">
    <img src="docs/logo-light.svg" width="300" alt="Timeless">
  </picture>
</p>

<h3 align="center">Unified Observability for Phoenix</h3>

<p align="center">
  <a href="https://hex.pm/packages/timeless_phoenix"><img src="https://img.shields.io/hexpm/v/timeless_phoenix.svg" alt="Hex.pm"></a>
  <a href="https://hexdocs.pm/timeless_phoenix"><img src="https://img.shields.io/badge/docs-hexdocs-blue.svg" alt="Docs"></a>
  <a href="LICENSE"><img src="https://img.shields.io/hexpm/l/timeless_phoenix.svg" alt="License"></a>
</p>

---

> "I found it ironic that the first thing you do to time series data is squash the timestamp. That's how the name Timeless was born." --Mark Cotner

Unified observability for Phoenix: persistent metrics, logs, and traces in LiveDashboard.

One dep, one child_spec, one router macro — you get:

- **Metrics** — TimelessMetrics stores telemetry metrics that survive restarts
- **Logs** — TimelessLogs captures and indexes Elixir Logger output
- **Traces** — TimelessTraces stores OpenTelemetry spans
- **Dashboard** — All three as LiveDashboard pages, plus built-in charts with history

## Documentation

- [Getting Started](docs/getting_started.md)
- [Configuration Reference](docs/configuration.md)
- [Architecture](docs/architecture.md)
- [Dashboard](docs/dashboard.md)
- [Metrics](docs/metrics.md)
- [Demo Traffic Generator](docs/demo_traffic.md)
- [Production Deployment](docs/production.md)
- [Interactive Demo Livebook](livebook/demo.livemd)

## Installation

### With Igniter (recommended)

Add the dependency to `mix.exs`:

```elixir
{:timeless_phoenix, "~> 1.5"},
{:igniter, "~> 0.6", only: [:dev, :test], runtime: false}
```

Then run:

```bash
mix deps.get
mix igniter.install timeless_phoenix
```

This automatically:

1. Adds `{TimelessPhoenix, ...}` to your supervision tree
2. Configures OpenTelemetry to export spans to TimelessTraces
3. Adds `import TimelessPhoenix.Router` to your Phoenix router
4. Adds `timeless_phoenix_dashboard "/dashboard"` to your browser scope
5. Removes the default `live_dashboard` route (avoids live_session conflict)
6. Updates `.formatter.exs`

By default, metrics, logs, and traces are all persisted to disk under
`priv/observability`. If you want logs and traces to stay in memory only for
CI or ephemeral demo environments:

```bash
mix igniter.install timeless_phoenix --storage memory
```

### HTTP Endpoints

To expose HTTP ingest/query endpoints for external tooling (Grafana, curl, etc.),
use the `--http` flag to enable all three:

```bash
mix igniter.install timeless_phoenix --http
```

Or enable them individually:

```bash
mix igniter.install timeless_phoenix --http-metrics --http-logs
```

Default ports are 8428 (metrics), 9428 (logs), and 10428 (traces). Override with:

```bash
mix igniter.install timeless_phoenix --http --metrics-port 9090 --logs-port 3100 --traces-port 4318
```

| Flag | Description |
|------|-------------|
| `--http` | Enable all HTTP endpoints |
| `--http-metrics` | Enable metrics HTTP endpoint |
| `--http-logs` | Enable logs HTTP endpoint |
| `--http-traces` | Enable traces HTTP endpoint |
| `--metrics-port` | Metrics port (default 8428) |
| `--logs-port` | Logs port (default 9428) |
| `--traces-port` | Traces port (default 10428) |

### Manual

Add the dependency to `mix.exs`:

```elixir
{:timeless_phoenix, "~> 1.5"}
```

Add to your application's supervision tree (`lib/my_app/application.ex`):

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

Configure OpenTelemetry to export spans (`config/config.exs`):

```elixir
config :opentelemetry, traces_exporter: {TimelessTraces.Exporter, []}
```

Remove the default `live_dashboard` route from your router — it's
typically inside an `if Application.compile_env(:my_app, :dev_routes)`
block. TimelessPhoenix provides its own dashboard at the same path, and
having both causes a live_session conflict.

Add `:timeless_phoenix` to your `.formatter.exs` import_deps:

```elixir
[import_deps: [:timeless_phoenix, ...]]
```

## Configuration

### Child spec options

| Option | Default | Description |
|--------|---------|-------------|
| `:data_dir` | **required** | Base directory; creates `metrics/`, `logs/`, `spans/` subdirs |
| `:name` | `:default` | Instance name for process naming |
| `:metrics` | `DefaultMetrics.all()` | `Telemetry.Metrics` list for the reporter |
| `:timeless` | `[]` | Extra opts forwarded to TimelessMetrics |
| `:timeless_logs` | `[]` | Application env overrides for TimelessLogs |
| `:timeless_traces` | `[]` | Application env overrides for TimelessTraces |
| `:reporter` | `[]` | Extra opts for Reporter (`:flush_interval`, `:prefix`) |

### Router macro options

```elixir
timeless_phoenix_dashboard "/dashboard",
  name: :default,                              # TimelessPhoenix instance name
  metrics: MyApp.Telemetry,                    # custom metrics module
  download_path: "/timeless/downloads",        # backup download path
  live_dashboard: [csp_nonce_assign_key: :csp] # extra LiveDashboard opts
```

### Manual LiveDashboard setup

If you need full control over the LiveDashboard configuration instead of
using the macro:

```elixir
import Phoenix.LiveDashboard.Router

forward "/timeless/downloads", TimelessMetricsDashboard.DownloadPlug,
  store: :tp_default_timeless

live_dashboard "/dashboard",
  metrics: MyApp.Telemetry,
  metrics_history: {TimelessPhoenix, :metrics_history, []},
  additional_pages: TimelessPhoenix.dashboard_pages()
```

## Running in Production

The Igniter installer places `timeless_phoenix_dashboard` in a top-level
browser scope so it's available in all environments. To restrict access in
production, add authentication.

### Authentication

#### Pipeline-based auth (recommended)

Create an admin pipeline with your existing auth plugs:

```elixir
pipeline :admin do
  plug :fetch_current_user
  plug :require_admin_user
end

scope "/" do
  pipe_through [:browser, :admin]
  timeless_phoenix_dashboard "/dashboard"
end
```

#### Basic HTTP auth

For a quick setup using environment variables:

```elixir
pipeline :dashboard_auth do
  plug :admin_basic_auth
end

scope "/" do
  pipe_through [:browser, :dashboard_auth]
  timeless_phoenix_dashboard "/dashboard"
end

# In your router or a plug module:
defp admin_basic_auth(conn, _opts) do
  username = System.fetch_env!("DASHBOARD_USER")
  password = System.fetch_env!("DASHBOARD_PASS")
  Plug.BasicAuth.basic_auth(conn, username: username, password: password)
end
```

#### LiveView on_mount hook

For LiveView-level auth, pass `on_mount` through to LiveDashboard:

```elixir
timeless_phoenix_dashboard "/dashboard",
  live_dashboard: [on_mount: [{MyAppWeb.AdminAuth, :ensure_admin, []}]]
```

### WebSocket proxies

If your app is behind nginx or a reverse proxy, ensure WebSocket upgrades
are allowed. LiveDashboard uses LiveView, which requires a WebSocket
connection.

Nginx example:

```nginx
location /dashboard {
    proxy_pass http://localhost:4000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

### Production data directory

In production, use a persistent path outside the release:

```elixir
{TimelessPhoenix, data_dir: "/var/lib/my_app/observability"}
```

Or configure at runtime:

```elixir
{TimelessPhoenix, data_dir: System.get_env("OBS_DATA_DIR", "/var/lib/my_app/observability")}
```

## Data Retention

TimelessPhoenix ships with sensible defaults for embedded use. All three
engines retain 7 days of data by default.

| Engine | Default Retention | Size Limit |
|--------|------------------|------------|
| Metrics (raw) | 7 days | none |
| Metrics (daily rollup) | 90 days | none |
| Logs | 7 days | none |
| Traces | 7 days | none |

### Customizing retention

Override via the `:timeless_logs` and `:timeless_traces` child spec options:

```elixir
{TimelessPhoenix,
  data_dir: "priv/observability",
  timeless_logs: [
    retention_max_age: 30 * 86_400,       # 30 days
    retention_max_size: 1_073_741_824,     # 1 GB cap (nil = unlimited)
    retention_check_interval: 120_000      # check every 2 minutes
  ],
  timeless_traces: [
    retention_max_age: 14 * 86_400,        # 14 days
    retention_max_size: 512 * 1_048_576    # 512 MB cap
  ]}
```

For metrics, use the `:timeless` key:

```elixir
{TimelessPhoenix,
  data_dir: "priv/observability",
  timeless: [
    raw_retention_seconds: 14 * 86_400,    # 14 days raw
    daily_retention_seconds: 180 * 86_400  # 180 days rolled up
  ]}
```

Setting `retention_max_age` to `nil` disables time-based retention.
Setting `retention_max_size` to `nil` disables size-based retention (default).

## Custom Metrics

The default metrics include VM, Phoenix, LiveView, TimelessMetrics,
TimelessLogs, and TimelessTraces telemetry. To add your own:

```elixir
defmodule MyApp.Telemetry do
  import Telemetry.Metrics

  def metrics do
    TimelessPhoenix.DefaultMetrics.all() ++ [
      counter("my_app.orders.created"),
      summary("my_app.checkout.duration", unit: {:native, :millisecond}),
      last_value("my_app.queue.depth")
    ]
  end
end
```

Then pass it to both the child spec and router:

```elixir
# application.ex
{TimelessPhoenix, data_dir: "priv/observability", metrics: MyApp.Telemetry.metrics()}

# router.ex
timeless_phoenix_dashboard "/dashboard", metrics: MyApp.Telemetry
```
