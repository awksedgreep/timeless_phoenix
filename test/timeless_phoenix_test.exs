defmodule TimelessPhoenixTest do
  use ExUnit.Case

  alias TimelessPhoenix.Identity

  test "child_spec returns supervisor spec with default name" do
    spec = TimelessPhoenix.child_spec(data_dir: "/tmp/test")

    assert spec.id == {TimelessPhoenix, :default}
    assert spec.type == :supervisor
    assert {TimelessPhoenix.Supervisor, :start_link, [opts]} = spec.start
    assert Keyword.fetch!(opts, :data_dir) == "/tmp/test"
  end

  test "child_spec uses custom name" do
    spec = TimelessPhoenix.child_spec(data_dir: "/tmp/test", name: :custom)

    assert spec.id == {TimelessPhoenix, :custom}
  end

  test "store_name and reporter_name" do
    assert TimelessPhoenix.store_name(:default) == :tp_default_timeless
    assert TimelessPhoenix.reporter_name(:default) == :tp_default_reporter
    assert TimelessPhoenix.store_name(:prod) == :tp_prod_timeless
  end

  test "dashboard_pages returns three pages" do
    pages = TimelessPhoenix.dashboard_pages()

    assert Keyword.has_key?(pages, :timeless)
    assert Keyword.has_key?(pages, :logs)
    assert Keyword.has_key?(pages, :traces)

    assert {TimelessMetricsDashboard.Page, page_opts} = pages[:timeless]
    assert page_opts[:store] == :tp_default_timeless
    assert page_opts[:download_path] == "/timeless/downloads"

    assert pages[:logs] == TimelessLogsDashboard.Page
    assert pages[:traces] == TimelessTracesDashboard.Page
  end

  test "dashboard_pages has timeless_beam_acct's page where it is, and not where it is not" do
    # Not among this project's dependencies, so not there unless asked for.
    refute Keyword.has_key?(TimelessPhoenix.dashboard_pages(), :beam)

    pages = TimelessPhoenix.dashboard_pages(beam_acct: true)
    assert pages[:beam] == TimelessBeamAcct.Dashboard.Page
    assert Keyword.keys(pages) == [:timeless, :logs, :traces, :beam]

    refute Keyword.has_key?(TimelessPhoenix.dashboard_pages(beam_acct: false), :beam)
  end

  test "DefaultMetrics.all returns a non-empty list of metrics" do
    metrics = TimelessPhoenix.DefaultMetrics.all()
    assert is_list(metrics)
    assert length(metrics) > 0
    assert Enum.all?(metrics, &match?(%{__struct__: _}, &1))
  end

  test "DefaultMetrics.metrics/0 delegates to all/0" do
    assert TimelessPhoenix.DefaultMetrics.metrics() == TimelessPhoenix.DefaultMetrics.all()
  end

  test "identity merges missing host and service into keyword resource config" do
    resource = [service: [name: "existing-service"]]

    merged =
      Identity.merge_resource(resource, %{service_name: "new-service", host_name: "web-01"})

    assert Keyword.get(merged, :service)[:name] == "existing-service"
    assert Keyword.get(merged, :host)[:name] == "web-01"
  end

  test "identity merges missing host and service into map resource config" do
    resource = %{service: %{name: "existing-service"}}

    merged =
      Identity.merge_resource(resource, %{service_name: "new-service", host_name: "web-01"})

    assert get_in(merged, [:service, :name]) == "existing-service"
    assert get_in(merged, [:host, :name]) == "web-01"
  end

  test "identity logger metadata includes canonical OpenTelemetry keys once" do
    previous = Application.fetch_env(:opentelemetry, :resource)
    on_exit(fn -> restore_env(:opentelemetry, :resource, previous) end)

    Application.put_env(:opentelemetry, :resource,
      service: [name: "timeless-ui"],
      host: [name: "vpn"]
    )

    metadata = Identity.logger_metadata()

    assert metadata[:"service.name"] == "timeless-ui"
    assert metadata[:"host.name"] == "vpn"
    refute Keyword.has_key?(metadata, :service)
    refute Keyword.has_key?(metadata, :host)
  end

  test "identity resolves keyword and string-keyed resources without creating atoms" do
    previous = Application.fetch_env(:opentelemetry, :resource)
    on_exit(fn -> restore_env(:opentelemetry, :resource, previous) end)

    Application.put_env(:opentelemetry, :resource, [
      {"service.name", "dotted"},
      {:host, [name: "nested"]}
    ])

    assert Identity.resolve() == %{service_name: "dotted", host_name: "nested"}
  end

  test "default flush metrics do not duplicate summary and counter definitions" do
    for metrics <- [
          TimelessPhoenix.DefaultMetrics.log_stream_metrics(),
          TimelessPhoenix.DefaultMetrics.span_stream_metrics()
        ] do
      names = Enum.map(metrics, & &1.name)
      assert length(names) == length(Enum.uniq(names))
    end
  end

  test "default metrics are memoized" do
    :persistent_term.erase({TimelessPhoenix.DefaultMetrics, :all, 1})
    metrics = TimelessPhoenix.DefaultMetrics.all()

    assert :persistent_term.get({TimelessPhoenix.DefaultMetrics, :all, 1}) == metrics
  end

  test "public naming helpers reject non-atom instance names" do
    assert_raise FunctionClauseError, fn -> apply(TimelessPhoenix, :store_name, ["unsafe"]) end
    assert_raise FunctionClauseError, fn -> apply(TimelessPhoenix, :reporter_name, ["unsafe"]) end
  end

  defp restore_env(app, key, {:ok, value}), do: Application.put_env(app, key, value)
  defp restore_env(app, key, :error), do: Application.delete_env(app, key)
end
