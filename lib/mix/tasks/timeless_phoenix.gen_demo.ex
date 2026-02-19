if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.TimelessPhoenix.GenDemo do
    @shortdoc "Generates a demo traffic module for observability dashboards."
    @moduledoc """
    #{@shortdoc}

    Creates a GenServer that generates realistic background activity —
    simulated requests, DB queries, background jobs, cache operations,
    warnings, and errors — to populate your metrics, logs, and traces
    dashboards with interesting data.

    ## Usage

        mix timeless_phoenix.gen_demo

    ## What it does

    1. Creates `lib/<app>/demo_traffic.ex` with a GenServer that spawns
       varied simulated activity every 2 seconds
    2. Adds a `Task.Supervisor` and the `DemoTraffic` module to your
       application's supervision tree
    """

    use Igniter.Mix.Task

    @template ~S'''
    @moduledoc """
    Generates realistic background activity to populate the observability
    dashboards with metrics, logs, and traces.

    Starts automatically in the supervision tree. Spawns periodic processes
    that simulate varied application work — no HTTP requests needed.

    Remove this module (and its supervision tree entries) when you no longer
    need demo data.
    """

    use GenServer
    require Logger
    require OpenTelemetry.Tracer, as: Tracer

    @interval 2_000

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl true
    def init(_opts) do
      schedule()
      Logger.info("DemoTraffic started — generating background activity every #{@interval}ms")
      {:ok, %{tick: 0}}
    end

    @impl true
    def handle_info(:generate, %{tick: tick} = state) do
      tasks = [
        &simulate_request/0,
        &simulate_db_query/0,
        &simulate_background_job/0,
        &simulate_cache_operation/0
      ]

      count = Enum.random(3..6)

      Enum.take_random(tasks, count)
      |> Enum.each(fn task ->
        Task.Supervisor.start_child(__TASK_SUP__, task)
      end)

      if rem(tick, 5) == 0, do: simulate_warning()
      if rem(tick, 12) == 0, do: simulate_error()

      schedule()
      {:noreply, %{state | tick: tick + 1}}
    end

    defp schedule, do: Process.send_after(self(), :generate, @interval)

    defp simulate_request do
      method = Enum.random(["GET", "POST", "PUT", "DELETE"])
      path = Enum.random(["/users", "/orders", "/products", "/api/health", "/search"])
      status = Enum.random([200, 200, 200, 200, 201, 301, 404])
      duration = Enum.random(5..150)

      Tracer.with_span "#{method} #{path}", attributes: %{"http.method" => method, "http.target" => path, "http.status_code" => status} do
        :telemetry.execute(
          [:__OTP_APP__, :request, :stop],
          %{duration: duration * 1_000_000},
          %{method: method, path: path, status: status}
        )

        Logger.info("#{method} #{path} — #{status} in #{duration}ms",
          method: method,
          path: path,
          status: status,
          request_id: random_id()
        )

        Process.sleep(duration)

        if status >= 400 do
          Tracer.set_status(:error, "HTTP #{status}")
        end
      end
    end

    defp simulate_db_query do
      table = Enum.random(["users", "orders", "products", "sessions", "events"])
      duration = Enum.random(1..50)

      Tracer.with_span "DB #{table}", attributes: %{"db.system" => "postgresql", "db.sql.table" => table} do
        :telemetry.execute(
          [:__OTP_APP__, :repo, :query],
          %{total_time: duration * 1_000_000, queue_time: Enum.random(0..5) * 1_000_000},
          %{source: table}
        )

        Logger.debug("SQL query on #{table} completed in #{duration}ms",
          table: table,
          duration_ms: duration
        )

        Process.sleep(duration)
      end
    end

    defp simulate_background_job do
      job = Enum.random(["send_email", "process_payment", "generate_report", "sync_inventory"])
      duration = Enum.random(50..500)

      Tracer.with_span "job.#{job}", attributes: %{"job.type" => job} do
        Logger.info("Starting background job: #{job}", job: job)
        Process.sleep(duration)
        Logger.info("Completed background job: #{job} in #{duration}ms", job: job, duration_ms: duration)
      end
    end

    defp simulate_cache_operation do
      op = Enum.random(["hit", "hit", "hit", "miss"])
      key = Enum.random(["user:123", "product:456", "session:abc", "config:main"])

      Tracer.with_span "cache.#{op}", attributes: %{"cache.key" => key, "cache.hit" => op == "hit"} do
        if op == "miss" do
          Logger.debug("Cache miss for #{key}, fetching from source", cache: op, key: key)
        else
          Logger.debug("Cache #{op} for #{key}", cache: op, key: key)
        end
      end
    end

    defp simulate_warning do
      warnings = [
        {"Connection pool running low", %{pool_size: 10, available: 2}},
        {"Slow query detected", %{table: "events", duration_ms: 850}},
        {"Rate limit approaching", %{current: 95, limit: 100}},
        {"Memory usage elevated", %{mb: Enum.random(400..600)}}
      ]

      {message, meta} = Enum.random(warnings)
      Logger.warning(message, Map.to_list(meta))
    end

    defp simulate_error do
      errors = [
        {"Connection timeout to external API", %{service: "payments", timeout_ms: 5000}},
        {"Failed to process webhook", %{webhook_id: random_id(), reason: "invalid_signature"}},
        {"Database deadlock detected", %{table: "orders", retries: 3}}
      ]

      {message, meta} = Enum.random(errors)
      Logger.error(message, Map.to_list(meta))
    end

    defp random_id do
      :crypto.strong_rand_bytes(8) |> Base.hex_encode32(case: :lower, padding: false)
    end
    '''

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :timeless_phoenix,
        schema: [],
        defaults: [],
        required: [],
        positional: [],
        aliases: [],
        composes: [],
        installs: [],
        adds_deps: [],
        example: "mix timeless_phoenix.gen_demo"
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      otp_app = Igniter.Project.Application.app_name(igniter)
      base_module = otp_app |> Atom.to_string() |> Macro.camelize() |> String.to_atom()
      base_module = Module.concat([base_module])

      demo_module = Module.concat(base_module, DemoTraffic)
      task_sup_module = Module.concat(base_module, DemoTaskSupervisor)

      igniter
      |> create_demo_traffic_module(demo_module, task_sup_module, otp_app)
      |> add_to_supervision_tree(demo_module, task_sup_module)
    end

    defp create_demo_traffic_module(igniter, demo_module, task_sup_module, otp_app) do
      contents =
        @template
        |> String.replace("__TASK_SUP__", inspect(task_sup_module))
        |> String.replace("__OTP_APP__", Atom.to_string(otp_app))

      Igniter.Project.Module.create_module(igniter, demo_module, contents)
    end

    defp add_to_supervision_tree(igniter, demo_module, task_sup_module) do
      # Task.Supervisor must come before DemoTraffic in the children list
      igniter
      |> Igniter.Project.Application.add_new_child(demo_module)
      |> Igniter.Project.Application.add_new_child(
        {Task.Supervisor, name: task_sup_module}
      )
    end
  end
else
  defmodule Mix.Tasks.TimelessPhoenix.GenDemo do
    @shortdoc "Generates demo traffic module (requires igniter)."
    @moduledoc @shortdoc
    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'timeless_phoenix.gen_demo' requires igniter.
      Please install igniter and try again.

          {:igniter, "~> 0.6", only: [:dev]}
      """)

      exit({:shutdown, 1})
    end
  end
end
