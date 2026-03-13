defmodule TimelessPhoenix.MixProject do
  use Mix.Project

  @version "1.3.2"

  def project do
    [
      app: :timeless_phoenix,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Unified observability for Phoenix: persistent metrics, logs, and traces in LiveDashboard.",
      source_url: "https://github.com/awksedgreep/timeless_phoenix",
      homepage_url: "https://github.com/awksedgreep/timeless_phoenix",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      maintainers: ["Mark Cotner"],
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE),
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/awksedgreep/timeless_phoenix"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras:
        ["README.md", "LICENSE"] ++
          Path.wildcard("docs/*.md")
    ]
  end

  defp deps do
    [
      # Storage engines (override: child dashboards also depend on these)
      {:timeless_metrics, github: "awksedgreep/timeless_metrics", tag: "v3.7.0", override: true},
      {:timeless_logs, github: "awksedgreep/timeless_logs", tag: "v1.3.1", override: true},
      {:timeless_traces, github: "awksedgreep/timeless_traces", tag: "v1.2.1", override: true},

      # Dashboard pages
      {:timeless_metrics_dashboard,
       github: "awksedgreep/timeless_metrics_dashboard", tag: "v0.3.2"},
      {:timeless_logs_dashboard, github: "awksedgreep/timeless_logs_dashboard", tag: "v0.7.1"},
      {:timeless_traces_dashboard,
       github: "awksedgreep/timeless_traces_dashboard", tag: "v0.3.1"},

      # Phoenix / LiveDashboard
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_view, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},

      # OpenTelemetry instrumentation (auto-traces for Phoenix + Bandit)
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_bandit, "~> 0.3.0"},

      # Installer (optional — only used by mix igniter.install)
      {:igniter, "~> 0.6", optional: true}
    ]
  end
end
