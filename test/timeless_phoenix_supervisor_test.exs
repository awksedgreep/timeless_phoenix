defmodule TimelessPhoenix.SupervisorTest do
  use ExUnit.Case, async: false

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "tp_sup_test_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp child_ids({:ok, {_flags, children}}) do
    Enum.map(children, fn
      %{id: {mod, _name}} when is_atom(mod) -> mod
      %{id: id} -> id
      {mod, _opts} -> mod
      mod when is_atom(mod) -> mod
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
    previous_owner = Application.get_env(:timeless_logs, :owner)
    previous_data_dir = Application.get_env(:timeless_logs, :data_dir)
    Application.put_env(:timeless_logs, :owner, :external)

    try do
      dir = tmp_dir()
      result = TimelessPhoenix.Supervisor.init(name: :ext_test, data_dir: dir)
      ids = child_ids(result)

      # No embedded logs app child, and the host's env is NOT clobbered.
      refute :timeless_logs_app in ids
      assert Application.get_env(:timeless_logs, :data_dir) == previous_data_dir
      refute File.dir?(Path.join(dir, "logs"))

      # The other signals still start embedded.
      assert TimelessMetrics in ids
      assert :timeless_traces_app in ids
    after
      case previous_owner do
        nil -> Application.delete_env(:timeless_logs, :owner)
        _ -> Application.put_env(:timeless_logs, :owner, previous_owner)
      end

      case previous_data_dir do
        nil -> Application.delete_env(:timeless_logs, :data_dir)
        _ -> Application.put_env(:timeless_logs, :data_dir, previous_data_dir)
      end
    end
  end

  test "embedded signals get the libSQL engine and the shared extension configured" do
    previous = {
      Application.get_env(:timeless_logs, :engine),
      Application.get_env(:timeless_logs, :extension_path),
      Application.get_env(:timeless_logs, :data_dir)
    }

    try do
      dir = tmp_dir()
      result = TimelessPhoenix.Supervisor.init(name: :engine_test, data_dir: dir)

      assert :timeless_logs_app in child_ids(result)
      assert Application.get_env(:timeless_logs, :engine) == :libsql
      assert Application.get_env(:timeless_logs, :extension_path) =~ "timeless_sqlite_ext.so"
      assert Application.get_env(:timeless_logs, :data_dir) == Path.join(dir, "logs")
    after
      {engine, ext, data_dir} = previous

      for {key, value} <- [engine: engine, extension_path: ext, data_dir: data_dir] do
        case value do
          nil -> Application.delete_env(:timeless_logs, key)
          _ -> Application.put_env(:timeless_logs, key, value)
        end
      end
    end
  end
end
