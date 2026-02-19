defmodule TimelessPhoenix.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :timeless_phoenix,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Unified observability for Phoenix: persistent metrics, logs, and traces in LiveDashboard."
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Storage engines (override: child dashboards also depend on these)
      {:timeless_metrics, path: "../timeless_metrics", override: true},
      {:timeless_logs, path: "../timeless_logs", override: true},
      {:timeless_traces, path: "../timeless_traces", override: true},

      # Dashboard pages
      {:timeless_metrics_dashboard, path: "../timeless_metrics_dashboard"},
      {:timeless_logs_dashboard, path: "../timeless_logs_dashboard"},
      {:timeless_traces_dashboard, path: "../timeless_traces_dashboard"},

      # Phoenix / LiveDashboard
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_view, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},

      # Installer (optional — only used by mix igniter.install)
      {:igniter, "~> 0.6", optional: true}
    ]
  end
end
