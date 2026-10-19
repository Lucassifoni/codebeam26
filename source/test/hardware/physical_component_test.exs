defmodule Hardware.PhysicalComponentTest do
  use ExUnit.Case, async: false

  alias Bbparty.Layout.ComponentInstance
  alias Hardware.PhysicalComponent

  defmodule Echo do
    @behaviour Hardware.Component

    defstruct pokes: 0, plain: 0

    @impl true
    def new(_opts), do: %__MODULE__{}

    @impl true
    def events(), do: [:poke, :plain]

    @impl true
    def handle_event(state, :poke, payload),
      do: {:ok, %{state | pokes: state.pokes + 1}, [{:echoed, payload}]}

    def handle_event(state, :plain, _payload), do: {:ok, %{state | plain: state.plain + 1}}
  end

  @id :physical_component_test_echo

  setup do
    {:ok, _pid} = PhysicalComponent.start(@id, %ComponentInstance{module: Echo, attrs: %{}})
    on_exit(fn -> PhysicalComponent.stop(@id) end)
    Phoenix.PubSub.subscribe(Bbparty.PubSub, "events")
    Phoenix.PubSub.subscribe(Bbparty.PubSub, "components")
    :ok
  end

  describe "an event from the world" do
    test "publishes the component's emits to the core" do
      PhysicalComponent.handle_event(@id, :poke, 7)

      assert_receive {:component_event, @id, :echoed, 7}
    end

    test "publishes the event itself when the component emits nothing explicit" do
      PhysicalComponent.handle_event(@id, :plain, 7)

      assert_receive {:component_event, @id, :plain, 7}
    end
  end

  describe "a command from the core" do
    test "updates the component without publishing its emits back to the core" do
      PhysicalComponent.command(@id, {:poke, 7})

      assert %Echo{pokes: 1} = PhysicalComponent.query_state(@id)
      assert_receive {:component_changed, @id, %Echo{pokes: 1}}
      refute_receive {:component_event, @id, _event, _payload}, 50
    end

    test "never echoes the command itself to the core" do
      PhysicalComponent.command(@id, {:plain, 7})

      assert %Echo{plain: 1} = PhysicalComponent.query_state(@id)
      refute_receive {:component_event, @id, _event, _payload}, 50
    end
  end
end
