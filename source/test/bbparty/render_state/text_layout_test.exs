defmodule Bbparty.RenderState.TextLayoutTest do
  use ExUnit.Case, async: true

  alias Bbparty.RenderState.TextLayout

  defp layout do
    %TextLayout{
      fingerprint: "f",
      line_starts: [0, 2, 6],
      xs: %{0 => [0, 10, 22], 1 => [0, 9, 21, 30, 44], 2 => [0, 11, 19]}
    }
  end

  describe "from_params/1" do
    test "takes a well-formed push, with the xs keys JSON turned into strings" do
      built =
        TextLayout.from_params(%{
          "fingerprint" => "f",
          "line_starts" => [0, 2],
          "xs" => %{"0" => [0, 10.5], "1" => [0, 9]}
        })

      assert built.fingerprint == "f"
      assert built.line_starts == [0, 2]
      assert built.xs == %{0 => [0, 10.5], 1 => [0, 9]}
    end

    test "falls back to a single line rather than trusting a malformed run" do
      for starts <- [[], [2, 0], [0, 0], [0, -1], ["0"], "nope", nil] do
        assert TextLayout.from_params(%{"line_starts" => starts}).line_starts == [0]
      end
    end

    test "drops xs entries that are not measurements" do
      built =
        TextLayout.from_params(%{
          "line_starts" => [0],
          "xs" => %{"0" => [0, 10], "1" => "nope", "2" => [], "3" => [0, "x"], "bad" => [0]}
        })

      assert built.xs == %{0 => [0, 10]}
    end

    test "a push that is not a map at all yields the empty layout" do
      assert TextLayout.from_params("nope") == TextLayout.empty()
    end
  end

  describe "stale?/2" do
    test "true exactly when the fingerprint differs" do
      refute TextLayout.stale?(layout(), "f")
      assert TextLayout.stale?(layout(), "g")
      assert TextLayout.stale?(TextLayout.empty(), "f")
    end
  end

  describe "line_of/2" do
    test "a line's first offset belongs to that line" do
      assert TextLayout.line_of(layout(), 0) == 0
      assert TextLayout.line_of(layout(), 1) == 0
      assert TextLayout.line_of(layout(), 2) == 1
      assert TextLayout.line_of(layout(), 5) == 1
      assert TextLayout.line_of(layout(), 6) == 2
    end

    test "an offset past the text stays on the last line" do
      assert TextLayout.line_of(layout(), 99) == 2
    end
  end

  describe "line_end/3" do
    test "stops one short of the next line, so the cursor cannot straddle" do
      assert TextLayout.line_end(layout(), 0, 8) == 1
      assert TextLayout.line_end(layout(), 1, 8) == 5
    end

    test "the last line is bounded by the text, the one place past every glyph" do
      assert TextLayout.line_end(layout(), 2, 8) == 8
    end
  end

  describe "x_of/2 and nearest/3" do
    test "reads the measured x of an offset" do
      assert TextLayout.x_of(layout(), 3) == 9
      assert TextLayout.x_of(layout(), 0) == 0
    end

    test "nil for a line outside the measured window, rather than a guess" do
      partial = %{layout() | xs: Map.delete(layout().xs, 2)}

      assert TextLayout.x_of(partial, 6) == nil
      assert TextLayout.nearest(partial, 2, 10) == nil
    end

    test "nearest picks by distance, not by column" do
      assert TextLayout.nearest(layout(), 1, 29) == 5
      assert TextLayout.nearest(layout(), 1, 0) == 2
      assert TextLayout.nearest(layout(), 0, 1000) == 2
    end
  end
end
