defmodule Bbparty.RenderStateServer do
  use GenServer

  alias Bbparty.Bus.Link
  alias Bbparty.RenderState
  alias Bbparty.RenderState.Fit
  alias Bbparty.RenderState.Projections
  alias Bbparty.RenderState.TextLayout
  alias Bbparty.RenderState.TextToWrite

  def init(arg), do: {:ok, arg}

  def start_link(_) do
    {:ok, pid} =
      GenServer.start_link(
        __MODULE__,
        %{render: RenderState.new(), layout: TextLayout.empty(), fit: Fit.empty()},
        name: __MODULE__
      )

    send(pid, :setup_subscriptions)
    {:ok, pid}
  end

  def get_state(), do: GenServer.call(__MODULE__, :get_state)

  @spec put_layout(TextLayout.t()) :: :ok
  def put_layout(%TextLayout{} = layout), do: GenServer.cast(__MODULE__, {:put_layout, layout})

  @spec get_layout() :: TextLayout.t()
  def get_layout(), do: GenServer.call(__MODULE__, :get_layout)

  @spec put_fit(Fit.t()) :: :ok
  def put_fit(%Fit{} = fit), do: GenServer.cast(__MODULE__, {:put_fit, fit})

  @spec get_fit() :: Fit.t()
  def get_fit(), do: GenServer.call(__MODULE__, :get_fit)

  def sync(), do: GenServer.cast(__MODULE__, :sync)

  def handle_call(:get_state, _, state), do: {:reply, state.render, state}
  def handle_call(:get_layout, _, state), do: {:reply, state.layout, state}
  def handle_call(:get_fit, _, state), do: {:reply, state.fit, state}

  def handle_cast(:sync, state) do
    dispatch_commands(Projections.sync(state.render))
    {:noreply, state}
  end

  def handle_cast({:put_layout, layout}, state), do: {:noreply, %{state | layout: layout}}

  def handle_cast({:put_fit, pushed}, state) do
    case Fit.accept(state.fit, pushed, RenderState.layout_fingerprint(state.render)) do
      {:ok, fit} ->
        Phoenix.PubSub.broadcast(Bbparty.PubSub, "render", {:fit, fit})
        {:noreply, %{state | fit: fit}}

      :ignore ->
        {:noreply, state}
    end
  end

  def handle_info(:setup_subscriptions, state) do
    Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")
    {:noreply, state}
  end

  def handle_info({:component_event, id, event, payload}, state) do
    {render, commands, effects} =
      RenderState.apply(state.render, {id, event, fold_payload(event, payload)}, state.layout)

    dispatch_commands(commands)

    Enum.each(effects, &run_effect(&1, payload, state.render, render))

    if render != state.render do
      Phoenix.PubSub.broadcast(Bbparty.PubSub, "render", {:new_state, render})
    end

    {:noreply, %{state | render: render}}
  end

  defp fold_payload(:roll, _intensity), do: %{word: Enum.random(TextToWrite.roll_words())}

  defp fold_payload(event, payload) when event in [:key_down, :key_up] and is_map(payload),
    do: Map.put(payload, :at, System.monotonic_time(:millisecond))

  defp fold_payload(_event, payload), do: payload

  defp run_effect({:bus, :reboot_boards}, _payload, _old, _new), do: Link.reboot_all()

  defp run_effect({target, effect}, payload, old, new),
    do: Hardware.PhysicalComponent.run_effect(target, {effect, payload, old, new})

  defp dispatch_commands(commands) do
    Enum.each(commands, fn {target, command} ->
      Hardware.PhysicalComponent.command(target, command)
    end)
  end
end
