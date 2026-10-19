defmodule Bbparty.Bus.Module4Dispatcher do
  use GenServer
  require Logger

  alias Bbparty.Bus.{Link, Module4}
  alias Bbparty.Layout
  alias Bbparty.TrackballPanel
  alias Hardware.Components.{PushButton, Trackball}
  alias Hardware.PhysicalComponent

  @module_id 0x04
  @topic "bus:module4"

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def topic, do: @topic
  def subscribe, do: Phoenix.PubSub.subscribe(Bbparty.PubSub, @topic)

  def unsubscribe, do: Phoenix.PubSub.unsubscribe(Bbparty.PubSub, @topic)

  @impl true
  def init(_) do
    Link.subscribe_frames()
    {:ok, %{buttons: 0}}
  end

  @impl true
  def handle_info({:frame, @module_id, <<0x01>>}, state) do
    broadcast({:hello})
    {:noreply, %{state | buttons: 0}}
  end

  def handle_info({:frame, @module_id, body}, state) do
    case Module4.decode(body) do
      {:ok, event} -> {:noreply, handle_event(event, state)}
      :error -> {:noreply, state}
    end
  end

  def handle_info({:frame, _module_id, _body}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  defp handle_event({:buttons, bits} = event, state) do
    broadcast(event)

    state.buttons
    |> TrackballPanel.transitions(bits)
    |> Enum.each(&deliver_button/1)

    %{state | buttons: bits}
  end

  defp handle_event({:activity, count} = event, state) do
    broadcast(event)
    deliver_activity(count)
    state
  end

  defp handle_event(event, state) do
    broadcast(event)
    state
  end

  defp broadcast(event), do: Phoenix.PubSub.broadcast(Bbparty.PubSub, @topic, {:module4, event})

  defp deliver_button({index, pressed?}) do
    id = String.to_atom(TrackballPanel.button_id(index))
    event = if pressed?, do: :key_down, else: :key_up

    case PhysicalComponent.running?(id) do
      true -> PhysicalComponent.handle_event(id, event, nil)
      false -> register_button(id, index, pressed?, event)
    end
  end

  defp register_button(_id, _index, false, _event), do: :ok

  defp register_button(id, index, true, event) do
    register(id, PushButton, %{}, TrackballPanel.button_default_position(index), event, nil)
  end

  defp deliver_activity(count) do
    case Registry.lookup(Bbparty.BindingsRegistry, {:trackball, @module_id}) do
      [{_pid, id} | _] ->
        PhysicalComponent.handle_event(id, :activity, count)

      [] ->
        register(
          String.to_atom(TrackballPanel.trackball_id()),
          Trackball,
          %{module: @module_id},
          TrackballPanel.trackball_default_position(),
          :activity,
          count
        )
    end
  end

  defp register(id, module, attrs, position, event, payload) do
    case Layout.autoregister?() do
      false ->
        :ok

      true ->
        case Layout.create_component(id, module, attrs, position) do
          {:ok, _inserted} -> start_and_deliver(id, event, payload)
          {:error, _changeset} -> :ok
        end
    end
  end

  defp start_and_deliver(id, event, payload) do
    Logger.info("module_4: registered #{id}")
    PhysicalComponent.start(id, Layout.get_component(id))
    Phoenix.PubSub.broadcast(Bbparty.PubSub, "components", {:component_registered, id})
    PhysicalComponent.handle_event(id, event, payload)
  end
end
