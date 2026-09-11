defmodule TimelessPhoenix.MixTasksTest do
  use ExUnit.Case, async: false

  setup do
    previous = Application.fetch_env(:opentelemetry, :traces_exporter)
    on_exit(fn -> restore_env(:opentelemetry, :traces_exporter, previous) end)
    :ok
  end

  defp project_files(router \\ nil, config \\ "import Config\n") do
    files = %{
      "mix.exs" => """
      defmodule Demo.MixProject do
        use Mix.Project
        def project, do: [app: :demo, version: "0.1.0", elixir: "~> 1.18", deps: []]
        def application, do: [mod: {Demo.Application, []}]
      end
      """,
      "lib/demo/application.ex" => """
      defmodule Demo.Application do
        use Application

        def start(_type, _args) do
          children = [DemoWeb.Telemetry]
          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end
      """,
      "config/config.exs" => config,
      ".formatter.exs" => "[]\n"
    }

    if router, do: Map.put(files, "lib/demo_web/router.ex", router), else: files
  end

  defp run_task(task, argv, files) do
    Igniter.Test.test_project(app_name: :demo, files: files)
    |> Igniter.Mix.Task.configure_and_run(task, argv)
  end

  defp content(igniter, path) do
    igniter.rewrite.sources[path]
    |> Rewrite.Source.get(:content)
  end

  test "installer preserves custom dashboards and an existing traces exporter" do
    router = """
    defmodule DemoWeb.Router do
      use Phoenix.Router
      import Phoenix.LiveDashboard.Router

      scope "/" do
        pipe_through :browser
        live_dashboard "/dashboard"
        live_dashboard "/ops"
      end
    end
    """

    config = """
    import Config
    config :opentelemetry, traces_exporter: {CustomExporter, endpoint: "https://example.invalid"}
    """

    igniter =
      run_task(Mix.Tasks.TimelessPhoenix.Install, [], project_files(router, config))

    router_content = content(igniter, "lib/demo_web/router.ex")
    config_content = content(igniter, "config/config.exs")

    assert router_content =~ ~s|live_dashboard("/ops")|
    assert router_content =~ "import Phoenix.LiveDashboard.Router"
    assert router_content =~ ~s|timeless_phoenix_dashboard("/dashboard")|
    refute router_content =~ ~s|live_dashboard("/dashboard")|
    assert config_content =~ "CustomExporter"
    refute config_content =~ "TimelessTraces.Exporter"
  end

  test "installer memory mode selects engines that honor storage: :memory" do
    igniter =
      run_task(
        Mix.Tasks.TimelessPhoenix.Install,
        ["--storage", "memory"],
        project_files()
      )

    application = content(igniter, "lib/demo/application.ex")

    assert application =~ "timeless_logs: [engine: :elixir, storage: :memory]"
    assert application =~ "timeless_traces: [engine: :elixir, storage: :memory]"
    refute application =~ "http:"
  end

  test "installer no longer accepts removed embedded HTTP options" do
    schema = Mix.Tasks.TimelessPhoenix.Install.info([], nil).schema

    for option <- [
          :http,
          :http_metrics,
          :http_logs,
          :http_traces,
          :metrics_port,
          :logs_port,
          :traces_port
        ] do
      refute Keyword.has_key?(schema, option)
    end
  end

  test "demo generator puts Task.Supervisor before DemoTraffic" do
    igniter =
      run_task(
        Mix.Tasks.TimelessPhoenix.GenDemo,
        ["--interval", "10"],
        project_files()
      )

    application = content(igniter, "lib/demo/application.ex")
    task_position = :binary.match(application, "{Task.Supervisor") |> elem(0)
    demo_position = :binary.match(application, "Demo.DemoTraffic") |> elem(0)

    assert task_position < demo_position
    assert content(igniter, "lib/demo/demo_traffic.ex") =~ "Enum.random(3..length(tasks))"
  end

  test "demo generator rejects non-positive intervals" do
    igniter =
      run_task(
        Mix.Tasks.TimelessPhoenix.GenDemo,
        ["--interval", "0"],
        project_files()
      )

    assert Enum.any?(igniter.issues, &(&1 =~ "--interval must be greater than zero"))
  end

  defp restore_env(app, key, {:ok, value}), do: Application.put_env(app, key, value)
  defp restore_env(app, key, :error), do: Application.delete_env(app, key)
end
