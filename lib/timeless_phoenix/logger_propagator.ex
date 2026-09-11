defmodule TimelessPhoenix.LoggerPropagator do
  @moduledoc """
  Propagates OpenTelemetry trace context into Elixir Logger metadata.

  Attaches a Telemetry handler to Phoenix lifecycle events that reads
  the current OTel span context and sets `trace_id` and `span_id` as
  Logger metadata. This means any `Logger.info/warning/error` call
  during a Phoenix request will automatically include these fields,
  enabling cross-signal linking between logs and traces.
  """

  @handler_id "timeless-phoenix-logger-propagator"

  @start_events [
    [:phoenix, :endpoint, :start],
    [:phoenix, :live_view, :mount, :start],
    [:phoenix, :live_view, :handle_params, :start],
    [:phoenix, :live_view, :handle_event, :start]
  ]

  @finish_events for event <- @start_events,
                     finish <- [:stop, :exception],
                     do: List.replace_at(event, -1, finish)

  def attach do
    identity = TimelessPhoenix.Identity.resolve()
    :telemetry.detach(@handler_id)

    case :telemetry.attach_many(
           @handler_id,
           @start_events ++ @finish_events,
           &__MODULE__.handle_event/4,
           %{
             logger_metadata: TimelessPhoenix.Identity.logger_metadata(identity),
             span_attributes: TimelessPhoenix.Identity.span_attributes(identity)
           }
         ) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  def handle_event(event, _measurements, _metadata, config) do
    if List.last(event) in [:stop, :exception] do
      Logger.metadata(trace_id: nil, span_id: nil)
    else
      propagate(config)
    end
  end

  defp propagate(config) do
    case OpenTelemetry.Tracer.current_span_ctx() do
      :undefined ->
        :ok

      span_ctx when is_tuple(span_ctx) ->
        OpenTelemetry.Tracer.set_attributes(config.span_attributes)

        trace_id = OpenTelemetry.Span.hex_trace_id(span_ctx)
        span_id = OpenTelemetry.Span.hex_span_id(span_ctx)

        if is_binary(trace_id) and trace_id != "" do
          Logger.metadata([trace_id: trace_id, span_id: span_id] ++ config.logger_metadata)
        end

      _ ->
        :ok
    end
  end
end
