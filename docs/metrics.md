# Metrics

TimelessPhoenix includes a default set of telemetry metrics that cover the VM, Phoenix, LiveView, and all three Timeless engines. You can use these as-is or extend them with your own application metrics.

## Default metrics

`TimelessPhoenix.DefaultMetrics.all()` combines all built-in metric groups:

### VM metrics

Standard Erlang VM telemetry:
- Memory usage (total, processes, binary, ETS, atom, code)
- Process counts
- Run queue lengths

### Phoenix metrics

HTTP request telemetry from `phoenix.endpoint.stop`:
- Request duration
- Request count by status code

### LiveView metrics

LiveView lifecycle telemetry:
- Mount duration
- Handle event duration

### TimelessMetrics metrics

Internal TSDB telemetry:
- Compression stats
- Write throughput

### TimelessLogs metrics

Log engine telemetry:
- `timeless_logs.flush.stop.entry_count` (summary + counter) -- entries per flush
- `timeless_logs.flush.stop.duration` (summary, ms) -- flush duration
- `timeless_logs.retention.stop.duration` (summary, ms) -- retention cleanup duration

### TimelessTraces metrics

Trace engine telemetry:
- `timeless_traces.flush.stop.entry_count` (summary + counter) -- spans per flush
- `timeless_traces.flush.stop.duration` (summary, ms) -- flush duration
- `timeless_traces.retention.stop.duration` (summary, ms) -- retention cleanup duration

## Using individual groups

Pick only the metric groups you need:

```elixir
metrics =
  TimelessPhoenix.DefaultMetrics.vm_metrics() ++
  TimelessPhoenix.DefaultMetrics.phoenix_metrics() ++
  TimelessPhoenix.DefaultMetrics.log_stream_metrics()
```

Available groups:
- `vm_metrics/0`
- `phoenix_metrics/0`
- `live_view_metrics/0`
- `ecto_metrics/1` (takes a repo event prefix, e.g. `[:my_app, :repo]`)
- `timeless_metrics/0`
- `log_stream_metrics/0`
- `span_stream_metrics/0`

## Adding custom metrics

Create a metrics module that combines the defaults with your own:

```elixir
defmodule MyApp.Telemetry do
  import Telemetry.Metrics

  def metrics do
    TimelessPhoenix.DefaultMetrics.all() ++ [
      # Application-specific metrics
      counter("my_app.orders.created"),
      summary("my_app.checkout.duration", unit: {:native, :millisecond}),
      last_value("my_app.queue.depth"),
      summary("my_app.api.response_time",
        unit: {:native, :millisecond},
        tags: [:endpoint])
    ]
  end
end
```

Pass the metrics to both the child spec and the router:

```elixir
# application.ex — reporter uses these to know what to collect
{TimelessPhoenix,
  data_dir: "priv/observability",
  metrics: MyApp.Telemetry.metrics()}

# router.ex — LiveDashboard uses these for chart definitions
timeless_phoenix_dashboard "/dashboard", metrics: MyApp.Telemetry
```

The child spec `:metrics` option takes a **list** of `Telemetry.Metrics` structs (the result of calling `metrics()`). The router `:metrics` option takes a **module** that exports `metrics/0`.

## Adding Ecto metrics

Ecto metrics require your repo's telemetry event prefix:

```elixir
defmodule MyApp.Telemetry do
  import Telemetry.Metrics

  def metrics do
    TimelessPhoenix.DefaultMetrics.all() ++
    TimelessPhoenix.DefaultMetrics.ecto_metrics([:my_app, :repo]) ++
    my_custom_metrics()
  end

  defp my_custom_metrics do
    [
      # ...
    ]
  end
end
```

## Emitting custom telemetry

Use `:telemetry.execute/3` in your application code:

```elixir
# Emit a counter event
:telemetry.execute([:my_app, :orders, :created], %{count: 1}, %{})

# Emit a duration measurement
start = System.monotonic_time()
# ... do work ...
duration = System.monotonic_time() - start
:telemetry.execute([:my_app, :checkout], %{duration: duration}, %{})
```

The reporter automatically captures these if a matching `Telemetry.Metrics` definition exists.

## Reporter

The `TimelessMetricsDashboard.Reporter` is a GenServer that:

1. Attaches telemetry handlers for all configured metrics
2. Aggregates measurements over a flush interval
3. Writes aggregated values to the named TimelessMetrics store

Reporter options can be passed via the `:reporter` key:

```elixir
{TimelessPhoenix,
  data_dir: "priv/observability",
  reporter: [flush_interval: 15_000]}
```
