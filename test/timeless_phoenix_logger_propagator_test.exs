defmodule TimelessPhoenix.LoggerPropagatorTest do
  use ExUnit.Case, async: false

  alias TimelessPhoenix.LoggerPropagator

  setup do
    on_exit(fn -> :telemetry.detach("timeless-phoenix-logger-propagator") end)
    :ok
  end

  test "attach is idempotent and subscribes to finish events" do
    assert :ok = LoggerPropagator.attach()
    assert :ok = LoggerPropagator.attach()

    handlers = :telemetry.list_handlers([:phoenix, :live_view, :handle_event, :stop])

    assert Enum.count(handlers, &(&1.id == "timeless-phoenix-logger-propagator")) == 1
  end

  test "stop and exception events clear stale trace metadata" do
    for finish <- [:stop, :exception] do
      Logger.metadata(trace_id: "old-trace", span_id: "old-span")

      assert :ok =
               LoggerPropagator.handle_event(
                 [:phoenix, :live_view, :handle_event, finish],
                 %{},
                 %{},
                 %{}
               )

      refute Keyword.has_key?(Logger.metadata(), :trace_id)
      refute Keyword.has_key?(Logger.metadata(), :span_id)
    end
  end
end
