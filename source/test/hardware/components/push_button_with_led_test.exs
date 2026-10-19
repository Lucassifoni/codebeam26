defmodule Hardware.Components.PushButtonWithLedTest do
  use ExUnit.Case, async: false

  alias Bbparty.Bus.LedShadow
  alias Bbparty.Bus.LedShadow.Frame
  import Phoenix.LiveViewTest

  alias Hardware.Components.PushButtonWithLed, as: Key

  defp key(opts \\ []),
    do: Key.new(Keyword.merge([action: "align_left", module: 2, led: 3], opts))

  describe "pressing" do
    test "emits what the key is, both edges" do
      assert {:ok, %Key{pushed: true}, [{:key_down, meaning}]} =
               Key.handle_event(key(), :key_down, nil)

      assert meaning.action == "align_left"

      assert {:ok, %Key{pushed: false}, [{:key_up, _}]} =
               Key.handle_event(key(), :key_up, nil)
    end

    test "an unassigned key says nothing" do
      blank = key(action: nil)

      assert {:ok, %Key{pushed: true}, []} = Key.handle_event(blank, :key_down, nil)
    end

    test "does not light the key" do
      {:ok, pressed, _} = Key.handle_event(key(), :key_down, nil)

      refute pressed.lit
    end
  end

  describe "the lamp" do
    test "is set by the fold's projection" do
      assert {:ok, %Key{lit: true}} = Key.handle_event(key(), :set_lit, true)
    end

    test "ignores anything that is not on or off" do
      assert {:ok, %Key{lit: false}} = Key.handle_event(key(), :set_lit, "yes")
    end
  end

  describe "a board's committed state" do
    test "moves the key without pretending it was pressed" do
      assert {:ok, %Key{pushed: true}, []} = Key.handle_event(key(), :set_pushed, true)
    end
  end

  describe "action_binding/1" do
    test "addresses the key by what it selects" do
      assert Key.action_binding(key()) == {:action, :align_left}
      assert Key.action_binding(key(action: "source_numbers")) == {:action, :source_numbers}
    end

    test "a key with no action, or a misspelled one, is addressed by nothing" do
      assert Key.action_binding(key(action: nil)) == nil
      assert Key.action_binding(key(action: "align_lefft")) == nil
    end
  end

  describe "the key on the canvas" do
    defp cap(opts), do: render_component(&Key.Display.render/1, id: :button_3, data: key(opts))

    test "shows the channel that lights it, under what it does" do
      html = cap(led: 5)

      assert html =~ "align left"
      assert html =~ "led 5"
    end

    test "a lamp bound to nothing says so" do
      assert cap(led: nil) =~ "led ?"
    end

    test "an unassigned key shows it has no meaning yet" do
      assert cap(action: nil, char: nil) =~ "—"
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

    test "a lit key writes its channel into its board's picture" do
      Key.handle_transition(key(), %{key() | lit: true}, [])

      assert Frame.lit?(LedShadow.frame(2), 3)
    end

    test "and darkening clears it" do
      Key.handle_transition(key(), %{key() | lit: true}, [])
      Key.handle_transition(%{key() | lit: true}, key(), [])

      refute Frame.lit?(LedShadow.frame(2), 3)
    end

    test "an unchanged value is still asserted" do
      lit = %{key() | lit: true}
      Key.handle_transition(lit, lit, [])

      assert Frame.lit?(LedShadow.frame(2), 3)
    end

    test "an unbound key drives nothing" do
      virtual = key(module: nil, led: nil)

      assert Key.handle_transition(virtual, %{virtual | lit: true}, []) == :ok
      assert LedShadow.frame(2) == Frame.new(8)
    end
  end
end
