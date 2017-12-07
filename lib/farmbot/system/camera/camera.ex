defmodule Farmbot.System.Camera do
  use GenServer
  use Farmbot.Logger

  def start_link(cb) do
    GenServer.start_link(__MODULE__, [cb], [name: __MODULE__])
  end

  def stop(pid, reason) do
    GenServer.stop(pid, reason)
  end

  def claim(pid) do
    GenServer.call(pid, :claim)
  end

  def claimed?(pid) do
    GenServer.call(pid, :claimed?)
  end

  def release(pid) do
    GenServer.call(pid, :release)
  end

  def init([cb]) do
    case Picam.Camera.start_link() do
      {:ok, pid} ->
        Process.link(pid)
        {:ok, %{camera: pid, timer: nil, cb: cb, claimed: false}}
      _ -> {:stop, :failed_to_start_camera}
    end
  end

  def terminate(reason, state) do
    if Process.alive?(state.camera) do
      GenServer.stop(state.camera, reason)
    end
  end

  def handle_info(:capture, %{claimed: false} = state) do
    {:noreply, state}
  end

  def handle_info(:capture, %{claimed: true} = state) do
    # Logger.info 1, "taking frame"
    frame = Picam.next_frame()
    send state.cb, {:camera, {:frame, frame}}
    {:noreply, %{state | timer: start_timer()}}
  end

  def handle_call(:claim, _, state) do
    {:reply, :ok, %{state | timer: start_timer(), claimed: true}}
  end

  def handle_call(:release, _, state) do
    Process.cancel_timer(state.timer)
    {:reply, :ok, %{state | timer: nil, claimed: false}}
  end

  def handle_call(:claimed?, _, state) do
    {:reply, state.claimed, state}
  end

  defp start_timer do
    Process.send_after(self(), :capture, 10)
  end
end
