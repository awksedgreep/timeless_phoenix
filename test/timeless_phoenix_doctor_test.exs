defmodule TimelessPhoenix.DoctorTest do
  # Boots the real TimelessPhoenix tree and verifies the doctor's
  # verdict on a healthy fresh install — the same call an operator runs
  # on a live node after upgrading.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @env_keys %{
    timeless_logs: [
      :owner,
      :data_dir,
      :engine,
      :extension_path,
      :retention_max_age,
      :retention_max_size,
      :retention_check_interval,
      :max_term_index_entries
    ],
    timeless_traces: [
      :owner,
      :data_dir,
      :engine,
      :extension_path,
      :retention_max_age,
      :retention_max_size,
      :retention_check_interval,
      :max_term_index_entries
    ],
    timeless_metrics: [:owner],
    opentelemetry: [:resource, :traces_exporter]
  }

  setup do
    previous =
      Map.new(@env_keys, fn {app, keys} ->
        {app, Map.new(keys, fn key -> {key, Application.fetch_env(app, key)} end)}
      end)

    on_exit(fn ->
      Enum.each(previous, fn {app, values} ->
        Enum.each(values, fn {key, value} -> restore_env(app, key, value) end)
      end)
    end)

    :ok
  end

  test "singleton stats errors include their reason" do
    assert {:warn, message} =
             TimelessPhoenix.Doctor.singleton_data(fn -> {:error, :database_busy} end)

    assert message =~ "database_busy"
    refute message =~ "no match"
  end

  test "quiet mode suppresses report output for externally owned signals" do
    previous_logs = Application.fetch_env(:timeless_logs, :owner)
    previous_traces = Application.fetch_env(:timeless_traces, :owner)
    previous_metrics = Application.fetch_env(:timeless_metrics, :owner)

    Application.put_env(:timeless_logs, :owner, :external)
    Application.put_env(:timeless_traces, :owner, :external)
    Application.put_env(:timeless_metrics, :owner, :external)

    on_exit(fn ->
      restore_env(:timeless_logs, :owner, previous_logs)
      restore_env(:timeless_traces, :owner, previous_traces)
      restore_env(:timeless_metrics, :owner, previous_metrics)
    end)

    assert capture_io(fn ->
             {verdict, report} = TimelessPhoenix.doctor(:default, quiet: true)
             assert verdict == :warn
             assert report.metrics.verdict == :warn
             assert report.logs.verdict == :warn
             assert report.traces.verdict == :warn
           end) == ""
  end

  @tag capture_log: true
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

    logs_pid = Process.whereis(TimelessLogs.Supervisor)
    traces_pid = Process.whereis(TimelessTraces.Supervisor)

    reporter_pid =
      child_pid(:tp_doctor_sup, {TimelessMetricsDashboard.Reporter, :tp_doctor_reporter})

    metrics_pid = child_pid(:tp_doctor_sup, {TimelessMetrics, :tp_doctor_timeless})

    Process.exit(metrics_pid, :kill)

    assert eventually(fn ->
             replacement =
               child_pid(:tp_doctor_sup, {TimelessMetrics, :tp_doctor_timeless})

             is_pid(replacement) and replacement != metrics_pid
           end)

    assert Process.whereis(TimelessLogs.Supervisor) == logs_pid
    assert Process.whereis(TimelessTraces.Supervisor) == traces_pid

    assert child_pid(
             :tp_doctor_sup,
             {TimelessMetricsDashboard.Reporter, :tp_doctor_reporter}
           ) == reporter_pid

    Process.exit(logs_pid, :kill)

    assert eventually(fn ->
             replacement = Process.whereis(TimelessLogs.Supervisor)
             is_pid(replacement) and replacement != logs_pid
           end)

    assert Process.whereis(TimelessTraces.Supervisor) == traces_pid
  end

  defp child_pid(supervisor, id) do
    Enum.find_value(Supervisor.which_children(supervisor), fn
      {^id, pid, _type, _modules} -> pid
      _child -> nil
    end)
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(_fun, 0), do: false

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end

  defp restore_env(app, key, {:ok, value}), do: Application.put_env(app, key, value)
  defp restore_env(app, key, :error), do: Application.delete_env(app, key)
end
