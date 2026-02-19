defmodule TimelessPhoenix.Router do
  @moduledoc """
  Router macro for one-line LiveDashboard setup with all observability pages.

  ## Usage

      defmodule MyAppWeb.Router do
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

  ## Options

    * `:name` — TimelessPhoenix instance name (default: `:default`)
    * `:metrics` — metrics module passed to LiveDashboard (default: `TimelessPhoenix.DefaultMetrics`)
    * `:download_path` — path for backup downloads (default: `"/timeless/downloads"`)
    * `:live_dashboard` — extra opts merged into `live_dashboard` call
  """

  @doc """
  Mounts the TimelessMetricsDashboard download plug and LiveDashboard with all pages.
  """
  defmacro timeless_phoenix_dashboard(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      import Phoenix.LiveDashboard.Router

      name = Keyword.get(opts, :name, :default)
      metrics_mod = Keyword.get(opts, :metrics, TimelessPhoenix.DefaultMetrics)
      download_path = Keyword.get(opts, :download_path, "/timeless/downloads")
      store = TimelessPhoenix.store_name(name)
      extra = Keyword.get(opts, :live_dashboard, [])

      forward download_path, TimelessMetricsDashboard.DownloadPlug, store: store

      dashboard_opts =
        [
          metrics: metrics_mod,
          metrics_history: {TimelessPhoenix, :metrics_history, [name]},
          additional_pages: TimelessPhoenix.dashboard_pages(name: name, download_path: download_path)
        ] ++ extra

      live_dashboard path, dashboard_opts
    end
  end
end
