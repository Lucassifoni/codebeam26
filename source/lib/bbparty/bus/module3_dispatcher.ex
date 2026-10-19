defmodule Bbparty.Bus.Module3Dispatcher do
  use GenServer
  require Logger

  alias Bbparty.Bus.{Link, Module3}
  alias Bbparty.Keyboard
  alias Bbparty.Layout
  alias Hardware.Components.PushButton
  alias Hardware.PhysicalComponent

  @module_id 0x03
  @topic "bus:module3"

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def topic, do: @topic
  def subscribe, do: Phoenix.PubSub.subscribe(Bbparty.PubSub, @topic)

  def unsubscribe, do: Phoenix.PubSub.unsubscribe(Bbparty.PubSub, @topic)

  @spec autoregister?() :: boolean()
  defdelegate autoregister?(), to: Layout

  @spec reset_warnings() :: :ok
  def reset_warnings, do: GenServer.cast(__MODULE__, :reset_warnings)

  @impl true
  def init(_) do
    Link.subscribe_frames()
    {:ok, %{warned: MapSet.new()}}
  end

  @impl true
  def handle_cast(:reset_warnings, state), do: {:noreply, %{state | warned: MapSet.new()}}

  @impl true
  def handle_info({:frame, @module_id, <<0x01>>}, state) do
    broadcast({:hello})
    {:noreply, %{state | warned: MapSet.new()}}
  end

  def handle_info({:frame, @module_id, body}, state) do
    case Module3.decode(body) do
      {:ok, event} -> {:noreply, handle_event(event, state)}
      :error -> {:noreply, state}
    end
  end

  def handle_info({:frame, _module_id, _body}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  defp handle_event({:key_event, drive, sense, pressed} = event, state) do
    broadcast(event)
    route(drive, sense, pressed, state)
  end

  defp handle_event(event, state) do
    broadcast(event)
    state
  end

  defp broadcast(event), do: Phoenix.PubSub.broadcast(Bbparty.PubSub, @topic, {:module3, event})

  defp route(drive, sense, pressed, state) do
    case Keyboard.valid_address?(drive, sense) do
      true ->
        deliver(String.to_atom(Keyboard.key_id(drive, sense)), drive, sense, pressed)
        state

      false ->
        warn_once(drive, sense, state)
    end
  end

  defp warn_once(drive, sense, %{warned: warned} = state) do
    case MapSet.member?(warned, {drive, sense}) do
      true ->
        state

      false ->
        Logger.warning("module_3: #{Keyboard.describe_address(drive, sense)}")
        %{state | warned: MapSet.put(warned, {drive, sense})}
    end
  end

  defp deliver(id, drive, sense, pressed) do
    case PhysicalComponent.running?(id) do
      true -> PhysicalComponent.handle_event(id, event_name(pressed), nil)
      false -> register_then_deliver(id, drive, sense, pressed)
    end
  end

  defp register_then_deliver(_id, _drive, _sense, false), do: :ok

  defp register_then_deliver(id, drive, sense, true) do
    case autoregister?() do
      true -> register(id, drive, sense)
      false -> :ok
    end
  end

  defp register(id, drive, sense) do
    attrs = %{char: Keyboard.default_char(drive, sense)}

    case Layout.create_component(id, PushButton, attrs, Keyboard.default_position(drive, sense)) do
      {:ok, _inserted} -> start_and_press(id)
      {:error, _changeset} -> :ok
    end
  end

  defp start_and_press(id) do
    Logger.info("module_3: registered key #{id}")
    PhysicalComponent.start(id, Layout.get_component(id))
    Phoenix.PubSub.broadcast(Bbparty.PubSub, "components", {:component_registered, id})
    PhysicalComponent.handle_event(id, :key_down, nil)
  end

  defp event_name(true), do: :key_down
  defp event_name(false), do: :key_up
end
