defmodule TimelessPhoenix.LoggerPropagator do
  @moduledoc """
  Propagates OpenTelemetry trace context into Elixir Logger metadata.

  Attaches a Telemetry handler to Phoenix lifecycle events that reads
  the current OTel span context and sets `trace_id` and `span_id` as
  Logger metadata. This means any `Logger.info/warning/error` call
  during a Phoenix request will automatically include these fields,
  enabling cross-signal linking between logs and traces.
  """

  require Logger

  @handler_id "timeless-phoenix-logger-propagator"

  def attach do
    events = [
      [:phoenix, :endpoint, :start],
      [:phoenix, :live_view, :mount, :start],
      [:phoenix, :live_view, :handle_params, :start],
      [:phoenix, :live_view, :handle_event, :start]
    ]

    :telemetry.attach_many(@handler_id, events, &__MODULE__.handle_event/4, nil)
  end

  def handle_event(_event, _measurements, _metadata, _config) do
    case OpenTelemetry.Tracer.current_span_ctx() do
      :undefined ->
        :ok

      span_ctx when is_tuple(span_ctx) ->
        trace_id = OpenTelemetry.Span.hex_trace_id(span_ctx)
        span_id = OpenTelemetry.Span.hex_span_id(span_ctx)

        if is_binary(trace_id) and trace_id != "" do
          Logger.metadata(trace_id: trace_id, span_id: span_id)
        end

      _ ->
        :ok
    end
  end
end
