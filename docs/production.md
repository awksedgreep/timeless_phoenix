# Production Deployment

This guide covers running TimelessPhoenix in production: authentication, data directories, proxies, retention, and backup.

## Moving out of dev-only

By default, Phoenix generators place `live_dashboard` inside a `if Mix.env() == :dev` block. For production, move the dashboard route out of that guard and add authentication.

## Authentication

### Pipeline-based auth (recommended)

Use your existing auth system:

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

### Basic HTTP auth

Quick setup using environment variables:

```elixir
pipeline :dashboard_auth do
  plug :admin_basic_auth
end

scope "/" do
  pipe_through [:browser, :dashboard_auth]
  timeless_phoenix_dashboard "/dashboard"
end

defp admin_basic_auth(conn, _opts) do
  username = System.fetch_env!("DASHBOARD_USER")
  password = System.fetch_env!("DASHBOARD_PASS")
  Plug.BasicAuth.basic_auth(conn, username: username, password: password)
end
```

### LiveView on_mount hook

For LiveView-level auth, pass `on_mount` through to LiveDashboard:

```elixir
timeless_phoenix_dashboard "/dashboard",
  live_dashboard: [on_mount: [{MyAppWeb.AdminAuth, :ensure_admin, []}]]
```

## Data directory

### Development

The default `priv/observability` works for development:

```elixir
{TimelessPhoenix, data_dir: "priv/observability"}
```

### Production

Use a persistent path outside the release directory:

```elixir
{TimelessPhoenix, data_dir: "/var/lib/my_app/observability"}
```

Or configure at runtime:

```elixir
{TimelessPhoenix,
  data_dir: System.get_env("OBS_DATA_DIR", "/var/lib/my_app/observability")}
```

### Docker / containers

Mount a volume for the data directory:

```dockerfile
VOLUME /var/lib/my_app/observability
```

```bash
docker run -v obs_data:/var/lib/my_app/observability my_app
```

### Directory structure

TimelessPhoenix creates subdirectories automatically:

```
/var/lib/my_app/observability/
├── metrics/    # TimelessMetrics TSDB (~0.67 bytes/point)
├── logs/       # TimelessLogs (~12.5x compression)
└── spans/      # TimelessTraces (~10x compression)
```

## Retention

Each engine has independent retention settings. Configure via the child spec:

```elixir
{TimelessPhoenix,
  data_dir: "/var/lib/my_app/observability",

  # Metrics retention
  timeless: [
    raw_retention_seconds: 7 * 86_400,      # Raw: 7 days
    daily_retention_seconds: 365 * 86_400    # Daily rollups: 1 year
  ],

  # Logs retention
  timeless_logs: [
    retention_max_age: 3 * 86_400,           # 3 days
    retention_max_size: 256 * 1_048_576      # 256 MB
  ],

  # Traces retention
  timeless_traces: [
    retention_max_age: 3 * 86_400,           # 3 days
    retention_max_size: 256 * 1_048_576      # 256 MB
  ]}
```

### Default retention

| Engine | Policy | Default |
|--------|--------|---------|
| TimelessMetrics | Raw age | 7 days |
| TimelessMetrics | Daily rollup age | 365 days |
| TimelessLogs | Age | 7 days |
| TimelessLogs | Size | 512 MB |
| TimelessTraces | Age | 7 days |
| TimelessTraces | Size | 512 MB |

## Backup

### Metrics backup

Via the download plug (mounted at `/timeless/downloads` by default) or programmatically:

```elixir
TimelessMetrics.backup(:tp_default_timeless, "/tmp/metrics_backup")
```

### Logs backup

```elixir
TimelessLogs.backup("/tmp/logs_backup")
```

### Traces backup

```elixir
TimelessTraces.backup("/tmp/spans_backup")
```

All backups use SQLite `VACUUM INTO` for atomic index snapshots and copy block files in parallel.

## WebSocket proxies

LiveDashboard uses LiveView, which requires WebSocket connections. If your app is behind a reverse proxy, ensure WebSocket upgrades are allowed.

### Nginx

```nginx
location /dashboard {
    proxy_pass http://localhost:4000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
}
```

### Caddy

```
reverse_proxy localhost:4000
```

Caddy handles WebSocket upgrades automatically.

## Disk space estimation

Rough estimates for a typical Phoenix application:

| Engine | Metric | Estimate |
|--------|--------|----------|
| Metrics | Per metric series | ~0.67 bytes/point |
| Metrics | 50 series, 1 point/15s, 7 days | ~13 MB |
| Logs | Per log entry | ~100 bytes compressed |
| Logs | 30 req/min, 7 days | ~30 MB |
| Traces | Per span | ~50 bytes compressed |
| Traces | 30 req/min, 3 spans/req, 7 days | ~45 MB |

Total for a moderate-traffic app with 7-day retention: **~90 MB**.

## Troubleshooting

### Dashboard not loading

- Verify the route is outside any `dev_routes` guard
- Check that the browser pipeline includes `:fetch_session`
- Ensure WebSocket connections work through your proxy

### No historical data in charts

- Verify `metrics_history` is configured (the macro does this automatically)
- Check that the `:name` option matches between child spec and router
- Ensure TimelessMetrics store is running: check for `:"tp_default_timeless"` process

### Logs not appearing

- TimelessLogs installs a Logger handler automatically when its application starts
- Verify the app started: `Application.ensure_all_started(:timeless_logs)`
- Check the data directory is writable

### Traces not appearing

- Verify OpenTelemetry config: `config :opentelemetry, traces_exporter: {TimelessTraces.Exporter, []}`
- This must be in compile-time config (`config.exs`), not runtime config
- Check that the OTel SDK is started: `Application.ensure_all_started(:opentelemetry)`
- Verify instrumentation is attached: `OpentelemetryPhoenix.setup(adapter: :bandit)` is called during supervisor init

### High disk usage

- Check retention settings for all three engines
- Trigger manual cleanup:
  ```elixir
  TimelessMetrics.enforce_retention(:tp_default_timeless)
  TimelessLogs.Retention.run_now()
  TimelessTraces.Retention.run_now()
  ```
- Check stats:
  ```elixir
  TimelessMetrics.info(:tp_default_timeless)
  TimelessLogs.stats()
  TimelessTraces.stats()
  ```
