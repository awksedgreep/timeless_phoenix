defmodule TimelessPhoenix.RouterTest.Router do
  use Phoenix.Router
  import TimelessPhoenix.Router

  scope "/" do
    timeless_phoenix_dashboard("/dashboard",
      live_dashboard: [metrics: false, metrics_history: nil, additional_pages: []]
    )
  end
end

defmodule TimelessPhoenix.RouterTest do
  use ExUnit.Case, async: true

  test "the dashboard macro does not require importing LiveDashboard into the host router" do
    assert Enum.any?(TimelessPhoenix.RouterTest.Router.__routes__(), fn route ->
             String.starts_with?(route.path, "/dashboard")
           end)
  end

  test "explicit LiveDashboard options override generated defaults" do
    home_route =
      Enum.find(TimelessPhoenix.RouterTest.Router.__routes__(), &(&1.path == "/dashboard"))

    assert %{phoenix_live_view: {_view, _action, _route_opts, live_opts}} = home_route.metadata

    assert %{extra: %{session: {Phoenix.LiveDashboard.Router, :__session__, session_opts}}} =
             live_opts

    assert [nil, _title, false, _request_logger, nil, [] | _rest] = session_opts
  end
end
