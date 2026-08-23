defmodule TimelessPhoenix.DoctorTest do
  # Boots the real TimelessPhoenix tree and verifies the doctor's
  # verdict on a healthy fresh install — the same call an operator runs
  # on a live node after upgrading.
  use ExUnit.Case, async: false

  test "doctor reports :ok on a healthy fresh libSQL boot" do
    dir = Path.join(System.tmp_dir!(), "tp_doctor_test_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)

    for app <- [
          :exqlite,
          :telemetry,
          :opentelemetry,
          :opentelemetry_phoenix,
          :opentelemetry_bandit
        ] do
      Application.ensure_all_started(app)
    end

    sup =
      start_supervised!(%{
        id: :doctor_tree,
        start:
          {Supervisor, :start_link,
           [[{TimelessPhoenix, data_dir: dir, name: :doctor}], [strategy: :one_for_one]]},
        type: :supervisor
      })

    store = TimelessPhoenix.store_name(:doctor)
    :ok = TimelessMetrics.write(store, "doc", %{"h" => "x"}, 1.0, timestamp: 1000)
    :ok = TimelessMetrics.flush(store)

    {verdict, report} = TimelessPhoenix.doctor(:doctor)

    assert verdict == :ok
    assert report.metrics.verdict == :ok
    assert report.logs.verdict == :ok
    assert report.traces.verdict == :ok

    # Version-agnostic: the bundled extension advances with the engine deps;
    # what matters is that the doctor reports one and its data ABI.
    assert Enum.any?(report.metrics.checks, fn {_, msg} ->
             msg =~ ~r/extension \d+\.\d+\.\d+, data ABI \d+/
           end)

    assert Enum.any?(report.metrics.checks, fn {_, msg} -> msg =~ "no legacy" end)

    Supervisor.stop(sup)
  end
end
