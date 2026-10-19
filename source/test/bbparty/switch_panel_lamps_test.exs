defmodule Bbparty.SwitchPanelLampsTest do
  use Bbparty.DataCase, async: false

  alias Bbparty.Bus.LedShadow
  alias Bbparty.Bus.LedShadow.Frame
  alias Bbparty.Layout
  alias Bbparty.RenderState
  alias Bbparty.RenderStateServer
  alias Hardware.Components.SwitchWithTwoLeds, as: Switch
  alias Hardware.PhysicalComponent

  @board 0x07

  @switches [
    {:switch_0_0, "liga", "toggle", 5, 37},
    {:switch_0_1, "dlig", "toggle", 0, 32},
    {:switch_3_0, "smcp", "position", 29, 61}
  ]

  @rich "Boogy Brut Bold"
  @bare "BBWB"

  setup do
    reset_render = fn ->
      :sys.replace_state(RenderStateServer, fn state ->
        %{state | render: RenderState.new()}
      end)
    end

    reset_render.()

    :sys.replace_state(LedShadow, fn state ->
      frames = Map.new(LedShadow.boards(), fn {id, %{width: w}} -> {id, Frame.new(w)} end)
      %{state | frames: frames, dirty: MapSet.new()}
    end)

    for {id, feature, mode, status, available} <- @switches do
      attrs = %{
        feature: feature,
        mode: mode,
        module: @board,
        status_led: status,
        available_led: available
      }

      {:ok, _} = Layout.create_component(id, Switch, attrs, %{"x" => 0, "y" => 0})
      {:ok, _} = PhysicalComponent.start(id, Layout.get_component(id))
    end

    RenderStateServer.sync()
    settle()

    on_exit(fn -> Enum.each(@switches, fn {id, _, _, _, _} -> PhysicalComponent.stop(id) end) end)
    on_exit(reset_render)

    :ok
  end

  defp settle do
    RenderStateServer.get_state()
    Enum.each(@switches, fn {id, _, _, _, _} -> PhysicalComponent.query_state(id) end)
  end

  defp throw_switch(id) do
    PhysicalComponent.handle_event(id, :key_down, nil)
    PhysicalComponent.query_state(id)
    settle()
  end

  defp fold_event(id, event, payload) do
    Phoenix.PubSub.broadcast(Bbparty.PubSub, "events", {:component_event, id, event, payload})
    settle()
  end

  defp select_font(font), do: fold_event(:tag_reader, :select_font, font)

  defp lamps(id) do
    state = PhysicalComponent.query_state(id)
    {Switch.status_lit?(state), Switch.availability_lit?(state)}
  end

  defp frame, do: LedShadow.frame(@board)

  describe "a switch thrown on the toggle grid" do
    test "lights its own status lamp and nobody else's" do
      select_font(@rich)
      throw_switch(:switch_0_0)

      assert lamps(:switch_0_0) == {true, true}
      assert lamps(:switch_0_1) == {false, true}
    end

    test "the lamp is a channel in the board's picture, on the claimed output" do
      select_font(@rich)
      throw_switch(:switch_0_0)

      assert Frame.lit?(frame(), 5)
      assert Frame.lit?(frame(), 37)
      refute Frame.lit?(frame(), 0)
    end

    test "throwing it again turns the feature off, and the lamp with it" do
      select_font(@rich)
      throw_switch(:switch_0_0)
      PhysicalComponent.handle_event(:switch_0_0, :key_up, nil)
      PhysicalComponent.query_state(:switch_0_0)
      settle()

      assert lamps(:switch_0_0) == {false, true}
      refute Frame.lit?(frame(), 5)
    end
  end

  describe "a font that does not carry the feature" do
    test "darkens every red lamp, and leaves the features active" do
      select_font(@rich)
      throw_switch(:switch_0_0)
      select_font(@bare)

      assert lamps(:switch_0_0) == {false, false}
      refute Frame.lit?(frame(), 37)
      refute Frame.lit?(frame(), 5)

      assert "liga" in RenderStateServer.get_state().cumulative_features
    end

    test "and the status lamp returns when a font that has it is selected" do
      select_font(@rich)
      throw_switch(:switch_0_0)
      select_font(@bare)
      select_font(@rich)

      assert lamps(:switch_0_0) == {true, true}
      assert Frame.lit?(frame(), 5)
      assert Frame.lit?(frame(), 37)
    end
  end

  describe "the value grid" do
    test "the position sets the feature, and the lamp follows the app" do
      select_font(@rich)
      throw_switch(:switch_3_0)

      assert "smcp" in RenderStateServer.get_state().cumulative_features
      assert Frame.lit?(frame(), 29)
    end
  end

  describe "RESET" do
    test "leaves a latching lever's feature and lamp on, and the font selected" do
      select_font(@rich)
      throw_switch(:switch_0_0)
      assert Frame.lit?(frame(), 5)

      fold_event(:some_key, :key_down, %{char: nil, shift: nil, action: "reset"})

      assert lamps(:switch_0_0) == {true, true}
      assert Frame.lit?(frame(), 5)
      assert Frame.lit?(frame(), 37)
      assert %Switch{position: true} = PhysicalComponent.query_state(:switch_0_0)
    end
  end
end
