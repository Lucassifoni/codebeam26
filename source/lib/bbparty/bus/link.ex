defmodule Bbparty.Bus.Link do
  use GenServer
  require Logger

  alias Bbparty.Bus.Frame

  @frames_topic "bus:frames"
  @speed 115_200
  @reopen_ms 1_000

  @reset_pulse_ms 100

  def start_link(port) when is_binary(port) do
    GenServer.start_link(__MODULE__, port, name: via(port))
  end

  defp via(port), do: {:via, Registry, {Bbparty.Bus.LinkRegistry, port}}

  def frames_topic, do: @frames_topic
  def subscribe_frames, do: Phoenix.PubSub.subscribe(Bbparty.PubSub, @frames_topic)

  @spec publish_frame(0..255, binary()) :: :ok | {:error, term()}
  def publish_frame(module_id, body) when module_id in 0..255 and is_binary(body) do
    Phoenix.PubSub.broadcast(Bbparty.PubSub, @frames_topic, {:frame, module_id, body})
  end

  def module_connected?(module_id) do
    match?([_ | _], Registry.lookup(Bbparty.Bus.ModuleRegistry, module_id))
  end

  def connected_modules do
    Registry.select(Bbparty.Bus.ModuleRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  def send_command(module_id, body) when is_integer(module_id) and is_binary(body) do
    case Registry.lookup(Bbparty.Bus.ModuleRegistry, module_id) do
      [{pid, _} | _] -> GenServer.call(pid, {:send, module_id, body})
      [] -> {:error, :not_connected}
    end
  end

  @spec reboot_all() :: :ok
  def reboot_all do
    Bbparty.Bus.LinkRegistry
    |> Registry.select([{{:_, :"$1", :_}, [], [:"$1"]}])
    |> Enum.each(&GenServer.cast(&1, :reboot))
  end

  @impl true
  def init(port) do
    {:ok, uart} = Circuits.UART.start_link()
    state = %{port: port, uart: uart, reader: Frame.Reader.new(), module_id: nil, open?: false}
    {:ok, state, {:continue, :open}}
  end

  @impl true
  def handle_continue(:open, state), do: {:noreply, try_open(state)}

  @impl true
  def handle_call({:send, _module_id, _body}, _from, %{open?: false} = state) do
    {:reply, {:error, :not_open}, state}
  end

  def handle_call({:send, module_id, body}, _from, state) do
    frame = Frame.encode(<<module_id>> <> body)
    {:reply, Circuits.UART.write(state.uart, frame), state}
  end

  @impl true
  def handle_cast(:reboot, %{open?: false} = state), do: {:noreply, state}

  def handle_cast(:reboot, state) do
    Logger.info("Bus.Link rebooting the board on #{state.port}")
    Circuits.UART.set_dtr(state.uart, false)
    Circuits.UART.set_rts(state.uart, true)
    Process.send_after(self(), :release_reset, @reset_pulse_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(:reopen, state), do: {:noreply, try_open(state)}

  def handle_info(:release_reset, %{open?: true} = state) do
    Circuits.UART.set_rts(state.uart, false)
    {:noreply, %{state | reader: Frame.Reader.new()}}
  end

  def handle_info({:circuits_uart, _port, data}, state) when is_binary(data) do
    {reader, frames} = Frame.Reader.push(state.reader, data)
    state = Enum.reduce(frames, %{state | reader: reader}, &dispatch/2)
    {:noreply, state}
  end

  def handle_info({:circuits_uart, _port, {:error, reason}}, state) do
    Logger.warning("Bus.Link #{state.port} error: #{inspect(reason)}; reopening")
    Circuits.UART.close(state.uart)
    Process.send_after(self(), :reopen, @reopen_ms)
    {:noreply, %{state | open?: false, reader: Frame.Reader.new()}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp try_open(state) do
    opts = [speed: @speed, active: true, framing: Circuits.UART.Framing.None]

    case Circuits.UART.open(state.uart, state.port, opts) do
      :ok ->
        Logger.info("Bus.Link opened #{state.port}")
        %{state | open?: true, reader: Frame.Reader.new()}

      {:error, reason} ->
        Logger.warning("Bus.Link open #{state.port} failed: #{inspect(reason)}; retrying")
        Process.send_after(self(), :reopen, @reopen_ms)
        %{state | open?: false}
    end
  end

  defp dispatch(<<module_id, body::binary>>, state) do
    state = learn_module(state, module_id)
    publish_frame(module_id, body)
    state
  end

  defp dispatch(_frame, state), do: state

  defp learn_module(%{module_id: nil} = state, module_id) do
    case Registry.register(Bbparty.Bus.ModuleRegistry, module_id, state.port) do
      {:ok, _} ->
        Logger.info("Bus.Link #{state.port} is module 0x#{Integer.to_string(module_id, 16)}")

      {:error, {:already_registered, _}} ->
        Logger.warning("Bus.Link #{state.port}: module #{module_id} already on the bus")
    end

    %{state | module_id: module_id}
  end

  defp learn_module(state, _module_id), do: state
end
