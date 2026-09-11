if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.TimelessPhoenix.Install do
    @shortdoc "Installs TimelessPhoenix into your application."
    @moduledoc """
    #{@shortdoc}

    Adds TimelessPhoenix to your supervision tree, configures your Phoenix router
    with all observability dashboard pages, and updates the formatter.

    ## Usage

        mix igniter.install timeless_phoenix
        mix igniter.install timeless_phoenix --storage memory

    ## Options

      * `--storage` — `disk` (default) or `memory`. Disk mode persists logs and
        traces with indexing and retention management. Memory mode keeps them
        in RAM using the legacy Elixir engines and loses them on restart.
        Metrics are always persisted to disk.

    ## What it does

    1. Adds `{TimelessPhoenix, ...}` to your application's supervision tree
       (logs, traces, and metrics persist to disk by default)
    2. Configures OpenTelemetry to export spans to TimelessTraces
    3. Adds `import TimelessPhoenix.Router` to your Phoenix router
    4. Adds `timeless_phoenix_dashboard "/dashboard"` to your router's browser scope
    5. Adds `:timeless_phoenix` to your `.formatter.exs` import_deps
    6. Removes the default `live_dashboard` route (avoids live_session conflict)
    """

    use Igniter.Mix.Task

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :timeless_phoenix,
        schema: [storage: :string],
        defaults: [storage: "disk"],
        required: [],
        positional: [],
        aliases: [],
        composes: [],
        installs: [],
        adds_deps: [],
        example: "mix igniter.install timeless_phoenix --storage memory"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      storage = igniter.args.options[:storage] || "disk"

      igniter
      |> add_to_supervision_tree(storage)
      |> configure_opentelemetry()
      |> setup_router()
      |> remove_default_live_dashboard()
      |> Igniter.Project.Formatter.import_dep(:timeless_phoenix)
    end

    # Adds {TimelessPhoenix, ...} to the application's children list.
    defp add_to_supervision_tree(igniter, storage) do
      opts_parts = [~s(data_dir: "priv/observability")]

      opts_parts =
        case storage do
          "memory" ->
            opts_parts ++
              [
                "timeless_logs: [engine: :elixir, storage: :memory]",
                "timeless_traces: [engine: :elixir, storage: :memory]"
              ]

          _ ->
            opts_parts
        end

      opts_string = "[" <> Enum.join(opts_parts, ", ") <> "]"
      child_code = Sourceror.parse_string!(opts_string)

      Igniter.Project.Application.add_new_child(
        igniter,
        {TimelessPhoenix, {:code, child_code}}
      )
    end

    # Adds the import and macro call to the Phoenix router.
    defp setup_router(igniter) do
      case Igniter.Libs.Phoenix.select_router(igniter) do
        {igniter, nil} ->
          Igniter.add_warning(igniter, """
          No Phoenix router found. Add the following manually:

              import TimelessPhoenix.Router

              scope "/" do
                pipe_through :browser
                timeless_phoenix_dashboard "/dashboard"
              end
          """)

        {igniter, router} ->
          igniter
          |> add_router_import(router)
          |> Igniter.Libs.Phoenix.append_to_scope(
            "/",
            """
            timeless_phoenix_dashboard "/dashboard"
            """,
            with_pipelines: [:browser],
            router: router
          )
      end
    end

    # Configures OpenTelemetry to export spans to TimelessTraces.
    # This must be in compile-time config so it takes effect before the OTel app starts.
    defp configure_opentelemetry(igniter) do
      Igniter.Project.Config.configure_new(
        igniter,
        "config.exs",
        :opentelemetry,
        [:traces_exporter],
        {:code, Sourceror.parse_string!("{TimelessTraces.Exporter, []}")}
      )
    end

    # Removes the default Phoenix LiveDashboard route to avoid live_session conflicts.
    # The default Phoenix generator puts `live_dashboard "/dashboard"` inside
    # `if Application.compile_env(:app, :dev_routes) do ... end` — we remove
    # the `live_dashboard` call since TimelessPhoenix provides its own dashboard.
    defp remove_default_live_dashboard(igniter) do
      case Igniter.Libs.Phoenix.select_router(igniter) do
        {igniter, nil} ->
          igniter

        {igniter, router} ->
          Igniter.Project.Module.find_and_update_module!(igniter, router, fn zipper ->
            # Remove only Phoenix's generated default route. Applications may
            # intentionally mount other dashboards at other paths.
            zipper =
              Igniter.Code.Common.remove_all_matches(zipper, fn z ->
                default_live_dashboard_call?(z)
              end)

            zipper =
              if Igniter.Code.Common.find_all(zipper, &live_dashboard_call?/1) == [] do
                Igniter.Code.Common.remove_all_matches(zipper, &live_dashboard_import?/1)
              else
                zipper
              end

            {:ok, zipper}
          end)
      end
    end

    defp default_live_dashboard_call?(zipper) do
      live_dashboard_call?(zipper) &&
        case Igniter.Code.Function.move_to_nth_argument(zipper, 0) do
          {:ok, argument} -> Igniter.Code.Common.nodes_equal?(argument, "/dashboard")
          :error -> false
        end
    end

    defp live_dashboard_call?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :live_dashboard, :any)
    end

    defp live_dashboard_import?(zipper) do
      Igniter.Code.Function.function_call?(zipper, :import, 1) &&
        match?(
          {:ok,
           %Sourceror.Zipper{
             node: {:__aliases__, _, [:Phoenix, :LiveDashboard, :Router]}
           }},
          Igniter.Code.Function.move_to_nth_argument(zipper, 0)
        )
    end

    # Adds `import TimelessPhoenix.Router` after `use Phoenix.Router` in the router module.
    defp add_router_import(igniter, router) do
      Igniter.Project.Module.find_and_update_module!(igniter, router, fn zipper ->
        case Igniter.Libs.Phoenix.move_to_router_use(igniter, zipper) do
          {:ok, zipper} ->
            {:ok, Igniter.Code.Common.add_code(zipper, "import TimelessPhoenix.Router")}

          _ ->
            {:ok, zipper}
        end
      end)
    end
  end
else
  defmodule Mix.Tasks.TimelessPhoenix.Install do
    @shortdoc "Installs TimelessPhoenix (requires igniter)."
    @moduledoc @shortdoc
    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'timeless_phoenix.install' requires igniter.
      Please install igniter and try again.

          {:igniter, "~> 0.6", only: [:dev]}

      For more information, see: https://hexdocs.pm/igniter
      """)

      exit({:shutdown, 1})
    end
  end
end
