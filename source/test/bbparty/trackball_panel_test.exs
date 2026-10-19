defmodule Bbparty.TrackballPanelTest do
  use ExUnit.Case, async: true

  alias Bbparty.TrackballPanel

  describe "ids" do
    test "a button id names its index" do
      assert TrackballPanel.button_id(0) == "m4_button_0"
      assert TrackballPanel.button_id(1) == "m4_button_1"
    end

    test "the board has one ball" do
      assert TrackballPanel.trackball_id() == "m4_trackball"
    end

    test "ids are interpolable into an atom, as PhysicalComponent.name/1 needs" do
      assert is_binary(TrackballPanel.button_id(0))
      refute TrackballPanel.button_id(0) =~ ~r/[{}\s]/
    end
  end

  describe "valid_button?/1" do
    test "the two wired buttons" do
      assert TrackballPanel.valid_button?(0)
      assert TrackballPanel.valid_button?(1)
    end

    test "anything else is a fault, not a button" do
      refute TrackballPanel.valid_button?(2)
      refute TrackballPanel.valid_button?(-1)
      refute TrackballPanel.valid_button?(nil)
      refute TrackballPanel.valid_button?("0")
    end
  end

  describe "default positions" do
    test "the board lays out as a cluster, not a stack at the origin" do
      positions = [
        TrackballPanel.button_default_position(0),
        TrackballPanel.button_default_position(1),
        TrackballPanel.trackball_default_position()
      ]

      assert length(Enum.uniq(positions)) == 3
    end

    test "positions carry the string keys a ComponentInstance stores" do
      assert %{"x" => 0, "y" => _} = TrackballPanel.button_default_position(0)
    end

    test "the cluster clears module_3's grid rather than landing under it" do
      keyboard_bottom = (Bbparty.Keyboard.drives() - 1) * Bbparty.Keyboard.pitch()

      for position <- [
            TrackballPanel.button_default_position(0),
            TrackballPanel.button_default_position(1),
            TrackballPanel.trackball_default_position()
          ] do
        assert position["y"] > keyboard_bottom
      end
    end
  end

  describe "transitions/2" do
    test "a press is a bit going up" do
      assert TrackballPanel.transitions(0b00, 0b01) == [{0, true}]
      assert TrackballPanel.transitions(0b00, 0b10) == [{1, true}]
    end

    test "a release is a bit going down" do
      assert TrackballPanel.transitions(0b01, 0b00) == [{0, false}]
      assert TrackballPanel.transitions(0b11, 0b01) == [{1, false}]
    end

    test "both buttons can move in one frame, in index order" do
      assert TrackballPanel.transitions(0b00, 0b11) == [{0, true}, {1, true}]
      assert TrackballPanel.transitions(0b11, 0b00) == [{0, false}, {1, false}]
    end

    test "opposite edges in one frame" do
      assert TrackballPanel.transitions(0b01, 0b10) == [{0, false}, {1, true}]
    end

    test "an identical field is no edges at all" do
      assert TrackballPanel.transitions(0b00, 0b00) == []
      assert TrackballPanel.transitions(0b11, 0b11) == []
    end

    test "a bit above the wired buttons invents nothing" do
      assert TrackballPanel.transitions(0b000, 0b100) == []
      assert TrackballPanel.transitions(0b000, 0b101) == [{0, true}]
    end
  end
end
