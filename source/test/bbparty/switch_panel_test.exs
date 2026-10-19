defmodule Bbparty.SwitchPanelTest do
  use ExUnit.Case, async: true

  alias Bbparty.SwitchPanel

  describe "ids and addresses" do
    test "an id is the crosspoint it landed on" do
      assert SwitchPanel.switch_id(0, 0) == "switch_0_0"
      assert SwitchPanel.switch_id(4, 5) == "switch_4_5"
    end

    test "address/1 round-trips an id, as a string or an atom" do
      assert SwitchPanel.address("switch_4_5") == {:ok, {4, 5}}
      assert SwitchPanel.address(:switch_0_0) == {:ok, {0, 0}}
    end

    test "address/1 is total — the panel holds gauges and joysticks too" do
      assert SwitchPanel.address("gauge_zoom") == :error
      assert SwitchPanel.address(:joystick_1) == :error
      assert SwitchPanel.address("key_3_4") == :error
      assert SwitchPanel.address("switch_") == :error
      assert SwitchPanel.address("switch_1") == :error
      assert SwitchPanel.address("switch_1_2_3") == :error
      assert SwitchPanel.address("switch_a_b") == :error
      assert SwitchPanel.address("switch_1_2x") == :error
    end

    test "an address outside the bus is not an id" do
      assert SwitchPanel.address("switch_8_0") == :error
      assert SwitchPanel.address("switch_0_8") == :error
      assert SwitchPanel.address("switch_-1_0") == :error
    end
  end

  describe "valid_address?/2" do
    test "every crosspoint of the 8x8 bus is addressable, wired or not" do
      assert SwitchPanel.valid_address?(0, 0)
      assert SwitchPanel.valid_address?(4, 5)
      assert SwitchPanel.valid_address?(7, 7)
      assert SwitchPanel.valid_address?(5, 6)
    end

    test "outside the bus, or not an integer" do
      refute SwitchPanel.valid_address?(8, 0)
      refute SwitchPanel.valid_address?(0, 8)
      refute SwitchPanel.valid_address?(-1, 0)
      refute SwitchPanel.valid_address?(nil, 0)
      refute SwitchPanel.valid_address?("3", 4)
    end
  end

  describe "the wired panel" do
    test "30 crosspoints, in panel order" do
      wired = SwitchPanel.wired_crosspoints()

      assert length(wired) == 30
      assert hd(wired) == {0, 0}
      assert List.last(wired) == {4, 5}
    end

    test "default positions lay the panel out as a grid" do
      assert SwitchPanel.default_position(0, 0) == %{"x" => 0, "y" => 0}

      %{"x" => x1, "y" => y0} = SwitchPanel.default_position(0, 1)
      %{"x" => x0, "y" => y1} = SwitchPanel.default_position(1, 0)

      assert x1 > x0
      assert y1 > y0
    end

    test "the pitch clears the part's footprint" do
      {width, height} = Hardware.Components.SwitchWithTwoLeds.dimensions()

      assert SwitchPanel.pitch() > Hardware.Component.mm_to_px(width)
      assert SwitchPanel.pitch() > Hardware.Component.mm_to_px(height)
    end
  end

  describe "grid_plan/2" do
    defp ids,
      do: Enum.map(SwitchPanel.wired_crosspoints(), fn {d, s} -> SwitchPanel.switch_id(d, s) end)

    test "lays every switch on its crosspoint: drive down, sense across" do
      plan = Map.new(SwitchPanel.grid_plan(ids()))

      assert plan["switch_0_0"] == %{"x" => 0, "y" => 0}
      assert plan["switch_0_1"] == %{"x" => SwitchPanel.pitch(), "y" => 0}
      assert plan["switch_1_0"] == %{"x" => 0, "y" => SwitchPanel.pitch()}
    end

    test "nothing overlaps" do
      positions = SwitchPanel.grid_plan(ids()) |> Enum.map(fn {_id, position} -> position end)

      assert length(Enum.uniq(positions)) == 30
    end

    test "the origin moves the whole grid, and keeps its shape" do
      plan = Map.new(SwitchPanel.grid_plan(ids(), origin: {-500, -500}))

      assert plan["switch_0_0"] == %{"x" => -500, "y" => -500}

      assert plan["switch_4_5"] == %{
               "x" => -500 + 5 * SwitchPanel.pitch(),
               "y" => -500 + 4 * SwitchPanel.pitch()
             }
    end

    test "a tighter pitch is allowed, for a panel someone wants packed" do
      plan = Map.new(SwitchPanel.grid_plan(ids(), pitch: 10))

      assert plan["switch_0_1"] == %{"x" => 10, "y" => 0}
    end

    test "ids that are not switches are dropped, not moved" do
      plan = SwitchPanel.grid_plan(["switch_0_0", "gauge_zoom", :joystick_1, "key_3_4"])

      assert [{"switch_0_0", _position}] = plan
    end

    test "an empty list plans nothing" do
      assert SwitchPanel.grid_plan([]) == []
    end
  end

  describe "snapshot bitmaps" do
    test "bit index is drive * 8 + sense" do
      bits = Bitwise.bsl(1, 0) + Bitwise.bsl(1, 8) + Bitwise.bsl(1, 37)

      assert SwitchPanel.pressed?(bits, 0, 0)
      assert SwitchPanel.pressed?(bits, 1, 0)
      assert SwitchPanel.pressed?(bits, 4, 5)
      refute SwitchPanel.pressed?(bits, 0, 1)
      refute SwitchPanel.pressed?(bits, 7, 7)
    end

    test "pressed/1 lists the closed crosspoints in scan order" do
      bits = Bitwise.bsl(1, 37) + Bitwise.bsl(1, 0)
      assert SwitchPanel.pressed(bits) == [{0, 0}, {4, 5}]
    end

    test "an all-open snapshot lists nothing" do
      assert SwitchPanel.pressed(0) == []
    end

    test "every crosspoint closed is 64 of them" do
      assert length(SwitchPanel.pressed(Bitwise.bsl(1, 64) - 1)) == 64
    end
  end
end
