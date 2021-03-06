defmodule Singleton.Manager do
  @moduledoc """

  Singleton watchdog process

  Each node that the singleton runs on, runs this process. It is
  responsible for starting the singleton process (with the help of
  Erlang's 'global' module).

  When starting the singleton process fails, it instead monitors the
  process, so that in case it dies, it will try to start it locally.

  The singleton process is started using the `GenServer.start_link`
  call, with the given module and args.

  """

  use GenServer

  require Logger

  @doc """
  Start the manager process, registering it under a unique name.
  """
  def start_link(mod, args, name, child_name) do
    GenServer.start_link(__MODULE__, [mod, args, name], name: child_name)
  end

  defmodule State do
    @moduledoc false
    defstruct pid: nil, mod: nil, args: nil, name: nil
  end

  @doc false
  def init([mod, args, name]) do
    state = %State{mod: mod, args: args, name: name}
    {:ok, start_and_monitor(state)}
  end

  @doc false
  def handle_info({:DOWN, _, :process, pid, :normal}, state = %State{pid: pid}) do
    # Managed process exited normally. Shut manager down as well.
    {:stop, :normal, state}
  end

  def handle_info({:DOWN, _, :process, pid, _reason}, state = %State{pid: pid}) do
    # Managed process exited with an error. Try restarting after 10 seconds
    # (delay to prevent crashloops from consuming too much resources)
    Process.sleep(10_000)
    {:noreply, start_and_monitor(state)}
  end

  defp start_and_monitor(state) do
    start_result = GenServer.start_link(state.mod, state.args, name: {:global, state.name})

    pid =
      case start_result do
        {:ok, pid} ->
          Logger.info("Singleton #{state.name} started with pid #{pid |> inspect()}")
          pid

        {:error, {:already_started, pid}} ->
          pid
      end

    Process.monitor(pid)
    %State{state | pid: pid}
  end
end
