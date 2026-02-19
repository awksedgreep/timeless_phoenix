# Podcast Demo: TimelessPhoenix — Zero to Observability

Step-by-step demo script showing a fresh Phoenix project going from zero to full observability (metrics, logs, traces) with a single Igniter install.

## Pre-requisites (before recording)

1. **Publish to Hex** (or use `github:` deps)
   - `timeless_metrics`, `timeless_logs`, `timeless_traces`
   - `timeless_metrics_dashboard`, `timeless_logs_dashboard`, `timeless_traces_dashboard`
   - `timeless_phoenix`

2. **Install latest Phoenix + Igniter globally**
   ```bash
   mix archive.install hex phx_new
   mix archive.install hex igniter_new
   ```

## Demo Script

### Act 1: Fresh Phoenix Project (~2 min)

```bash
mix phx.new demo_app --no-ecto
cd demo_app
mix deps.get
mix phx.server
```

- Open `http://localhost:4000` — vanilla Phoenix welcome page
- Open `http://localhost:4000/dev/dashboard` — stock LiveDashboard
- **Talking point:** "This is what you get out of the box. Metrics are ephemeral — refresh and they're gone. No logs, no traces."

### Act 2: One-Line Install (~1 min)

Stop the server, then:

```bash
mix igniter.install timeless_phoenix
```

What Igniter does automatically (show the diff or narrate):

- Adds `{:timeless_phoenix, "~> 0.x"}` to `mix.exs` deps
- Adds `{TimelessPhoenix, data_dir: "priv/observability"}` to your supervision tree in `application.ex`
- Configures OpenTelemetry to export spans to TimelessTraces in `config.exs`
- Adds `import TimelessPhoenix.Router` to your router
- Adds `timeless_phoenix_dashboard "/dashboard"` inside your browser scope
- Updates `.formatter.exs` with `import_deps: [:timeless_phoenix]`
- Prints a notice to remove the default `/dev/dashboard` route (avoids live_session conflict)

**Important:** Remove the default LiveDashboard route from the router (the `if Application.compile_env(:your_app, :dev_routes)` block) to avoid a live_session conflict.

**Talking point:** "One command. No config files. No YAML. No docker-compose."

### Act 3: Generate Demo Traffic (~1 min)

```bash
mix timeless_phoenix.gen_demo
```

What Igniter generates:

- `lib/<app>/demo_traffic.ex` — a GenServer that spawns 3-6 simulated activities every 2 seconds (HTTP requests, DB queries, background jobs, cache operations, plus periodic warnings and errors)
- Adds `{Task.Supervisor, name: <App>.DemoTaskSupervisor}` and `<App>.DemoTraffic` to the supervision tree

**Talking point:** "This gives us realistic background activity so the dashboards have something interesting to show. All log levels, telemetry events, simulated request patterns."

### Act 4: Start and Explore (~3 min)

```bash
mix phx.server
```

Open `http://localhost:4000/dashboard` — LiveDashboard now has three observability pages, and the demo traffic generator is already populating them:

1. **Metrics tab** — VM metrics (memory, run queues, process counts) already being captured and *persisted*. Refresh the page — history is still there.
   - **Talking point:** "These metrics survive page refreshes, restarts, even deploys. They're stored in a Gorilla+zstd compressed time series database at 0.67 bytes per point — an 11.5x compression ratio."

2. **Logs tab** — Demo traffic is generating logs at all four levels. Show the search.
   - All `Logger` calls are automatically captured, compressed, and indexed
   - Demo: search by level (`:error`, `:warning`), substring match ("timeout", "deadlock"), time range
   - **Talking point:** "Every Logger call in your app is automatically captured. No extra config. Search by level, message, metadata — all indexed in SQLite."

3. **Timeless tab** (metrics dashboard) — Persistent charts, compression stats, backup controls.
   - **Talking point:** "This is your metrics TSDB dashboard. Compression ratios, point counts, segment info — all at a glance."

### Act 5: Traces (optional, ~2 min)

For OTel span instrumentation, add the Phoenix/Cowboy libraries:

```elixir
# mix.exs — add these deps
{:opentelemetry_phoenix, "~> 2.0"},
{:opentelemetry_cowboy, "~> 1.0"}
```

```elixir
# application.ex — in start/2, before supervisor
OpentelemetryPhoenix.setup()
OpentelemetryCowboy.setup()
```

Restart, hit a few pages, then:

- **Traces tab:** Spans appearing with service name, duration, status
- Click a trace ID to see the full span tree
- Filter by `status=error`, `min_duration`, etc.
- **Talking point:** "Spans go straight from the OTel SDK to compressed storage. No collector, no Jaeger, no external infra."

### Act 6: The Punchline (~1 min)

Show the data directory:

```bash
ls -la priv/observability/
# metrics/  logs/  spans/
du -sh priv/observability/
```

**Talking points:**

- "All three pillars of observability in one dep"
- "Zero external infrastructure — no Prometheus, no Loki, no Jaeger, no Grafana needed"
- "11.5x compression on metrics, 11x on logs, 10x on traces"
- "SQLite + immutable segment files — back it up with a single function call"
- "Works with `mix phx.server` in dev, works in production containers"

## Bonus Demos (if time allows)

- **Memory-only mode:** `mix igniter.install timeless_phoenix --storage memory` for CI/test environments
- **Forecasting:** Hit `/chart?metric=vm.memory.total&from=-1h&forecast=30m` in the browser
- **Anomaly detection:** Add `&anomalies=medium` to the chart URL for red dot overlays
- **Backup:** Click the backup button in the dashboard or call `TimelessMetrics.backup(:tp_default_timeless, "/tmp/bak")`

## Pre-flight Checklist

- [ ] All packages published to Hex (or clean GitHub dep story ready)
- [ ] `mix igniter.install timeless_phoenix` works against a clean `phx.new` project
- [ ] Remove default LiveDashboard route after install (live_session conflict)
- [ ] `mix timeless_phoenix.gen_demo` generates DemoTraffic + Task.Supervisor correctly
- [ ] Traces tab populates with OTel Phoenix/Cowboy instrumentation (if using Act 5)
- [ ] Data directory creates cleanly under `priv/observability/`
