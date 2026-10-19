defmodule Hardware.Components.SwitchWithTwoLedsTest do
  use ExUnit.Case, async: false

  alias Bbparty.Bus.LedShadow
  alias Bbparty.Bus.LedShadow.Frame
  import Phoenix.LiveViewTest

  alias Hardware.Components.SwitchWithTwoLeds, as: Switch

  @board 0x07

  defp switch(opts \\ []) do
    Switch.new(
      Keyword.merge(
        [feature: "liga", mode: "toggle", module: @board, status_led: 3, available_led: 35],
        opts
      )
    )
  end

  describe "commissioning attrs" do
    test "mode arrives as a string from the editor and the database" do
      assert %Switch{mode: :toggle} = switch(mode: "toggle")
      assert %Switch{mode: :position} = switch(mode: "position")
    end

    test "mode may also be given as an atom" do
      assert %Switch{mode: :position} = switch(mode: :position)
    end

    test "an unset or unrecognised mode is a toggle" do
      assert %Switch{mode: :toggle} = switch(mode: nil)
      assert %Switch{mode: :toggle} = switch(mode: "latching")
    end

    test "a switch starts with nothing claimed about it" do
      assert %Switch{position: false, active: false, available: false} = switch()
    end

    test "the LED channels are attrs, filled by the claim walk" do
      assert %Switch{status_led: nil, available_led: nil} =
               switch(status_led: nil, available_led: nil)
    end
  end

  describe "throwing a toggle switch" do
    test "either edge flips the feature" do
      assert {:ok, %Switch{position: true}, [{:toggle_feature, "liga"}]} =
               Switch.handle_event(switch(), :key_down, nil)

      assert {:ok, %Switch{position: false}, [{:toggle_feature, "liga"}]} =
               Switch.handle_event(%{switch() | position: true}, :key_up, nil)
    end

    test "a switch with no feature moves but says nothing" do
      assert {:ok, %Switch{position: true}, []} =
               Switch.handle_event(switch(feature: nil), :key_down, nil)
    end
  end

  describe "throwing a position switch" do
    test "the position is the value" do
      assert {:ok, %Switch{position: true}, [{:set_feature, {"liga", true}}]} =
               Switch.handle_event(switch(mode: "position"), :key_down, nil)

      assert {:ok, %Switch{position: false}, [{:set_feature, {"liga", false}}]} =
               Switch.handle_event(
                 %{switch(mode: "position") | position: true},
                 :key_up,
                 nil
               )
    end
  end

  describe "a board snapshot" do
    test "never becomes a toggle" do
      assert {:ok, %Switch{position: true}, []} =
               Switch.handle_event(switch(), :set_position, true)
    end

    test "sets the feature on a position switch, idempotently" do
      position = switch(mode: "position")

      assert {:ok, %Switch{position: true}, [{:set_feature, {"liga", true}}]} =
               Switch.handle_event(position, :set_position, true)

      assert {:ok, %Switch{position: true}, [{:set_feature, {"liga", true}}]} =
               Switch.handle_event(%{position | position: true}, :set_position, true)
    end

    test "an unbound position switch says nothing" do
      assert {:ok, %Switch{position: true}, []} =
               Switch.handle_event(switch(mode: "position", feature: nil), :set_position, true)
    end
  end

  describe "what the fold says back" do
    test "active and available arrive as state, and emit nothing" do
      assert {:ok, %Switch{active: true}} = Switch.handle_event(switch(), :set_active, true)
      assert {:ok, %Switch{available: true}} = Switch.handle_event(switch(), :set_available, true)
    end

    test "an unknown event leaves the switch alone" do
      assert {:ok, %Switch{}} = Switch.handle_event(switch(), :set_lit, true)
    end
  end

  describe "feature_binding/1" do
    test "a switch is addressed by what it carries" do
      assert Switch.feature_binding(switch()) == {:feature, "liga"}
    end

    test "an uncommissioned switch carries nothing" do
      assert Switch.feature_binding(switch(feature: nil)) == nil
    end
  end

  describe "the lamp table" do
    test "all four combinations of active and available" do
      lamps = fn active, available ->
        state = %{switch() | active: active, available: available}
        {Switch.status_lit?(state), Switch.availability_lit?(state)}
      end

      assert lamps.(true, true) == {true, true}
      assert lamps.(false, true) == {false, true}
      assert lamps.(true, false) == {false, false}
      assert lamps.(false, false) == {false, false}
    end
  end

  describe "driving the panel" do
    setup do
      dark = fn ->
        :sys.replace_state(LedShadow, fn state ->
          frames =
            Map.new(LedShadow.boards(), fn {id, %{width: width}} -> {id, Frame.new(width)} end)

          %{state | frames: frames, dirty: MapSet.new()}
        end)
      end

      dark.()
      on_exit(dark)
      :ok
    end

    test "an active, available feature lights both channels" do
      lit = %{switch() | active: true, available: true}
      Switch.handle_transition(switch(), lit, [])

      assert Frame.lit?(LedShadow.frame(@board), 3)
      assert Frame.lit?(LedShadow.frame(@board), 35)
    end

    test "an inactive, available feature lights the red channel alone" do
      Switch.handle_transition(switch(), %{switch() | available: true}, [])

      refute Frame.lit?(LedShadow.frame(@board), 3)
      assert Frame.lit?(LedShadow.frame(@board), 35)
    end

    test "a font without the feature leaves both channels dark" do
      Switch.handle_transition(switch(), %{switch() | active: true}, [])

      refute Frame.lit?(LedShadow.frame(@board), 3)
      refute Frame.lit?(LedShadow.frame(@board), 35)
    end

    test "both channels are written on every transition, not only the one that changed" do
      lit = %{switch() | active: true, available: true}
      Switch.handle_transition(switch(), lit, [])
      Switch.handle_transition(lit, %{lit | available: false}, [])

      refute Frame.lit?(LedShadow.frame(@board), 3)
      refute Frame.lit?(LedShadow.frame(@board), 35)
    end

    test "an unchanged state is still asserted" do
      lit = %{switch() | active: true, available: true}
      Switch.handle_transition(lit, lit, [])

      assert Frame.lit?(LedShadow.frame(@board), 3)
    end

    test "a switch with no claimed channels drives nothing" do
      virtual = switch(module: nil, status_led: nil, available_led: nil)

      assert Switch.handle_transition(virtual, %{virtual | active: true}, []) == :ok
      assert LedShadow.frame(@board) == Frame.new(64)
    end

    test "a half-claimed switch drives the channel it has" do
      half = switch(available_led: nil)
      Switch.handle_transition(half, %{half | active: true, available: true}, [])

      assert Frame.lit?(LedShadow.frame(@board), 3)
    end
  end

  describe "the display" do
    defp face(opts \\ []),
      do: render_component(&Switch.Display.render/1, id: :switch_0_0, data: switch(opts))

    test "shows the feature it carries" do
      assert face() =~ "liga"
    end

    test "an uncommissioned switch says so" do
      assert face(feature: nil) =~ "—"
    end

    test "the red lamp is lit when the font carries the feature" do
      assert render_component(&Switch.Display.render/1,
               id: :switch_0_0,
               data: %{switch() | available: true}
             ) =~ "bg-red-400"

      refute face() =~ "bg-red-400"
    end

    test "shows both claimed channels, and flags an unclaimed one" do
      assert face() =~ "3/35"
      assert face(available_led: nil) =~ "3/?"
    end

    test "clicking sends the edge the position implies" do
      assert face() =~ ~s(phx-value-event="key_down")
    end

    test "the event is a string, not an atom" do
      assert face() =~ ~s(phx-value-event=")
      refute face() =~ "phx-value-event=\"Elixir."
    end
  end
end
