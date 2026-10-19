defmodule Hardware.PhysicalComponent do
  require Logger
  alias Bbparty.Layout.ComponentInstance

  use GenServer

  def init({identifier, state}) do
    Process.put(:component_id, identifier)
    register_binding(identifier, state)
    {:ok, state}
  end

  def start(identifier, component) do
    DynamicSupervisor.start_child(
      Bbparty.ComponentsSupervisor,
      {__MODULE__, {identifier, component}}
    )
  end

  def stop(identifier) do
    case GenServer.whereis(via(identifier)) do
      nil -> :ok
      pid -> DynamicSupervisor.terminate_child(Bbparty.ComponentsSupervisor, pid)
    end
  end

  def start_link({identifier, %ComponentInstance{module: module, attrs: args}}) do
    result =
      GenServer.start_link(__MODULE__, {identifier, apply(module, :new, [Map.to_list(args)])},
        name: via(identifier)
      )

    Logger.info("Started physical component #{identifier} via #{inspect(via(identifier))}")
    result
  end

  def via(identifier) do
    {:via, Registry, {Bbparty.ComponentsRegistry, name(identifier)}}
  end

  def name(identifier) do
    :"PhysicalComponent_#{identifier}"
  end

  def query_state(identifier) do
    GenServer.call(via(identifier), :query_state)
  end

  @spec running?(String.t() | atom()) :: boolean()
  def running?(identifier), do: GenServer.whereis(via(identifier)) != nil

  def handle_event(id, event, payload) do
    GenServer.cast(via(id), {:handle_event, id, event, payload})
  end

  def command({kind, _what} = key, {event, payload}) when kind in [:action, :feature, :field] do
    Bbparty.ActionsRegistry
    |> Registry.lookup(key)
    |> Enum.each(fn {_pid, id} -> command(id, {event, payload}) end)
  end

  def command(target, {event, payload}) do
    GenServer.cast(via(target), {:handle_command, target, event, payload})
  end

  def feed_input(id, event, payload) do
    GenServer.cast(via(id), {:input, id, event, payload})
  end

  def run_effect(target, {effect, payload, old_state, new_state}) do
    GenServer.cast(via(target), {:run_effect, target, effect, payload, old_state, new_state})
  end

  def reconfigure(identifier, %ComponentInstance{module: module, attrs: attrs}) do
    GenServer.cast(via(identifier), {:reconfigure, module, attrs})
  end

  def handle_call(:query_state, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:run_effect, target, effect, payload, old_state, new_state}, state) do
    perform_effect(state.__struct__, target, effect, payload, old_state, new_state)
    {:noreply, state}
  end

  def handle_cast({:reconfigure, module, attrs}, _state) do
    new_state = apply(module, :new, [Map.to_list(attrs)])

    for key <- Registry.keys(Bbparty.BindingsRegistry, self()) do
      Registry.unregister(Bbparty.BindingsRegistry, key)
    end

    for key <- Registry.keys(Bbparty.ActionsRegistry, self()) do
      Registry.unregister(Bbparty.ActionsRegistry, key)
    end

    register_binding(Process.get(:component_id), new_state)
    {:noreply, new_state}
  end

  def handle_cast({:input, id, event, payload}, state) do
    step_input(id, event, payload, state)
  end

  def handle_cast({:handle_event, id, event, payload}, state) do
    step(id, event, payload, state, :world)
  end

  def handle_cast({:handle_command, id, event, payload}, state) do
    step(id, event, payload, state, :system)
  end

  defp perform_effect(module, id, effect, payload, old_state, new_state) do
    if function_exported?(module, :effects, 0) and effect in module.effects() do
      module.handle_effect(id, effect, payload, old_state, new_state)
    end
  end

  defp maybe_output(module, old_state, new_state) do
    if function_exported?(module, :handle_transition, 3) do
      module.handle_transition(old_state, new_state, [])
    end

    :ok
  end

  defp step(id, event, payload, state, origin) do
    module = state.__struct__

    if event in module.events() do
      case module.handle_event(state, event, payload) do
        {:ok, new_state} ->
          broadcast_changed(id, new_state)
          publish(id, [{event, payload}], origin)
          maybe_output(module, state, new_state)
          {:noreply, new_state}

        {:ok, new_state, emits} ->
          broadcast_changed(id, new_state)
          publish(id, emits, origin)
          maybe_output(module, state, new_state)
          {:noreply, new_state}

        {:error, _e} ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  defp step_input(id, event, payload, state) do
    module = state.__struct__

    if event in module.events() do
      case module.handle_event(state, event, payload) do
        {:ok, new_state, emits} ->
          broadcast_emits(id, emits)
          {:noreply, new_state}

        {:ok, new_state} ->
          {:noreply, new_state}

        {:error, _e} ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  defp broadcast_changed(id, new_state) do
    Phoenix.PubSub.broadcast(Bbparty.PubSub, "components", {:component_changed, id, new_state})
  end

  defp publish(id, emits, :world), do: broadcast_emits(id, emits)
  defp publish(_id, _emits, :system), do: :ok

  defp broadcast_emits(id, emits) do
    Enum.each(emits, fn {event, payload} ->
      Phoenix.PubSub.broadcast(Bbparty.PubSub, "events", {:component_event, id, event, payload})
    end)
  end

  defp register_binding(id, state) do
    module = state.__struct__

    register_input(module, state, id)
    register_action(module, state, id)
    register_feature(module, state, id)
    register_field(module, state, id)

    :ok
  end

  defp register_input(module, state, id) do
    with true <- function_exported?(module, :input_binding, 1),
         key when not is_nil(key) <- module.input_binding(state) do
      case Registry.register(Bbparty.BindingsRegistry, key, id) do
        {:ok, _pid} ->
          :ok

        {:error, {:already_registered, _pid}} ->
          [{_pid, holder}] = Registry.lookup(Bbparty.BindingsRegistry, key)

          Logger.warning(
            "#{id} wants #{inspect(key)}, which #{holder} already holds — #{id} will receive nothing"
          )
      end
    end
  end

  defp register_action(module, state, id),
    do: register_target(module, :action_binding, state, id)

  defp register_feature(module, state, id),
    do: register_target(module, :feature_binding, state, id)

  defp register_field(module, state, id),
    do: register_target(module, :field_binding, state, id)

  defp register_target(module, callback, state, id) do
    with true <- function_exported?(module, callback, 1),
         key when not is_nil(key) <- apply(module, callback, [state]) do
      Registry.register(Bbparty.ActionsRegistry, key, id)
    end
  end
end
