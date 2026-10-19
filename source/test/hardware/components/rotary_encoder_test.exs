defmodule Hardware.Components.RotaryEncoderTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Hardware.Components.RotaryEncoder

  defp turn(state, detents), do: RotaryEncoder.handle_event(state, :turn, detents)

  describe "turning" do
    test "a detent is a word" do
      assert {:ok, _state, [{:nudge_quantity, 1}]} = turn(RotaryEncoder.new([]), 1)
    end

    test "the other way takes words back" do
      assert {:ok, _state, [{:nudge_quantity, -3}]} = turn(RotaryEncoder.new([]), -3)
    end

    test "chars_per_detent scales the nudge" do
      state = RotaryEncoder.new(chars_per_detent: 5)

      assert {:ok, _state, [{:nudge_quantity, 10}]} = turn(state, 2)
    end

    test "a fractional turn is rounded" do
      assert {:ok, _state, [{:nudge_quantity, 2}]} = turn(RotaryEncoder.new([]), 1.6)
    end

    test "a turn too small to be a word emits nothing" do
      assert {:ok, %RotaryEncoder{}} = turn(RotaryEncoder.new([]), 0)
      assert {:ok, %RotaryEncoder{}} = turn(RotaryEncoder.new([]), 0.2)
    end

    test "does not move the mirrored quantity" do
      {:ok, state, _emits} = turn(RotaryEncoder.new([]), 4)

      assert state.quantity == 0
    end
  end

  describe "a knob wired backwards" do
    defp flipped(attrs \\ []), do: RotaryEncoder.new([invert: true] ++ attrs)

    defp detents(state, count), do: RotaryEncoder.handle_event(state, :detents, count)

    test "the board's detents write the other way" do
      assert {:ok, _state, [{:nudge_quantity, -1}]} = detents(flipped(), 1)
      assert {:ok, _state, [{:nudge_quantity, 3}]} = detents(flipped(), -3)
    end

    test "chars_per_detent still scales the nudge" do
      assert {:ok, _state, [{:nudge_quantity, -10}]} = detents(flipped(chars_per_detent: 5), 2)
    end

    test "the on-screen knob is untouched" do
      assert {:ok, _state, [{:nudge_quantity, 1}]} = turn(flipped(), 1)
    end
  end

  describe "a knob wired the usual way" do
    test "the board's detents and a virtual turn agree" do
      assert {:ok, _state, [{:nudge_quantity, 1}]} =
               RotaryEncoder.handle_event(RotaryEncoder.new([]), :detents, 1)
    end

    test "is the default, and a missing attr does not change it" do
      refute RotaryEncoder.new([]).invert
      refute RotaryEncoder.new(invert: nil).invert
    end
  end

  describe "the mirrored quantity" do
    test "follows what the fold committed" do
      {:ok, state} = RotaryEncoder.handle_event(RotaryEncoder.new([]), :set_quantity, 12)

      assert state.quantity == 12
    end

    test "ignores a quantity that is not a count" do
      {:ok, state} = RotaryEncoder.handle_event(RotaryEncoder.new([]), :set_quantity, "12")

      assert state.quantity == 0
    end
  end

  describe "input_binding/1" do
    test "addresses the board it is wired to" do
      assert RotaryEncoder.input_binding(RotaryEncoder.new(module: 2)) == {:encoder, 2}
    end

    test "an unbound encoder is virtual only" do
      assert RotaryEncoder.input_binding(RotaryEncoder.new([])) == nil
    end
  end

  describe "field_binding/1" do
    test "shows the core's text quantity, wired or not" do
      assert RotaryEncoder.field_binding(RotaryEncoder.new(module: 2)) == {:field, :text_quantity}
      assert RotaryEncoder.field_binding(RotaryEncoder.new([])) == {:field, :text_quantity}
    end
  end

  describe "the virtual knob" do
    defp dial(quantity) do
      render_component(&RotaryEncoder.Display.render/1,
        id: :text_quantity,
        attrs: %{},
        data: %RotaryEncoder{quantity: quantity}
      )
    end

    test "shows the committed word count" do
      assert dial(17) =~ "17"
    end

    test "the pointer steps round with each word" do
      refute dial(1) == dial(2)
      assert dial(0) =~ "rotate(0.0 20 20)"
    end

    test "the pointer wraps rather than crawling" do
      turn = RotaryEncoder.Display.detents_per_turn()

      assert dial(turn) =~ "rotate(0.0 20 20)", "a full turn brings the pointer home"
      assert dial(turn + 1) =~ "rotate(15.0 20 20)"
      assert dial(1) =~ "rotate(15.0 20 20)", "one word past a turn points where one word did"
    end
  end
end
