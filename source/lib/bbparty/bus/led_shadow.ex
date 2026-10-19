defmodule Bbparty.Bus.LedShadow do
  use GenServer
  require Logger

  alias Bbparty.Bus.{Link, Module2, Module7}
  alias Bbparty.Bus.LedShadow.Frame

  @boards %{
    0x02 => %{width: 8, codec: Module2, brightness: true},
    0x07 => %{width: 64, codec: Module7, brightness: false}
  }

  @flush_ms 20
  @full_brightness 255

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @spec put(0..255, integer(), boolean()) :: :ok
  def put(module_id, channel, on?),
    do: GenServer.cast(__MODULE__, {:put, module_id, channel, on?})

  @spec blank(0..255) :: :ok
  def blank(module_id), do: GenServer.cast(__MODULE__, {:blank, module_id})

  @spec reassert(0..255) :: :ok
  def reassert(module_id), do: GenServer.cast(__MODULE__, {:reassert, module_id})

  @spec set_brightness(0..255, 0..255) :: :ok
  def set_brightness(module_id, level),
    do: GenServer.cast(__MODULE__, {:brightness, module_id, level})

  @spec frame(0..255) :: Frame.t() | nil
  def frame(module_id), do: GenServer.call(__MODULE__, {:frame, module_id})

  @spec boards() :: %{
          optional(0..255) => %{width: pos_integer(), codec: module(), brightness: boolean()}
        }
  def boards, do: @boards

  @impl true
  def init(_) do
    frames = Map.new(@boards, fn {id, %{width: width}} -> {id, Frame.new(width)} end)
    {:ok, %{frames: frames, dirty: MapSet.new(), timer: nil}}
  end

  @impl true
  def handle_call({:frame, module_id}, _from, state), do: {:reply, state.frames[module_id], state}

  @impl true
  def handle_cast({:put, module_id, channel, on?}, state) do
    case state.frames[module_id] do
      nil ->
        Logger.warning("LedShadow: no board 0x#{Integer.to_string(module_id, 16)}")
        {:noreply, state}

      frame ->
        updated = Frame.put(frame, channel, on?)
        state = %{state | frames: Map.put(state.frames, module_id, updated)}

        case updated == frame do
          true -> {:noreply, state}
          false -> {:noreply, mark(state, module_id)}
        end
    end
  end

  def handle_cast({:blank, module_id}, state) do
    case state.frames[module_id] do
      nil ->
        {:noreply, state}

      frame ->
        cleared = Frame.new(frame.width)
        state = %{state | frames: Map.put(state.frames, module_id, cleared)}

        case cleared == frame do
          true -> {:noreply, state}
          false -> {:noreply, mark(state, module_id)}
        end
    end
  end

  def handle_cast({:reassert, module_id}, state) do
    {:noreply, mark(state, module_id)}
  end

  def handle_cast({:brightness, module_id, level}, state) do
    send_brightness(module_id, level)
    {:noreply, state}
  end

  @impl true
  def handle_info(:flush, state) do
    Enum.each(state.dirty, fn module_id -> send_frame(module_id, state.frames[module_id]) end)
    {:noreply, %{state | dirty: MapSet.new(), timer: nil}}
  end

  defp mark(state, module_id) do
    state = %{state | dirty: MapSet.put(state.dirty, module_id)}

    case state.timer do
      nil -> %{state | timer: Process.send_after(self(), :flush, @flush_ms)}
      _pending -> state
    end
  end

  defp send_frame(module_id, %Frame{} = frame) do
    %{codec: codec} = @boards[module_id]
    Link.send_command(module_id, codec.set_leds(Frame.to_binary(frame)))
  end

  defp send_brightness(module_id, level) do
    case @boards[module_id] do
      %{codec: codec, brightness: true} ->
        Link.send_command(module_id, codec.set_brightness(level))

      _not_dimmable ->
        :ok
    end
  end

  @spec full_brightness() :: 0..255
  def full_brightness, do: @full_brightness
end
