defmodule Hardware.Components.JoystickTest do
  use ExUnit.Case, async: true

  alias Hardware.Components.Joystick

  defp jstick do
    Joystick.new(
      center: 3290,
      low: 300,
      high: 4090,
      deadzone: 120,
      smoothing: 1.0,
      sensitivity: 0.5,
      module: 2,
      axis: 0
    )
  end

  describe "new/1" do
    test "defaults are unbound, centred, full-range" do
      j = Joystick.new([])
      assert {j.module, j.axis} == {nil, nil}
      assert {j.center, j.low, j.high} == {2048, 0, 4095}
      assert j.ema == 2048.0
    end

    test "nil attrs fall back to defaults" do
      j = Joystick.new(low: nil, high: nil, sensitivity: nil)
      assert {j.low, j.high, j.sensitivity} == {0, 4095, 0.4}
    end

    test "is mounted the right way up unless told otherwise" do
      refute Joystick.new([]).invert
      refute Joystick.new(invert: nil).invert
      assert Joystick.new(invert: true).invert
    end
  end

  describe "input_binding/1" do
    test "bound returns the axis channel key" do
      assert Joystick.input_binding(Joystick.new(module: 2, axis: 1)) == {:axis, 2, 1}
    end

    test "unbound returns nil" do
      assert Joystick.input_binding(Joystick.new([])) == nil
    end
  end

  describe "normalize/2 — equal authority despite lopsided travel" do
    test "rest is zero" do
      assert Joystick.normalize(3290, jstick()) == 0.0
    end

    test "within the deadzone is zero" do
      assert Joystick.normalize(3350, jstick()) == 0.0
      assert Joystick.normalize(3200, jstick()) == 0.0
    end

    test "full up and full down are +/-1 even though the throws differ" do
      assert Joystick.normalize(4090, jstick()) == 1.0
      assert Joystick.normalize(300, jstick()) == -1.0
    end
  end

  describe "normalize/2 — a stick mounted upside down" do
    defp flipped, do: %{jstick() | invert: true}

    test "rest is still zero" do
      assert Joystick.normalize(3290, flipped()) == 0.0
    end

    test "full travel reads full the other way" do
      assert Joystick.normalize(4090, flipped()) == -1.0
      assert Joystick.normalize(300, flipped()) == 1.0
    end

    test "partial travel mirrors the uninverted reading" do
      raw = 3700
      assert Joystick.normalize(raw, flipped()) == -Joystick.normalize(raw, jstick())
    end
  end

  describe "handle_event :axis" do
    test "rest emits nothing" do
      assert {:ok, s, []} = Joystick.handle_event(jstick(), :axis, 3290)
      assert s.ema == 3290.0
    end

    test "full up and full down emit equal, opposite nudges" do
      assert {:ok, _s, [{:nudge, up}]} = Joystick.handle_event(jstick(), :axis, 4090)
      assert {:ok, _s, [{:nudge, down}]} = Joystick.handle_event(jstick(), :axis, 300)
      assert up == 50.0
      assert down == -50.0
    end
  end

  describe "handle_event :axis, inverted" do
    test "the nudges swap sign" do
      assert {:ok, _s, [{:nudge, -50.0}]} = Joystick.handle_event(flipped(), :axis, 4090)
      assert {:ok, _s, [{:nudge, 50.0}]} = Joystick.handle_event(flipped(), :axis, 300)
    end

    test "the on-screen stick is untouched" do
      assert {:ok, _s, [{:nudge, 50.0}]} = Joystick.handle_event(flipped(), :deflect, 100)
    end
  end

  describe "handle_event :deflect (virtual)" do
    test "full travel maps to the same nudge as full axis" do
      assert {:ok, _s, [{:nudge, 50.0}]} = Joystick.handle_event(jstick(), :deflect, 100)
      assert {:ok, _s, [{:nudge, -50.0}]} = Joystick.handle_event(jstick(), :deflect, -100)
    end

    test "partial travel scales linearly" do
      assert {:ok, _s, [{:nudge, 25.0}]} = Joystick.handle_event(jstick(), :deflect, 50)
    end

    test "tiny travel is ignored" do
      assert {:ok, _s, []} = Joystick.handle_event(jstick(), :deflect, 2)
    end
  end
end
