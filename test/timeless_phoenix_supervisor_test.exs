defmodule TimelessPhoenix.SupervisorTest do
  use ExUnit.Case, async: false

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
        Enum.each(values, fn
          {key, {:ok, value}} -> Application.put_env(app, key, value)
          {key, :error} -> Application.delete_env(app, key)
        end)
      end)
    end)

    :ok
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "tp_sup_test_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp child_ids({:ok, {_flags, children}}) do
    Enum.map(children, fn
      %{id: {TimelessPhoenix.ApplicationMonitor, app}} ->
        {TimelessPhoenix.ApplicationMonitor, app}

      %{id: {mod, _name}} when is_atom(mod) ->
        mod

      %{id: id} ->
        id

      {mod, _opts} ->
        mod

      mod when is_atom(mod) ->
        mod
    end)
  end

  test ":http raises with Rust-services guidance" do
    assert_raise ArgumentError, ~r/timeless-metrics-api|Rust/, fn ->
      TimelessPhoenix.Supervisor.init(
        name: :http_test,
        data_dir: tmp_dir(),
        http: [metrics: 8428]
      )
    end
  end

  test "an external-owner signal is neither configured nor started" do
    previous_data_dir = Application.get_env(:timeless_logs, :data_dir)
    Application.put_env(:timeless_logs, :owner, :external)

    dir = tmp_dir()
    result = TimelessPhoenix.Supervisor.init(name: :ext_test, data_dir: dir)
    ids = child_ids(result)

    # No embedded logs app child, and the host's env is NOT clobbered.
    refute {TimelessPhoenix.ApplicationMonitor, :timeless_logs} in ids
    assert Application.get_env(:timeless_logs, :data_dir) == previous_data_dir
    refute File.dir?(Path.join(dir, "logs"))

    # The other signals still start embedded.
    assert TimelessMetrics in ids
    assert {TimelessPhoenix.ApplicationMonitor, :timeless_traces} in ids
  end

  test "embedded signals get the libSQL engine and the shared extension configured" do
    dir = tmp_dir()
    result = TimelessPhoenix.Supervisor.init(name: :engine_test, data_dir: dir)

    assert {TimelessPhoenix.ApplicationMonitor, :timeless_logs} in child_ids(result)
    assert Application.get_env(:timeless_logs, :engine) == :libsql
    assert Application.get_env(:timeless_logs, :extension_path) =~ "timeless_sqlite_ext.so"
    assert Application.get_env(:timeless_logs, :data_dir) == Path.join(dir, "logs")
  end

  test "metrics owner in application env disables the embedded metrics store and reporter" do
    Application.put_env(:timeless_metrics, :owner, :external)

    ids =
      TimelessPhoenix.Supervisor.init(name: :metrics_external, data_dir: tmp_dir())
      |> child_ids()

    refute TimelessMetrics in ids
    refute TimelessMetricsDashboard.Reporter in ids
  end

  test "reporter options override generated defaults" do
    {:ok, {_flags, children}} =
      TimelessPhoenix.Supervisor.init(
        name: :reporter_override,
        data_dir: tmp_dir(),
        reporter: [name: :custom_reporter]
      )

    assert %{start: {TimelessMetricsDashboard.Reporter, :start_link, [opts]}} =
             Enum.find(children, &match?(%{id: {TimelessMetricsDashboard.Reporter, _}}, &1))

    assert opts[:name] == :custom_reporter
  end

  test "an existing OpenTelemetry exporter is preserved" do
    existing = {ExampleExporter, [endpoint: "https://example.invalid"]}
    Application.put_env(:opentelemetry, :traces_exporter, existing)

    TimelessPhoenix.Supervisor.init(name: :exporter_test, data_dir: tmp_dir())

    assert Application.get_env(:opentelemetry, :traces_exporter) == existing
  end

  test "string instance names are rejected before creating atoms" do
    assert_raise ArgumentError, ~r/:name must be an atom/, fn ->
      TimelessPhoenix.Supervisor.start_link(name: "unsafe", data_dir: tmp_dir())
    end
  end

  test "only one supervisor can own embedded singleton signals" do
    test_process = self()

    owner =
      spawn(fn ->
        :ets.new(TimelessPhoenix.EmbeddedOwner, [:named_table, :set, :protected])

        send(test_process, :owner_ready)
        receive do: (:stop -> :ok)
      end)

    assert_receive :owner_ready
    on_exit(fn -> send(owner, :stop) end)

    caller = self()
    second_dir = tmp_dir()

    spawn(fn ->
      Process.flag(:trap_exit, true)

      result =
        TimelessPhoenix.Supervisor.start_link(
          name: :second_embedded,
          data_dir: second_dir
        )

      send(caller, {:second_owner_result, result})
    end)

    assert_receive {:second_owner_result, {:error, {%ArgumentError{message: message}, _stack}}}

    assert message =~ "only one TimelessPhoenix instance"
  end

  test "application monitor children are permanent" do
    spec =
      TimelessPhoenix.ApplicationMonitor.child_spec(
        app: :timeless_logs,
        supervisor: TimelessLogs.Supervisor
      )

    assert spec.restart == :permanent
    assert spec.id == {TimelessPhoenix.ApplicationMonitor, :timeless_logs}
  end
end
