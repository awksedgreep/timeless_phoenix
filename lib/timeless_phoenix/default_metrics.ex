defmodule TimelessPhoenix.DefaultMetrics do
  @moduledoc """
  Aggregated `Telemetry.Metrics` from all observability engines.

  Used as the default metrics module for both the Reporter and LiveDashboard.
  Re-exports from `TimelessMetricsDashboard.DefaultMetrics` and adds log/span metrics.

  ## Usage

      # All metrics (default when no :metrics option given to TimelessPhoenix)
      TimelessPhoenix.DefaultMetrics.all()

      # Or pick what you need:
      TimelessPhoenix.DefaultMetrics.vm_metrics() ++
      TimelessPhoenix.DefaultMetrics.phoenix_metrics() ++
      TimelessPhoenix.DefaultMetrics.log_stream_metrics()
  """

  import Telemetry.Metrics

  # Bump when the built-in list changes so hot upgrades cannot retain an old list.
  @cache_version 1

  # Re-export TimelessMetricsDashboard.DefaultMetrics
  defdelegate vm_metrics, to: TimelessMetricsDashboard.DefaultMetrics
  defdelegate phoenix_metrics, to: TimelessMetricsDashboard.DefaultMetrics
  defdelegate ecto_metrics(repo_prefix), to: TimelessMetricsDashboard.DefaultMetrics
  defdelegate live_view_metrics, to: TimelessMetricsDashboard.DefaultMetrics
  defdelegate timeless_metrics, to: TimelessMetricsDashboard.DefaultMetrics

  @doc """
  TimelessLogs metrics: buffer flushes, retention cleanup.
  """
  def log_stream_metrics do
    [
      summary("timeless_logs.flush.stop.entry_count"),
      summary("timeless_logs.flush.stop.duration", unit: {:native, :millisecond}),
      summary("timeless_logs.retention.stop.duration", unit: {:native, :millisecond})
    ]
  end

  @doc """
  TimelessTraces metrics: buffer flushes, retention cleanup.
  """
  def span_stream_metrics do
    [
      summary("timeless_traces.flush.stop.entry_count"),
      summary("timeless_traces.flush.stop.duration", unit: {:native, :millisecond}),
      summary("timeless_traces.retention.stop.duration", unit: {:native, :millisecond})
    ]
  end

  @doc """
  All default metrics combined: VM, Phoenix, LiveView, Timeless, LogStream, SpanStream.

  This is the default when no `:metrics` option is passed to `TimelessPhoenix`.
  """
  def all do
    cache_key = {__MODULE__, :all, @cache_version}

    case :persistent_term.get(cache_key, nil) do
      nil ->
        metrics =
          vm_metrics() ++
            phoenix_metrics() ++
            live_view_metrics() ++
            timeless_metrics() ++
            log_stream_metrics() ++
            span_stream_metrics()

        :persistent_term.put(cache_key, metrics)
        metrics

      metrics ->
        metrics
    end
  end

  # LiveDashboard calls metrics/0 on the metrics module
  def metrics, do: all()
end
