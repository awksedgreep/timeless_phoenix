# TimelessPhoenix

Unified observability for Phoenix: persistent metrics, logs, and traces in LiveDashboard.

One dep, one child_spec, one router macro — you get:

- **Metrics** — Timeless TSDB stores telemetry metrics that survive restarts
- **Logs** — LogStream captures and indexes Elixir Logger output
- **Traces** — SpanStream stores OpenTelemetry spans
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

If you have [Igniter](https://hex.pm/packages/igniter) installed:

```bash
mix igniter.install timeless_phoenix
```

This automatically:

1. Adds `{TimelessPhoenix, data_dir: "priv/observability"}` to your supervision tree
2. Adds `import TimelessPhoenix.Router` to your Phoenix router
3. Adds `timeless_phoenix_dashboard "/dashboard"` to your browser scope
4. Updates `.formatter.exs`

For development or when you don't need persistent logs/traces, use memory
storage:

```bash
mix igniter.install timeless_phoenix --storage memory
```

This configures LogStream and SpanStream to store data in memory (lost on
restart). Metrics are always persisted to disk via Timeless.

### Manual

Add the dependency to `mix.exs`:

```elixir
{:timeless_phoenix, github: "awksedgreep/timeless_phoenix"}
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

## Configuration

### Child spec options

| Option | Default | Description |
|--------|---------|-------------|
| `:data_dir` | **required** | Base directory; creates `metrics/`, `logs/`, `spans/` subdirs |
| `:name` | `:default` | Instance name for process naming |
| `:metrics` | `DefaultMetrics.all()` | `Telemetry.Metrics` list for the reporter |
| `:timeless` | `[]` | Extra opts forwarded to Timeless |
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

By default, Phoenix generators place `live_dashboard` inside a
`if Mix.env() == :dev` block. To run in production, move it out of that
guard and add authentication.

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

## Custom Metrics

The default metrics include VM, Phoenix, LiveView, Timeless, LogStream,
and SpanStream telemetry. To add your own:

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

## Demo

```bash
mix run examples/demo.exs
```

Open http://localhost:4000/dashboard to see all pages.
