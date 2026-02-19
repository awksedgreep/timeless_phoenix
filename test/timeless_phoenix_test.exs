defmodule TimelessPhoenixTest do
  use ExUnit.Case

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

  test "DefaultMetrics.all returns a non-empty list of metrics" do
    metrics = TimelessPhoenix.DefaultMetrics.all()
    assert is_list(metrics)
    assert length(metrics) > 0
    assert Enum.all?(metrics, &match?(%{__struct__: _}, &1))
  end

  test "DefaultMetrics.metrics/0 delegates to all/0" do
    assert TimelessPhoenix.DefaultMetrics.metrics() == TimelessPhoenix.DefaultMetrics.all()
  end
end
