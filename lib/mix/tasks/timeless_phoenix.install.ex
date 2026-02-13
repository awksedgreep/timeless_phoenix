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

      * `--storage` — `disk` (default) or `memory`. Memory mode stores logs and
        traces in memory only (lost on restart). Metrics are always persisted to disk.

    ## What it does

    1. Adds `{TimelessPhoenix, data_dir: "priv/observability"}` to your application's
       supervision tree (with `log_stream: [storage: :memory], span_stream: [storage: :memory]`
       when `--storage memory` is used)
    2. Adds `import TimelessPhoenix.Router` to your Phoenix router
    3. Adds `timeless_phoenix_dashboard "/dashboard"` to your router's browser scope
    4. Adds `:timeless_phoenix` to your `.formatter.exs` import_deps
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
      |> setup_router()
      |> Igniter.Project.Formatter.import_dep(:timeless_phoenix)
    end

    # Adds {TimelessPhoenix, ...} to the application's children list.
    defp add_to_supervision_tree(igniter, storage) do
      child_code =
        case storage do
          "memory" ->
            Sourceror.parse_string!("""
            data_dir: "priv/observability",
            timeless_logs: [storage: :memory],
            timeless_traces: [storage: :memory]
            """)

          _ ->
            Sourceror.parse_string!(~s(data_dir: "priv/observability"))
        end

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
