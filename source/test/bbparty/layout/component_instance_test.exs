defmodule Bbparty.Layout.ComponentInstanceTest do
  use ExUnit.Case, async: true

  alias Bbparty.Layout.ComponentInstance
  alias Hardware.Components.Joystick

  describe "cast/2" do
    test "numbers come in as strings from the editor and JSON alike" do
      assert ComponentInstance.cast("120", :integer) == 120
      assert ComponentInstance.cast("0.2", :float) == 0.2
      assert ComponentInstance.cast(nil, :integer) == nil
    end

    test "a flag is written any of the ways a person writes one" do
      for written <- ~w(true 1 yes on TRUE  True ) do
        assert ComponentInstance.cast(written, :boolean) == true, written
      end

      for written <- ~w(false 0 no off FALSE) do
        assert ComponentInstance.cast(written, :boolean) == false, written
      end

      assert ComponentInstance.cast(true, :boolean) == true
      assert ComponentInstance.cast(false, :boolean) == false
    end

    test "an unparseable flag falls back to the component default" do
      assert ComponentInstance.cast("maybe", :boolean) == nil
      assert ComponentInstance.cast("", :boolean) == nil
    end
  end

  describe "hydrate_attrs/2" do
    test "a stored flag survives the trip through the editor's text field" do
      attrs = ComponentInstance.hydrate_attrs(%{"invert" => "true", "axis" => "1"}, Joystick)

      assert attrs.invert == true
      assert attrs.axis == 1
      assert Joystick.new(Map.to_list(attrs)).invert
    end

    test "a flag left off is nil, and the component decides" do
      attrs = ComponentInstance.hydrate_attrs(%{}, Joystick)

      assert attrs.invert == nil
      refute Joystick.new(Map.to_list(attrs)).invert
    end
  end
end
