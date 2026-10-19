defmodule Bbparty.Bus.Module2Dispatcher do
  use GenServer
  require Logger
  import Bitwise

  alias Bbparty.Bus.{LedShadow, Link, Module2}
  alias Bbparty.Layout
  alias Hardware.Components.PushButtonWithLed
  alias Hardware.PhysicalComponent

  @module_id 0x02
  @topic "bus:module2"

  @key_prefix "button_"
  @tag_topic "bus:module2:tags"
  @tag_events [:tag_read, :tag_gone, :write_result]

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def topic, do: @topic
  def subscribe, do: Phoenix.PubSub.subscribe(Bbparty.PubSub, @topic)
  def subscribe_tags, do: Phoenix.PubSub.subscribe(Bbparty.PubSub, @tag_topic)

  @spec key_id(0..255) :: String.t()
  def key_id(index), do: "#{@key_prefix}#{index}"

  @spec key_index(String.t() | atom()) :: {:ok, 0..255} | :error
  def key_index(id) when is_atom(id), do: key_index(Atom.to_string(id))

  def key_index(@key_prefix <> digits) do
    case Integer.parse(digits) do
      {index, ""} when index in 0..255 -> {:ok, index}
      _ -> :error
    end
  end

  def key_index(_id), do: :error

  @impl true
  def init(_) do
    Link.subscribe_frames()
    {:ok, %{}}
  end

  @impl true
  def handle_info({:frame, @module_id, <<0x01>>}, state) do
    broadcast({:hello})
    if state[:resync_timer], do: Process.cancel_timer(state.resync_timer)
    {:noreply, Map.put(state, :resync_timer, Process.send_after(self(), :resync, 500))}
  end

  def handle_info(:resync, state) do
    Bbparty.RenderStateServer.sync()
    LedShadow.set_brightness(@module_id, LedShadow.full_brightness())
    LedShadow.reassert(@module_id)
    Link.send_command(@module_id, Module2.request_sync())
    {:noreply, Map.delete(state, :resync_timer)}
  end

  def handle_info({:frame, @module_id, body}, state) do
    case Module2.decode(body) do
      {:ok, event} -> broadcast(event)
      :error -> :ok
    end

    {:noreply, state}
  end

  def handle_info({:frame, _module_id, _body}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(Bbparty.PubSub, @topic, {:module2, event})

    if is_tuple(event) and elem(event, 0) in @tag_events do
      Phoenix.PubSub.broadcast(Bbparty.PubSub, @tag_topic, {:module2, event})
    end

    route(event)
  end

  defp route({:axes, axes}) do
    axes
    |> Tuple.to_list()
    |> Enum.with_index()
    |> Enum.each(fn {value, axis} ->
      case Registry.lookup(Bbparty.BindingsRegistry, {:axis, @module_id, axis}) do
        [{_pid, id} | _] -> Hardware.PhysicalComponent.feed_input(id, :axis, value)
        [] -> :ok
      end
    end)
  end

  defp route({:key_event, index, pressed}) do
    deliver(String.to_atom(key_id(index)), pressed)
  end

  defp route({:snapshot, bits}) do
    for index <- 0..7, id = String.to_atom(key_id(index)), PhysicalComponent.running?(id) do
      PhysicalComponent.handle_event(id, :set_pushed, (bits >>> index &&& 1) == 1)
    end

    :ok
  end

  defp route({:tag_read, %{text: id}}) do
    case Registry.lookup(Bbparty.BindingsRegistry, {:nfc, @module_id}) do
      [{_pid, component} | _] -> Hardware.PhysicalComponent.feed_input(component, :tag, id)
      [] -> :ok
    end
  end

  defp route({:encoder, detents}) do
    case Registry.lookup(Bbparty.BindingsRegistry, {:encoder, @module_id}) do
      [{_pid, id} | _] -> Hardware.PhysicalComponent.feed_input(id, :detents, detents)
      [] -> :ok
    end
  end

  defp route({:fault, subsystem, index}) do
    Logger.warning("module_2 — #{Module2.fault_description(subsystem, index)}")
  end

  defp route(_event), do: :ok

  defp deliver(id, pressed) do
    case PhysicalComponent.running?(id) do
      true -> PhysicalComponent.handle_event(id, event_name(pressed), nil)
      false -> register_then_deliver(id, pressed)
    end
  end

  defp register_then_deliver(_id, false), do: :ok

  defp register_then_deliver(id, true) do
    case Layout.autoregister?() do
      true -> register(id, index_of(id))
      false -> :ok
    end
  end

  defp index_of(id) do
    {:ok, index} = key_index(id)
    index
  end

  defp default_position(index) do
    %{"x" => rem(index, 4) * 70, "y" => div(index, 4) * 70 + 700}
  end

  defp register(id, index) do
    attrs = %{module: @module_id}

    case Layout.create_component(id, PushButtonWithLed, attrs, default_position(index)) do
      {:ok, _inserted} ->
        Logger.info("module_2: registered key #{id}")
        PhysicalComponent.start(id, Layout.get_component(id))
        Phoenix.PubSub.broadcast(Bbparty.PubSub, "components", {:component_registered, id})
        PhysicalComponent.handle_event(id, :key_down, nil)

      {:error, _changeset} ->
        :ok
    end
  end

  defp event_name(true), do: :key_down
  defp event_name(false), do: :key_up
end
