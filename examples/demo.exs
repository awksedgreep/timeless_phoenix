# Unified observability demo — metrics + logs + traces in one LiveDashboard.
#
# Run:  mix run examples/demo.exs
# Open: http://localhost:4000/dashboard
# Stop: Ctrl+C twice

Logger.configure(level: :info)

# --- Router + Endpoint ---

defmodule Demo.Router do
  use Phoenix.Router
  import TimelessPhoenix.Router

  pipeline :browser do
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/" do
    pipe_through :browser
    timeless_phoenix_dashboard "/dashboard"
  end
end

defmodule Demo.ErrorView do
  def render(template, _assigns), do: "Error: #{template}"
end

defmodule Demo.Endpoint do
  use Phoenix.Endpoint, otp_app: :timeless_phoenix

  @session_options [
    store: :cookie,
    key: "_demo_key",
    signing_salt: "demo_salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.Session, @session_options
  plug Demo.Router
end

# --- Boot ---

data_dir = System.get_env("TIMELESS_DATA_DIR") || Path.join(System.tmp_dir!(), "timeless_phoenix_demo")
IO.puts("Data dir: #{data_dir}")

Application.put_env(:timeless_phoenix, Demo.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [port: 4000],
  url: [host: "localhost"],
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "demo_lv_salt"],
  pubsub_server: Demo.PubSub,
  server: true
)

{:ok, _} = Application.ensure_all_started(:phoenix_live_dashboard)

{:ok, _} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: Demo.PubSub},
      {TimelessPhoenix, data_dir: data_dir},
      Demo.Endpoint
    ],
    strategy: :one_for_one
  )

IO.puts("""

========================================
  TimelessPhoenix Demo
  http://localhost:4000/dashboard

  Pages:
    /dashboard/timeless — Metrics TSDB
    /dashboard/logs     — Log search & tail
    /dashboard/spans    — Trace waterfall
    /dashboard/metrics  — Live charts (with history)
========================================
""")

Process.sleep(:infinity)
