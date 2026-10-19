defmodule Bbparty.Bus.Module7Dispatcher do
  use GenServer
  require Logger

  alias Bbparty.Bus.{LedShadow, Link, Module7}
  alias Bbparty.Layout
  alias Bbparty.SwitchPanel
  alias Hardware.Components.SwitchWithTwoLeds
  alias Hardware.PhysicalComponent

  @module_id 0x07
  @topic "bus:module7"

  @resync_debounce_ms 500

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def topic, do: @topic
  def subscribe, do: Phoenix.PubSub.subscribe(Bbparty.PubSub, @topic)

  def unsubscribe, do: Phoenix.PubSub.unsubscribe(Bbparty.PubSub, @topic)

  @spec autoregister?() :: boolean()
  defdelegate autoregister?(), to: Layout

  @spec reset_warnings() :: :ok
  def reset_warnings, do: GenServer.cast(__MODULE__, :reset_warnings)

  @spec request_sync() :: :ok
  def request_sync, do: Link.send_command(@module_id, Module7.request_sync())

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

    if state[:resync_timer], do: Process.cancel_timer(state.resync_timer)

    {:noreply,
     state
     |> Map.put(:warned, MapSet.new())
     |> Map.put(:resync_timer, Process.send_after(self(), :resync, @resync_debounce_ms))}
  end

  def handle_info(:resync, state) do
    Bbparty.RenderStateServer.sync()
    LedShadow.reassert(@module_id)
    request_sync()
    {:noreply, Map.delete(state, :resync_timer)}
  end

  def handle_info({:frame, @module_id, body}, state) do
    case Module7.decode(body) do
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

  defp handle_event({:snapshot, bits} = event, state) do
    broadcast(event)
    apply_snapshot(bits)
    state
  end

  defp handle_event(event, state) do
    broadcast(event)
    state
  end

  defp broadcast(event), do: Phoenix.PubSub.broadcast(Bbparty.PubSub, @topic, {:module7, event})

  defp apply_snapshot(bits) do
    for drive <- 0..(SwitchPanel.drives() - 1),
        sense <- 0..(SwitchPanel.senses() - 1),
        id = String.to_atom(SwitchPanel.switch_id(drive, sense)),
        PhysicalComponent.running?(id) do
      PhysicalComponent.handle_event(id, :set_position, SwitchPanel.pressed?(bits, drive, sense))
    end

    :ok
  end

  defp route(drive, sense, pressed, state) do
    case SwitchPanel.valid_address?(drive, sense) do
      true ->
        deliver(String.to_atom(SwitchPanel.switch_id(drive, sense)), drive, sense, pressed)
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
        Logger.warning("module_7: #{SwitchPanel.describe_address(drive, sense)}")
        %{state | warned: MapSet.put(warned, {drive, sense})}
    end
  end

  defp deliver(id, drive, sense, pressed) do
    case PhysicalComponent.running?(id) do
      true -> PhysicalComponent.handle_event(id, event_name(pressed), nil)
      false -> register_then_deliver(id, drive, sense, pressed)
    end
  end

  defp register_then_deliver(id, drive, sense, pressed) do
    case autoregister?() do
      true -> register(id, drive, sense, pressed)
      false -> :ok
    end
  end

  defp register(id, drive, sense, pressed) do
    attrs = %{module: @module_id}
    position = SwitchPanel.default_position(drive, sense)

    case Layout.create_component(id, SwitchWithTwoLeds, attrs, position) do
      {:ok, _inserted} -> start_and_deliver(id, pressed)
      {:error, _changeset} -> :ok
    end
  end

  defp start_and_deliver(id, pressed) do
    Logger.info("module_7: registered switch #{id}")
    PhysicalComponent.start(id, Layout.get_component(id))
    Phoenix.PubSub.broadcast(Bbparty.PubSub, "components", {:component_registered, id})

    Bbparty.RenderStateServer.sync()

    PhysicalComponent.handle_event(id, event_name(pressed), nil)
  end

  defp event_name(true), do: :key_down
  defp event_name(false), do: :key_up
end
