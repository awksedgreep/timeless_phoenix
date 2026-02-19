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
      counter("timeless_logs.flush.stop.entry_count"),
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
      counter("timeless_traces.flush.stop.entry_count"),
      summary("timeless_traces.retention.stop.duration", unit: {:native, :millisecond})
    ]
  end

  @doc """
  All default metrics combined: VM, Phoenix, LiveView, Timeless, LogStream, SpanStream.

  This is the default when no `:metrics` option is passed to `TimelessPhoenix`.
  """
  def all do
    vm_metrics() ++
      phoenix_metrics() ++
      live_view_metrics() ++
      timeless_metrics() ++
      log_stream_metrics() ++
      span_stream_metrics()
  end

  # LiveDashboard calls metrics/0 on the metrics module
  def metrics, do: all()
end
