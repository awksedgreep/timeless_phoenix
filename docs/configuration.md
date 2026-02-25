# Configuration Reference

TimelessPhoenix is configured through two touch points: a child spec in your supervision tree and a router macro in your Phoenix router.

## Child spec options

Pass these options to `{TimelessPhoenix, opts}` in your supervision tree:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:data_dir` | string | **required** | Base directory; creates `metrics/`, `logs/`, `spans/` subdirectories |
| `:name` | atom | `:default` | Instance name for process naming |
| `:metrics` | list | `DefaultMetrics.all()` | `Telemetry.Metrics` list for the reporter |
| `:timeless` | keyword | `[]` | Extra opts forwarded to TimelessMetrics |
| `:timeless_logs` | keyword | `[]` | Application env overrides for TimelessLogs |
| `:timeless_traces` | keyword | `[]` | Application env overrides for TimelessTraces |
| `:reporter` | keyword | `[]` | Extra opts for the telemetry reporter |

## Router macro options

Pass these to `timeless_phoenix_dashboard "/path", opts`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:name` | atom | `:default` | Must match the child spec `:name` |
| `:metrics` | module | `TimelessPhoenix.DefaultMetrics` | Custom metrics module (must export `metrics/0`) |
| `:download_path` | string | `"/timeless/downloads"` | Path for the metrics backup download plug |
| `:live_dashboard` | keyword | `[]` | Extra options merged into the `live_dashboard` call |

## Full example

```elixir
# lib/my_app/application.ex
children = [
  {TimelessPhoenix,
    data_dir: "priv/observability",
    name: :default,
    metrics: MyApp.Telemetry.metrics(),
    timeless: [max_blocks: 200, block_size: 2000],
    timeless_logs: [retention_max_age: 3 * 86_400],
    timeless_traces: [retention_max_age: 3 * 86_400],
    reporter: [flush_interval: 15_000]}
]

# lib/my_app_web/router.ex
import TimelessPhoenix.Router

scope "/" do
  pipe_through [:browser, :admin]
  timeless_phoenix_dashboard "/dashboard",
    name: :default,
    metrics: MyApp.Telemetry,
    live_dashboard: [on_mount: [{MyAppWeb.AdminAuth, :ensure_admin, []}]]
end
```

## Subsystem overrides

### TimelessMetrics options

Forwarded via the `:timeless` key. Common options:

| Option | Default | Description |
|--------|---------|-------------|
| `:max_blocks` | `100` | Max compressed blocks per series |
| `:block_size` | `1000` | Points per block |
| `:flush_interval` | `60_000` | Reporter flush interval (ms) |
| `:compression` | `:zstd` | Block compression (`:zstd`) |
| `:raw_retention_seconds` | `604_800` (7 days) | Raw data retention |
| `:daily_retention_seconds` | `31_536_000` (365 days) | Daily rollup retention |

See [TimelessMetrics Configuration](https://github.com/awksedgreep/timeless_metrics/blob/main/docs/configuration.md) for the full reference.

### TimelessLogs options

Forwarded via the `:timeless_logs` key. Set as application env before the app starts:

| Option | Default | Description |
|--------|---------|-------------|
| `:storage` | `:disk` | `:disk` or `:memory` |
| `:flush_interval` | `1_000` | Buffer flush interval (ms) |
| `:max_buffer_size` | `1_000` | Max entries before forced flush |
| `:compaction_format` | `:openzl` | Compression format (`:openzl` or `:zstd`) |
| `:retention_max_age` | `604_800` (7 days) | Max log age in seconds |
| `:retention_max_size` | `536_870_912` (512 MB) | Max storage size |

See [TimelessLogs Configuration](https://github.com/awksedgreep/timeless_logs/blob/main/docs/configuration.md) for the full reference.

### TimelessTraces options

Forwarded via the `:timeless_traces` key. Set as application env before the app starts:

| Option | Default | Description |
|--------|---------|-------------|
| `:storage` | `:disk` | `:disk` or `:memory` |
| `:flush_interval` | `1_000` | Buffer flush interval (ms) |
| `:max_buffer_size` | `1_000` | Max spans before forced flush |
| `:compaction_format` | `:openzl` | Compression format (`:openzl` or `:zstd`) |
| `:retention_max_age` | `604_800` (7 days) | Max span age in seconds |
| `:retention_max_size` | `536_870_912` (512 MB) | Max storage size |

See [TimelessTraces Configuration](https://github.com/awksedgreep/timeless_traces/blob/main/docs/configuration.md) for the full reference.

### Reporter options

Forwarded via the `:reporter` key:

| Option | Default | Description |
|--------|---------|-------------|
| `:flush_interval` | inherited | Override the reporter's flush interval |
| `:prefix` | `nil` | Prefix for metric names |

## Named instances

Multiple TimelessPhoenix instances can run in the same application. Each gets isolated storage, processes, and dashboard pages:

```elixir
children = [
  {TimelessPhoenix, data_dir: "priv/obs_main", name: :main},
  {TimelessPhoenix, data_dir: "priv/obs_admin", name: :admin}
]
```

```elixir
scope "/main" do
  pipe_through :browser
  timeless_phoenix_dashboard "/dashboard", name: :main
end

scope "/admin" do
  pipe_through [:browser, :admin]
  timeless_phoenix_dashboard "/dashboard", name: :admin
end
```

Instance names generate process names:
- Store: `:"tp_{name}_timeless"` (e.g., `:"tp_main_timeless"`)
- Reporter: `:"tp_{name}_reporter"`
- Supervisor: `:"tp_{name}_sup"`

## Memory mode

For development or CI, store logs and traces in memory (metrics always persist to disk):

```elixir
{TimelessPhoenix,
  data_dir: "priv/observability",
  timeless_logs: [storage: :memory],
  timeless_traces: [storage: :memory]}
```

Or via the Igniter installer:

```bash
mix igniter.install timeless_phoenix --storage memory
```
