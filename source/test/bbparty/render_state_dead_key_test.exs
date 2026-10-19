defmodule Bbparty.RenderStateDeadKeyTest do
  use ExUnit.Case, async: true

  alias Bbparty.RenderState
  alias Bbparty.RenderState.TextLayout

  defp press(state, attrs, layout \\ TextLayout.empty()) do
    {new_state, _commands, _effects} =
      RenderState.apply(state, {:some_key, :key_down, meaning(attrs)}, layout)

    new_state
  end

  defp release(state, attrs) do
    {new_state, _commands, _effects} =
      RenderState.apply(state, {:some_key, :key_up, meaning(attrs)})

    new_state
  end

  defp meaning(attrs), do: Enum.into(attrs, %{char: nil, shift: nil, action: nil})

  defp type(state, text) do
    text
    |> String.graphemes()
    |> Enum.reduce(state, fn char, acc -> press(acc, char: char) end)
  end

  defp act(state, action, layout \\ TextLayout.empty()),
    do: press(state, [action: action], layout)

  defp dead(state, mark), do: press(state, char: mark, action: "dead")

  describe "arming" do
    test "a dead key types nothing and waits" do
      state = RenderState.new() |> type("caf") |> dead("´")

      assert state.text == "caf"
      assert state.cursor == 3
      assert state.pending_diacritic == "´"
    end

    test "the armed mark is drawn at the cursor, split out of the text" do
      state = RenderState.new() |> type("cafe") |> act("left") |> dead("´")

      assert RenderState.composition(state) == {"caf", "´", "e"}
    end

    test "nothing pending leaves the composition in one piece" do
      state = RenderState.new() |> type("cafe")

      assert RenderState.composition(state) == {"cafe", nil, ""}
    end

    test "the mark occupies the cursor's own slot" do
      {before, mark, _rest} =
        RenderState.composition(RenderState.new() |> type("caf") |> dead("´"))

      assert String.length(before) == 3
      assert mark == "´"
    end
  end

  describe "resolving" do
    test "a letter the mark takes becomes one precomposed glyph" do
      state = RenderState.new() |> type("caf") |> dead("´") |> type("e")

      assert state.text == "café"
      assert String.length(state.text) == 4
      assert state.cursor == 4
      assert state.pending_diacritic == nil
    end

    test "space types the mark on its own and is consumed by it" do
      state = RenderState.new() |> dead("´") |> act("space")

      assert state.text == "´"
      assert state.cursor == 1
      assert state.pending_diacritic == nil
    end

    test "a letter the mark cannot take is emitted after it" do
      state = RenderState.new() |> dead("ˇ") |> type("g")

      assert state.text == "ˇg"
      assert state.cursor == 2
      assert state.pending_diacritic == nil
    end

    test "a digit, an emoji and a second mark are all just not letters" do
      assert (RenderState.new() |> dead("´") |> type("5")).text == "´5"
      assert (RenderState.new() |> dead("´") |> type("😀")).text == "´😀"
    end

    test "a second dead key emits the first and arms itself" do
      state = RenderState.new() |> dead("´") |> dead("¨") |> type("o")

      assert state.text == "´ö"
      assert state.pending_diacritic == nil
    end

    test "resolves at the cursor, not at the end" do
      state =
        RenderState.new()
        |> type("xy")
        |> act("left")
        |> dead("˜")
        |> type("n")

      assert state.text == "xñy"
      assert state.cursor == 2
    end

    test "composes onto the shifted letter" do
      state =
        RenderState.new()
        |> dead("´")
        |> press(action: "shift")
        |> press(char: "e", shift: "E")

      assert state.text == "É"
    end

    test "composes onto a caps-locked letter" do
      state =
        RenderState.new()
        |> act("capslock")
        |> dead("ˇ")
        |> press(char: "s", shift: "S")

      assert state.text == "Š"
    end
  end

  describe "cancelling" do
    test "backspace drops the mark and deletes nothing" do
      state = RenderState.new() |> type("caf") |> dead("´") |> act("backspace")

      assert state.text == "caf"
      assert state.cursor == 3
      assert state.pending_diacritic == nil
    end

    test "backspace deletes as usual once nothing is pending" do
      state =
        RenderState.new() |> type("caf") |> dead("´") |> act("backspace") |> act("backspace")

      assert state.text == "ca"
    end

    test "a cursor move drops the mark and still moves" do
      for action <- ~w(left right) do
        state = RenderState.new() |> type("ab") |> act("left") |> dead("´") |> act(action)

        assert state.pending_diacritic == nil
        assert state.text == "ab"
      end

      assert (RenderState.new() |> type("ab") |> act("left") |> dead("´") |> act("left")).cursor ==
               0
    end

    test "enter drops the mark and still breaks the line" do
      state = RenderState.new() |> type("a") |> dead("´") |> act("enter")

      assert state.text == "a\n"
      assert state.pending_diacritic == nil
    end

    test "reset clears it along with everything else" do
      state = RenderState.new() |> type("a") |> dead("´") |> act("reset")

      assert state.text == ""
      assert state.pending_diacritic == nil
    end

    test "a selector drops it" do
      state = RenderState.new() |> dead("´") |> act("align_center")

      assert state.alignment == :center
      assert state.pending_diacritic == nil
    end
  end

  describe "what does not cancel" do
    test "shift, its release, and capslock all leave the mark armed" do
      state =
        RenderState.new()
        |> dead("´")
        |> press(action: "shift")
        |> release(action: "shift")
        |> act("capslock")

      assert state.pending_diacritic == "´"
    end

    test "print leaves the mark armed" do
      state = RenderState.new() |> dead("´") |> act("print")

      assert state.pending_diacritic == "´"
    end
  end

  describe "a dead key that is not one" do
    test "a dead key carrying a letter types it" do
      state = RenderState.new() |> press(char: "q", action: "dead")

      assert state.text == "q"
      assert state.pending_diacritic == nil
    end

    test "a dead key with no char says nothing" do
      state = RenderState.new() |> type("a") |> press(char: nil, action: "dead")

      assert state.text == "a"
      assert state.pending_diacritic == nil
    end
  end

  describe "the renderer's cache" do
    test "arming and resolving both move the layout fingerprint" do
      armed = RenderState.new() |> type("caf") |> dead("´")
      bare = RenderState.new() |> type("caf")
      resolved = type(armed, "e")

      refute RenderState.layout_fingerprint(armed) == RenderState.layout_fingerprint(bare)
      refute RenderState.layout_fingerprint(armed) == RenderState.layout_fingerprint(resolved)
    end

    test "an overridden render draws no pending mark" do
      state = %{(RenderState.new() |> type("caf") |> dead("´")) | text_source: :alpha_upper}

      assert {_text, nil, ""} = RenderState.composition(state)
      assert state.pending_diacritic == "´"
    end
  end
end
