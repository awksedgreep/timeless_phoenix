defmodule TimelessPhoenix.Doctor do
  @moduledoc """
  Post-upgrade verification for the 2.0 libSQL engines: confirms every
  embedded signal is configured AND running on the libSQL engine, the
  extension capability handshake holds, legacy stores were converted
  (with rollback material retained), and data is present.

  Run on a live node (e.g. from `bin/my_app remote`):

      TimelessPhoenix.doctor()

  Prints a report and returns `{verdict, report}` where verdict is
  `:ok` | `:warn` | `:error`. `:ok` means safe to trust the conversion.
  """

  @doc false
  def run(name \\ :default) do
    store = TimelessPhoenix.store_name(name)

    report = %{
      metrics: check_metrics(store),
      logs: check_logs(),
      traces: check_traces()
    }

    verdict =
      report
      |> Map.values()
      |> Enum.map(& &1.verdict)
      |> Enum.max_by(&verdict_rank/1)

    print(report, verdict)
    {verdict, report}
  end

  defp verdict_rank(:ok), do: 0
  defp verdict_rank(:warn), do: 1
  defp verdict_rank(:error), do: 2

  # -- metrics ---------------------------------------------------------------

  defp check_metrics(store) do
    configured = :persistent_term.get({TimelessMetrics, store, :engine}, :missing)
    data_dir = :persistent_term.get({TimelessMetrics, store, :data_dir}, nil)

    checks =
      [engine_check(:metrics, configured)] ++
        if configured == :libsql do
          [
            metrics_capability_check(store),
            metrics_conversion_check(store, data_dir),
            metrics_data_check(store)
          ]
        else
          []
        end

    summarize(checks)
  end

  defp metrics_capability_check(store) do
    writer = TimelessMetrics.LibsqlEngine.writer_name(store)

    case GenServer.call(writer, {:sql, "SELECT timeless_capabilities()", []}, 15_000) do
      {:ok, [[json]]} ->
        caps = :json.decode(json)

        if caps["data_abi"] == 1 do
          {:ok, "extension #{caps["extension_version"]}, data ABI 1"}
        else
          {:error, "unexpected data ABI: #{inspect(caps["data_abi"])}"}
        end

      other ->
        {:error, "capability query failed: #{inspect(other)}"}
    end
  catch
    :exit, reason -> {:error, "libSQL writer not reachable: #{inspect(reason)}"}
  end

  defp metrics_conversion_check(store, data_dir) do
    rust_dir = data_dir && Path.join(data_dir, "rust_engine")
    had_legacy? = rust_dir && match?({:ok, [_ | _]}, File.ls(rust_dir))

    if had_legacy? do
      db = :"#{store}_db"

      case TimelessMetrics.DB.read(
             db,
             "SELECT value FROM _metadata WHERE key = 'libsql_migration' LIMIT 1",
             []
           ) do
        {:ok, [[marker]]} ->
          {:ok,
           "converted (marker: #{summarize_marker(marker)}); rust_engine/ retained for rollback"}

        _ ->
          {:error,
           "rust_engine/ present but NO conversion marker — the store may be " <>
             "serving an empty database instead of converted data"}
      end
    else
      {:ok, "no legacy rust_engine/ store (fresh or already cleaned)"}
    end
  end

  defp summarize_marker(marker) when is_binary(marker) do
    case :json.decode(marker) do
      %{"series" => s, "points" => p} -> "#{s} series, #{p} points"
      _ -> "present"
    end
  rescue
    _ -> "present"
  end

  defp metrics_data_check(store) do
    info = TimelessMetrics.info(store)
    {:ok, "#{info.series_count} series, #{info.total_points} points"}
  rescue
    error -> {:warn, "info unavailable: #{Exception.message(error)}"}
  end

  # -- logs / traces ---------------------------------------------------------

  defp check_logs do
    check_singleton(
      :logs,
      :timeless_logs,
      {TimelessLogs, :engine},
      "logs_index.db",
      "logs.db",
      fn -> TimelessLogs.LibsqlEngine.sql("SELECT timeless_capabilities()") end,
      fn ->
        {:ok, stats} = TimelessLogs.stats()
        "#{stats.total_entries} entries, #{stats.total_blocks} blocks"
      end
    )
  end

  defp check_traces do
    check_singleton(
      :traces,
      :timeless_traces,
      {TimelessTraces, :engine},
      "traces_index.db",
      "traces.db",
      fn -> TimelessTraces.LibsqlEngine.sql("SELECT timeless_capabilities()") end,
      fn ->
        {:ok, stats} = TimelessTraces.stats()
        "#{stats.total_entries} spans, #{stats.total_blocks} blocks"
      end
    )
  end

  defp check_singleton(signal, app, pt_key, legacy_marker, converted_db, caps_fun, data_fun) do
    if Application.get_env(app, :owner, :embedded) == :external do
      summarize([{:ok, "externally owned (Rust service) — verify via the service, not here"}])
    else
      running = :persistent_term.get(pt_key, :missing)
      data_dir = Application.get_env(app, :data_dir)

      checks =
        [engine_check(signal, running)] ++
          if running == :libsql do
            [
              singleton_caps(caps_fun),
              singleton_conversion(data_dir, legacy_marker, converted_db),
              singleton_data(data_fun)
            ]
          else
            []
          end

      summarize(checks)
    end
  end

  defp singleton_caps(caps_fun) do
    case caps_fun.() do
      {:ok, [[json]]} ->
        caps = :json.decode(json)

        if caps["data_abi"] == 1 do
          {:ok, "extension #{caps["extension_version"]}, data ABI 1"}
        else
          {:error, "unexpected data ABI: #{inspect(caps["data_abi"])}"}
        end

      other ->
        {:error, "capability query failed: #{inspect(other)}"}
    end
  catch
    :exit, reason -> {:error, "libSQL engine not reachable: #{inspect(reason)}"}
  end

  defp singleton_conversion(nil, _legacy, _converted), do: {:warn, "data_dir not configured"}

  defp singleton_conversion(data_dir, legacy_marker, converted_db) do
    legacy? =
      File.exists?(Path.join(data_dir, legacy_marker)) or
        File.dir?(Path.join(data_dir, "blocks"))

    converted? = File.exists?(Path.join(data_dir, converted_db))

    cond do
      legacy? and converted? ->
        {:ok, "converted; legacy source retained for rollback"}

      legacy? and not converted? ->
        {:error, "legacy store present but #{converted_db} missing — conversion did not run"}

      true ->
        {:ok, "no legacy store (fresh or already cleaned)"}
    end
  end

  defp singleton_data(data_fun) do
    {:ok, data_fun.()}
  rescue
    error -> {:warn, "stats unavailable: #{Exception.message(error)}"}
  end

  # -- shared ----------------------------------------------------------------

  defp engine_check(signal, :libsql), do: {:ok, "#{signal} running on the libSQL engine"}

  defp engine_check(signal, :missing),
    do: {:error, "#{signal}: no engine registered — is the store running on this node?"}

  defp engine_check(signal, other),
    do: {:warn, "#{signal} running on deprecated engine #{inspect(other)} (removal ~2026-11)"}

  defp summarize(checks) do
    verdict =
      checks
      |> Enum.map(fn {v, _} -> v end)
      |> Enum.max_by(&verdict_rank/1)

    %{verdict: verdict, checks: checks}
  end

  defp print(report, verdict) do
    IO.puts("== timeless_phoenix doctor ==")

    for {signal, %{checks: checks}} <- Enum.sort(report) do
      IO.puts("#{signal}:")

      for {v, message} <- checks do
        IO.puts("  #{icon(v)} #{message}")
      end
    end

    IO.puts("verdict: #{String.upcase(to_string(verdict))}")
  end

  defp icon(:ok), do: "[ok]"
  defp icon(:warn), do: "[warn]"
  defp icon(:error), do: "[ERROR]"
end
