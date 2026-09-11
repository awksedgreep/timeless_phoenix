defmodule TimelessPhoenix.ApplicationMonitor do
  @moduledoc false

  use GenServer

  def child_spec(opts) do
    app = Keyword.fetch!(opts, :app)

    %{
      id: {__MODULE__, app},
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent
    }
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    app = Keyword.fetch!(opts, :app)
    supervisor = Keyword.fetch!(opts, :supervisor)

    if Keyword.get(opts, :restart_before_start?, false) and application_started?(app) do
      :ok = Application.stop(app)
    end

    case start_and_monitor(app, supervisor) do
      {:ok, monitor} -> {:ok, %{app: app, supervisor: supervisor, monitor: monitor}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_info({:DOWN, monitor, :process, _pid, reason}, %{monitor: monitor} = state) do
    case restart_and_monitor(state.app, state.supervisor) do
      {:ok, new_monitor} -> {:noreply, %{state | monitor: new_monitor}}
      {:error, restart_reason} -> {:stop, {:application_down, reason, restart_reason}, state}
    end
  end

  @impl true
  def terminate(reason, state) when reason in [:normal, :shutdown] do
    _ = Application.stop(state.app)
    :ok
  end

  def terminate({:shutdown, _}, state) do
    _ = Application.stop(state.app)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp restart_and_monitor(app, supervisor) do
    _ = Application.stop(app)
    start_and_monitor(app, supervisor)
  end

  defp start_and_monitor(app, supervisor) do
    with {:ok, _started} <- Application.ensure_all_started(app),
         pid when is_pid(pid) <- Process.whereis(supervisor) do
      {:ok, Process.monitor(pid)}
    else
      nil -> {:error, {:application_supervisor_not_running, app, supervisor}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp application_started?(app) do
    Enum.any?(Application.started_applications(), fn {started, _description, _version} ->
      started == app
    end)
  end
end
