defmodule Hardware.Components.FontSelectorTest do
  use ExUnit.Case, async: true

  alias Hardware.Components.FontSelector

  defp tag(state, id), do: FontSelector.handle_event(state, :tag, id)

  describe "a tag on the reader" do
    test "asks for the font it names" do
      assert {:ok, _state, [{:select_font, "Chalkboard"}]} =
               tag(FontSelector.new([]), "Chalkboard")
    end

    test "leaves the highlight to the core" do
      shown = %FontSelector{selected_font: "Arial"}

      assert {:ok, ^shown, [{:select_font, "Papyrus"}]} = tag(shown, "Papyrus")
    end

    test "an id nobody knows changes nothing and emits nothing" do
      shown = %FontSelector{selected_font: "Arial"}

      assert {:ok, ^shown} = tag(shown, "some-stranger's-transit-card")
    end

    test "an empty tag is not a font either" do
      assert {:ok, %FontSelector{selected_font: nil}} = tag(FontSelector.new([]), "")
    end
  end

  describe "the on-screen list" do
    test "asks for a font the same way a tag does" do
      assert {:ok, %FontSelector{selected_font: nil}, [{:select_font, "Arial"}]} =
               FontSelector.handle_event(FontSelector.new([]), :select_font, "Arial")
    end

    test "an empty payload asks to clear the selection" do
      shown = %FontSelector{selected_font: "Arial"}

      assert {:ok, ^shown, [{:select_font, ""}]} =
               FontSelector.handle_event(shown, :select_font, "")
    end
  end

  describe "the font projected by the core" do
    test "is what the selector shows" do
      assert {:ok, %FontSelector{selected_font: "Arial"}} =
               FontSelector.handle_event(FontSelector.new([]), :set_font, "Arial")
    end

    test "no font clears the highlight" do
      shown = %FontSelector{selected_font: "Arial"}

      assert {:ok, %FontSelector{selected_font: nil}} =
               FontSelector.handle_event(shown, :set_font, nil)
    end
  end

  describe "field_binding/1" do
    test "shows the core's selected font, wired or not" do
      assert FontSelector.field_binding(FontSelector.new(module: 2)) == {:field, :selected_font}
      assert FontSelector.field_binding(FontSelector.new([])) == {:field, :selected_font}
    end
  end

  describe "input_binding/1" do
    test "addresses the reader by its board" do
      assert FontSelector.input_binding(FontSelector.new(module: 2)) == {:nfc, 2}
    end

    test "an unbound selector is virtual only" do
      assert FontSelector.input_binding(FontSelector.new([])) == nil
    end
  end
end
