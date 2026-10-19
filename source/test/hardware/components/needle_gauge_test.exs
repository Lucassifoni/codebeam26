defmodule Hardware.Components.NeedleGaugeTest do
  use ExUnit.Case, async: true

  alias Hardware.Components.NeedleGauge

  describe "new/1" do
    test "defaults are virtual-only (unbound), full-scale duty" do
      g = NeedleGauge.new([])
      assert g.module == nil and g.gauge == nil
      assert g.duty_min == 0 and g.duty_max == 255
    end

    test "binds and calibrates from attrs" do
      g = NeedleGauge.new(module: 2, gauge: 1, duty_min: 40, duty_max: 210)
      assert g.module == 2 and g.gauge == 1
      assert g.duty_min == 40 and g.duty_max == 210
    end

    test "nil attr values fall back to defaults" do
      g = NeedleGauge.new(module: nil, gauge: nil, duty_min: nil, duty_max: nil)
      assert g.duty_min == 0 and g.duty_max == 255
    end
  end

  describe "pct_to_duty/3" do
    test "full-scale mapping and clamping" do
      assert NeedleGauge.pct_to_duty(0, 0, 255) == 0
      assert NeedleGauge.pct_to_duty(50, 0, 255) == 128
      assert NeedleGauge.pct_to_duty(100, 0, 255) == 255
      assert NeedleGauge.pct_to_duty(-10, 0, 255) == 0
      assert NeedleGauge.pct_to_duty(150, 0, 255) == 255
    end

    test "calibrated endpoints place neutral and range" do
      assert NeedleGauge.pct_to_duty(0, 60, 200) == 60
      assert NeedleGauge.pct_to_duty(100, 60, 200) == 200
      assert NeedleGauge.pct_to_duty(50, 60, 200) == 130
    end

    test "duty_min > duty_max inverts a reversed gauge" do
      assert NeedleGauge.pct_to_duty(0, 255, 0) == 255
      assert NeedleGauge.pct_to_duty(100, 255, 0) == 0
    end
  end

  test "duty/1 reads the struct's calibrated duty" do
    g = %NeedleGauge{progress: 50, duty_min: 0, duty_max: 255}
    assert NeedleGauge.duty(g) == 128
  end

  test "handle_event updates the display progress" do
    {:ok, g} = NeedleGauge.handle_event(NeedleGauge.new([]), :set_progress, 73)
    assert g.progress == 73
  end

  describe "handle_transition/3" do
    test "an unbound gauge drives nothing and returns :ok" do
      g = NeedleGauge.new([])
      assert NeedleGauge.handle_transition(g, %{g | progress: 80}, []) == :ok
    end

    test "a bound gauge drives its channel on every transition (enables resync)" do
      g = NeedleGauge.new(module: 2, gauge: 0)
      assert NeedleGauge.handle_transition(g, %{g | progress: 50}, []) == :ok
      assert NeedleGauge.handle_transition(g, %{g | progress: 90}, []) == :ok
    end
  end
end
