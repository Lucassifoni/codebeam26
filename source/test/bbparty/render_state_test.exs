defmodule Bbparty.RenderStateTest do
  use ExUnit.Case, async: true

  alias Bbparty.RenderState
  alias Bbparty.RenderState.Keys
  alias Bbparty.RenderState.Sizings
  alias Bbparty.RenderState.Projections
  alias Bbparty.RenderState.TextLayout
  alias Bbparty.RenderState.TextToWrite

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

  describe "typing at the cursor" do
    test "a char is inserted at the cursor, not appended" do
      state = RenderState.new() |> type("abc") |> act("left") |> act("left") |> type("X")

      assert state.text == "aXbc"
      assert state.cursor == 2
    end

    test "an unassigned key says nothing and does not move the cursor" do
      state = RenderState.new() |> type("ab") |> press([])

      assert state.text == "ab"
      assert state.cursor == 2
    end

    test "the reset char clears the text and the cursor" do
      state = RenderState.new() |> type("hello") |> press(char: "__RESET__")

      assert state.text == ""
      assert state.cursor == 0
    end

    test "SPACE and ENTER insert at the cursor" do
      state = RenderState.new() |> type("ab") |> act("left") |> act("space") |> act("enter")

      assert state.text == "a \nb"
      assert state.cursor == 3
    end
  end

  describe "horizontal movement" do
    test "clamps at both ends rather than running off the text" do
      state = RenderState.new() |> type("ab") |> act("right") |> act("right")
      assert state.cursor == 2

      state = state |> act("left") |> act("left") |> act("left") |> act("left")
      assert state.cursor == 0
    end
  end

  describe "backspace" do
    test "deletes before the cursor and takes the cursor with it" do
      state = RenderState.new() |> type("abc") |> act("left") |> act("backspace")

      assert state.text == "ac"
      assert state.cursor == 1
    end

    test "at the start of the text is a no-op" do
      state = RenderState.new() |> type("ab") |> act("left") |> act("left") |> act("backspace")

      assert state.text == "ab"
      assert state.cursor == 0
    end

    test "on empty text is a no-op" do
      state = RenderState.new() |> act("backspace")

      assert state.text == ""
      assert state.cursor == 0
    end
  end

  describe "effective_char/3" do
    test "shift held selects the alternate glyph" do
      assert Keys.effective_char(%{char: "a", shift: "A"}, true, false) == "A"
      assert Keys.effective_char(%{char: "1", shift: "!"}, true, false) == "!"
    end

    test "caps lock selects the alternate only when it is cased" do
      assert Keys.effective_char(%{char: "a", shift: "A"}, false, true) == "A"
      assert Keys.effective_char(%{char: "1", shift: "!"}, false, true) == "1"
    end

    test "unmodified, and with no alternate assigned, the base char wins" do
      assert Keys.effective_char(%{char: "a", shift: "A"}, false, false) == "a"
      assert Keys.effective_char(%{char: "a", shift: nil}, true, true) == "a"
      assert Keys.effective_char(%{char: nil, shift: nil}, false, false) == nil
    end
  end

  describe "modifiers" do
    test "SHIFT is momentary and applies to the key pressed while it is held" do
      state = RenderState.new() |> act("shift")
      assert state.shift_down

      state = press(state, char: "a", shift: "A")
      assert state.text == "A"

      state = release(state, action: "shift")
      refute state.shift_down

      assert press(state, char: "a", shift: "A").text == "Aa"
    end

    test "CAPSLOCK latches on press and is untouched by its own release" do
      state = RenderState.new() |> act("capslock")
      assert state.caps_lock

      state = release(state, action: "capslock")
      assert state.caps_lock

      assert press(state, char: "a", shift: "A").text == "A"
      refute act(state, "capslock").caps_lock
    end

    test "an action key ignores the placeholder char commissioning gave it" do
      state = RenderState.new() |> type("ab") |> press(char: "Z", action: "left")

      assert state.text == "ab"
      assert state.cursor == 1
    end

    test "an unrecognised action falls back to typing the char" do
      assert press(RenderState.new(), char: "Z", action: "BACKSPCE").text == "Z"
    end
  end

  describe "vertical movement against a measurement" do
    defp wrapped do
      state = %{RenderState.new() | text: "abcdefgh"}

      layout = %TextLayout{
        fingerprint: RenderState.layout_fingerprint(state),
        line_starts: [0, 2, 6],
        xs: %{0 => [0, 10, 22], 1 => [0, 9, 21, 30, 44], 2 => [0, 11, 19]}
      }

      {state, layout}
    end

    test "lands on the glyph nearest the cursor's x, not on the same column" do
      {state, layout} = wrapped()

      moved = %{state | cursor: 4} |> act("up", layout)

      assert moved.cursor == 1
      assert moved.goal_x == 21
    end

    test "the trailing slot is reachable when a newline occupies it" do
      state = %{RenderState.new() | text: "ab\ncdef", cursor: 5}

      layout = %TextLayout{
        fingerprint: RenderState.layout_fingerprint(state),
        line_starts: [0, 3],
        xs: %{0 => [0, 10, 22, 22], 1 => [0, 9, 21, 30, 44]}
      }

      assert act(state, "up", layout).cursor == 2
    end

    test "walks visual lines, which no offset arithmetic could find" do
      {state, layout} = wrapped()

      assert %{state | cursor: 0} |> act("down", layout) |> Map.get(:cursor) == 2
    end

    test "goal_x survives a short line so UP then DOWN returns to the column" do
      {state, layout} = wrapped()

      up = %{state | cursor: 5} |> act("up", layout)
      assert up.goal_x == 30

      down = act(up, "down", layout)
      assert down.cursor == 5
      assert down.goal_x == 30
    end

    test "past the first and last line the cursor stays put and keeps its goal" do
      {state, layout} = wrapped()

      top = %{state | cursor: 1, goal_x: 44} |> act("up", layout)
      assert top.cursor == 1
      assert top.goal_x == 44

      assert %{state | cursor: 7} |> act("down", layout) |> Map.get(:cursor) == 7
    end

    test "any other action clears the sticky goal" do
      {state, layout} = wrapped()

      assert %{state | cursor: 4} |> act("up", layout) |> act("left") |> Map.get(:goal_x) == nil
    end
  end

  describe "vertical movement without a trustworthy measurement" do
    test "a stale fingerprint degrades to hard lines rather than acting on it" do
      state = %{RenderState.new() | text: "ab\ncdef", cursor: 5}

      stale = %TextLayout{
        fingerprint: "measured-against-something-else",
        line_starts: [0, 2, 4, 6],
        xs: %{0 => [0, 9, 18], 1 => [0, 9, 18], 2 => [0, 9, 18]}
      }

      assert act(state, "up", stale).cursor == 2
    end

    test "with no renderer at all, hard lines still move the cursor" do
      state = %{RenderState.new() | text: "abc\ndefgh", cursor: 6}

      assert act(state, "up").cursor == 2
      assert act(state, "up") |> act("down") |> Map.get(:cursor) == 6
    end

    test "a hard line shorter than the column clamps to its end" do
      state = %{RenderState.new() | text: "a\nbcdef", cursor: 6}

      assert act(state, "up").cursor == 1
    end
  end

  describe "RESET" do
    defp effects_of(state, attrs) do
      {_state, _commands, effects} =
        RenderState.apply(state, {:some_key, :key_down, meaning(attrs)}, TextLayout.empty())

      effects
    end

    defp scrambled do
      RenderState.new()
      |> type("hello world")
      |> Map.merge(%{
        zoom: 1.5,
        kerning: 7,
        leading: 1.9,
        selected_font: "Chalkboard",
        alignment: :center,
        transform_toupper: true,
        cumulative_features: ["dlig", "ss03", "smcp+c2sc", "ss17"],
        caps_lock: true
      })
    end

    test "every typographic parameter returns to its default" do
      reset = act(scrambled(), :reset)
      default = RenderState.new()

      assert reset.zoom == default.zoom
      assert reset.kerning == default.kerning
      assert reset.leading == default.leading
      assert reset.alignment == default.alignment
      assert reset.transform_toupper == default.transform_toupper
    end

    test "the font survives" do
      assert act(scrambled(), :reset).selected_font == "Chalkboard"
    end

    test "features on latching levers survive, stylistic sets are cleared" do
      assert act(scrambled(), :reset).cumulative_features == ["dlig", "smcp+c2sc"]
    end

    test "the text is cleared and the cursor goes home" do
      reset = act(scrambled(), :reset)

      assert reset.text == ""
      assert reset.cursor == 0
    end

    test "caps lock is cleared, since nothing on the panel shows it" do
      assert scrambled().caps_lock
      refute act(scrambled(), :reset).caps_lock
    end

    test "the __RESET__ char does the same thing as the action" do
      assert press(scrambled(), char: "__RESET__") == act(scrambled(), :reset)
    end

    test "the __RESET__ char resets even over a pending dead key" do
      pending = scrambled() |> press(char: "´", action: "dead")
      assert is_binary(pending.pending_diacritic)

      assert press(pending, char: "__RESET__") == act(pending, :reset)
    end

    test "a dead key carrying the __RESET__ char resets instead of arming" do
      assert press(scrambled(), char: "__RESET__", action: "dead") == act(scrambled(), :reset)
    end

    test "resetting emits no effect" do
      assert effects_of(scrambled(), action: :reset) == []
    end
  end

  describe "holding RESET" do
    defp edge(state, event, at) do
      RenderState.apply(state, {:some_key, event, meaning(action: :reset, at: at)})
    end

    defp held(state, down_at, up_at) do
      {pressed, _commands, _effects} = edge(state, :key_down, down_at)
      edge(pressed, :key_up, up_at)
    end

    defp hold_ms, do: Keys.hard_reset_hold_ms()

    defp scrambled_with_font do
      RenderState.new()
      |> type("hello")
      |> Map.merge(%{
        selected_font: "Chalkboard",
        cumulative_features: ["dlig", "ss03"],
        kerning: 1.0
      })
    end

    test "the press is stamped, after the reset it performs" do
      {pressed, _commands, _effects} = edge(scrambled_with_font(), :key_down, 1_000)

      assert pressed.text == ""
      assert pressed.reset_pressed_at == 1_000
    end

    test "a short press stays an ordinary RESET and clears the stamp on release" do
      {state, _commands, effects} = held(scrambled_with_font(), 1_000, 1_000 + hold_ms() - 1)

      assert effects == []
      assert state.selected_font == "Chalkboard"
      assert state.cumulative_features == ["dlig"]
      assert state.reset_pressed_at == nil
    end

    test "a release after the hold returns everything to new, font and levers included" do
      {state, _commands, _effects} = held(scrambled_with_font(), 1_000, 1_000 + hold_ms())

      assert state == RenderState.new()
    end

    test "a release after the hold reboots the boards" do
      {_state, _commands, effects} = held(scrambled_with_font(), 1_000, 1_000 + hold_ms())

      assert effects == [{:bus, :reboot_boards}]
    end

    test "the hard reset propagates the font and features to the panel" do
      {pressed, _commands, _effects} = edge(scrambled_with_font(), :key_down, 1_000)
      {_state, commands, _effects} = edge(pressed, :key_up, 1_000 + hold_ms())

      assert commands != []
      assert commands == Projections.propagate(pressed, RenderState.new())
    end

    test "a release with no recorded press does nothing" do
      {state, _commands, effects} = edge(scrambled_with_font(), :key_up, 1_000_000)

      assert effects == []
      assert state == scrambled_with_font()
    end

    test "edges without a time never hard-reset" do
      {state, _commands, effects} = held(scrambled_with_font(), nil, nil)

      assert effects == []
      assert state.selected_font == "Chalkboard"
    end

    test "only RESET's release is measured" do
      {pressed, _commands, _effects} = edge(scrambled_with_font(), :key_down, 1_000)

      {_state, _commands, effects} =
        RenderState.apply(
          pressed,
          {:some_key, :key_up, meaning(action: :print, at: 1_000 + hold_ms())}
        )

      assert effects == []
    end
  end

  describe "PRINT" do
    test "changes nothing about the state" do
      before = RenderState.new() |> type("keep me")

      assert act(before, :print) == before
    end

    test "emits one print effect at the printer" do
      assert [{"printer", :print}] = effects_of(RenderState.new(), action: :print)
    end

    test "the release emits nothing" do
      {_state, _commands, effects} =
        RenderState.apply(RenderState.new(), {:some_key, :key_up, meaning(action: :print)})

      assert effects == []
    end

    test "the printer is a literally-named id, so renaming it is refused" do
      assert MapSet.member?(RenderState.referenced_ids(), "printer")
    end
  end

  describe "layout_fingerprint/1" do
    test "changes for every field that can move a glyph" do
      base = RenderState.new()
      fingerprint = RenderState.layout_fingerprint(base)

      for {field, value} <- [
            text: "a",
            text_quantity: 4,
            kerning: 1,
            leading: 1.3,
            selected_font: "Whatever",
            alignment: :center,
            transform_toupper: true,
            cumulative_features: ["smcp"]
          ] do
        assert RenderState.layout_fingerprint(%{base | field => value}) != fingerprint,
               "#{field} must invalidate the measurement"
      end
    end

    test "does not change for state that cannot move a glyph" do
      base = RenderState.new()
      fingerprint = RenderState.layout_fingerprint(base)

      for {field, value} <- [cursor: 3, goal_x: 12.5, shift_down: true, caps_lock: true] do
        assert RenderState.layout_fingerprint(%{base | field => value}) == fingerprint,
               "#{field} must not provoke a re-measure"
      end
    end

    test "the zoom does not, because a uniform scale cannot move a line break" do
      base = RenderState.new()

      for zoom <- [-2.0, -0.5, 1.0, 2.0] do
        assert RenderState.layout_fingerprint(%{base | zoom: zoom}) ==
                 RenderState.layout_fingerprint(base),
               "zoom #{zoom} must not provoke a re-measure"
      end
    end
  end

  describe "the existing typography fold is untouched" do
    test "a nudge still moves its field and still drives its gauge" do
      {state, commands, _effects} =
        RenderState.apply(RenderState.new(), {"kerning_joystick", :nudge, 100})

      assert state.kerning > 0
      assert Enum.any?(commands, &match?({:kerning_gauge, {:set_progress, _}}, &1))
    end

    test "a full push moves kerning by its own rate, not by a share of its range" do
      {state, _commands, _effects} =
        RenderState.apply(RenderState.new(), {"kerning_joystick", :nudge, 100})

      assert_in_delta state.kerning, Sizings.rates().kerning, 1.0e-9
    end

    test "zoom and leading keep moving at 5% of their range per full push" do
      for {field, stick} <- [zoom: "font_size_joystick", leading: "line_height_joystick"] do
        before = RenderState.new()
        {after_nudge, _commands, _effects} = RenderState.apply(before, {stick, :nudge, 100})
        {min, max} = Sizings.bounds()[field]

        assert_in_delta Map.get(after_nudge, field) - Map.get(before, field),
                        0.05 * (max - min),
                        1.0e-9
      end
    end

    test "kerning never tightens past -0.2em, however long the stick is held" do
      state =
        Enum.reduce(1..200, RenderState.new(), fn _, acc ->
          {next, _commands, _effects} = RenderState.apply(acc, {"kerning_joystick", :nudge, -100})
          next
        end)

      assert state.kerning == -0.2
    end
  end

  describe "magnification/1" do
    defp at(zoom), do: RenderState.magnification(%{RenderState.new() | zoom: zoom})

    test "neutral is life size — the fitted composition, unframed" do
      assert at(0.0) == 1.0
    end

    test "a whole step doubles, a whole step down halves" do
      assert_in_delta at(1.0), 2.0, 0.0001
      assert_in_delta at(-1.0), 0.5, 0.0001
      assert_in_delta at(2.0), 4.0, 0.0001
    end

    test "the bounds reach a quarter and four times, symmetrically" do
      {min_zoom, max_zoom} = Map.fetch!(Sizings.bounds(), :zoom)

      assert_in_delta at(min_zoom), 0.25, 0.0001
      assert_in_delta at(max_zoom), 4.0, 0.0001
      assert_in_delta at(min_zoom) * at(max_zoom), 1.0, 0.0001
    end

    test "neutral sits at the middle of the gauge's sweep" do
      assert_in_delta Projections.percentile(0.0, Map.fetch!(Sizings.bounds(), :zoom)),
                      50.0,
                      0.0001
    end

    test "it is strictly increasing across the whole range" do
      factors = for zoom <- -20..20, do: at(zoom / 10)

      assert factors == Enum.sort(factors)
      assert factors == Enum.uniq(factors)
    end

    test "it never returns something that would flip or blank the composition" do
      for zoom <- -20..20 do
        assert at(zoom / 10) > 0
      end
    end
  end

  describe "fit_bounds/0" do
    test "the floor is below the ceiling, and both are usable point sizes" do
      {floor, ceiling} = RenderState.fit_bounds()

      assert floor > 0
      assert floor < ceiling
    end

    test "a text too long to fit still has a size to be set at" do
      {floor, _ceiling} = RenderState.fit_bounds()

      assert floor >= 4, "a floor below legibility is the same as having none"
    end
  end

  describe "a trackball roll sets one word" do
    defp roll(state, word), do: RenderState.apply(state, {:m4_trackball, :roll, %{word: word}})

    defp rolled(state, word), do: state |> roll(word) |> elem(0)

    test "replaces the typed text with the word" do
      state = RenderState.new() |> type("hello world") |> rolled("grid")

      assert state.text == "grid"
      assert state.cursor == 4
    end

    test "every roll changes the word" do
      state = RenderState.new() |> rolled("grid") |> rolled("type") |> rolled("kern")

      assert state.text == "kern"
    end

    test "hands the render back from the encoder and from a specimen" do
      over_knob =
        RenderState.new()
        |> then(&elem(RenderState.apply(&1, {:text_quantity, :nudge_quantity, 12}), 0))
        |> rolled("grid")

      assert over_knob.text_quantity == 0
      assert RenderState.effective_text(over_knob) == "grid"

      over_specimen = %{RenderState.new() | text_source: :alpha_upper} |> rolled("grid")

      assert over_specimen.text_source == :user
      assert RenderState.effective_text(over_specimen) == "grid"
    end

    test "leaves the typography alone" do
      before = %{RenderState.new() | zoom: 1.0, kerning: 3, leading: 1.5}
      {state, commands, effects} = roll(before, "grid")

      assert {state.zoom, state.kerning, state.leading} == {1.0, 3, 1.5}
      refute Enum.any?(commands, &match?({:font_size_gauge, _}, &1))
      assert effects == []
    end

    test "backspace takes it back one letter at a time" do
      assert (RenderState.new() |> rolled("grid") |> act("backspace")).text == "gri"
    end

    test "a pending diacritic is dropped with the text it was waiting on" do
      state = %{RenderState.new() | pending_diacritic: "´"} |> rolled("grid")

      assert state.pending_diacritic == nil
      assert state.text == "grid"
    end

    test "a roll whose payload is not a word is a no-op" do
      for payload <- [4, %{}, %{word: 7}, nil] do
        {state, commands, effects} =
          RenderState.apply(RenderState.new(), {:m4_trackball, :roll, payload})

        assert {state, commands, effects} == {RenderState.new(), [], []}
      end
    end
  end

  describe "the encoder's text quantity" do
    defp turn(state, chars) do
      RenderState.apply(state, {:text_quantity, :nudge_quantity, chars})
    end

    defp quantity(state, chars) do
      {new_state, _commands, _effects} = turn(state, chars)
      new_state
    end

    test "a nudge accumulates into a character count" do
      state = RenderState.new() |> quantity(3) |> quantity(2)

      assert state.text_quantity == 5
    end

    test "the render draws that many characters of the preset text" do
      state = quantity(RenderState.new(), 3)

      assert RenderState.effective_text(state) == TextToWrite.take(3)
      assert String.length(RenderState.effective_text(state)) == 3
      assert RenderState.overridden?(state)
    end

    test "at zero the typist has their own text back" do
      state = RenderState.new() |> type("hello") |> quantity(3) |> quantity(-3)

      assert state.text_quantity == 0
      assert RenderState.effective_text(state) == "hello"
      refute RenderState.overridden?(state)
    end

    test "the typed text survives underneath" do
      state = RenderState.new() |> type("hello") |> quantity(3)

      assert state.text == "hello"
      assert state.cursor == 5
      assert RenderState.effective_text(state) == TextToWrite.take(3)
    end

    test "the count cannot go below zero" do
      state = RenderState.new() |> quantity(2) |> quantity(-40)

      assert state.text_quantity == 0
      assert RenderState.effective_text(state) == ""
    end

    test "the count cannot run past the end of the text" do
      state = quantity(RenderState.new(), TextToWrite.count() * 2)

      assert state.text_quantity == TextToWrite.count()
      assert RenderState.effective_text(state) == TextToWrite.text()
    end

    test "a nudge that is not a character count is a no-op" do
      {state, commands, effects} = turn(RenderState.new(), 1.5)

      assert state == RenderState.new()
      assert commands == []
      assert effects == []
    end

    test "the committed count is projected back onto the knob" do
      {_state, commands, _effects} = turn(RenderState.new(), 3)

      assert {{:field, :text_quantity}, {:set_quantity, 3}} in commands
    end

    test "a clamped turn projects the clamp, not what was asked for" do
      {state, _commands, _effects} = turn(RenderState.new(), 5)
      {_state, commands, _effects} = turn(state, TextToWrite.count())

      assert {{:field, :text_quantity}, {:set_quantity, TextToWrite.count()}} in commands
    end
  end

  describe "a keystroke takes the render back from the encoder" do
    test "typing a character clears the quantity" do
      state = RenderState.new() |> quantity(5) |> type("a")

      assert state.text_quantity == 0
      assert RenderState.effective_text(state) == "a"
    end

    test "so does backspace, an arrow, and ENTER" do
      for action <- ["backspace", "left", "right", "enter"] do
        state = RenderState.new() |> type("hi") |> quantity(5) |> act(action)

        assert state.text_quantity == 0, "#{action} must hand the render back"
      end
    end

    test "RESET clears it too" do
      state = RenderState.new() |> quantity(5) |> act("reset")

      assert state.text_quantity == 0
    end

    test "PRINT leaves it standing" do
      state = RenderState.new() |> quantity(5) |> act("print")

      assert state.text_quantity == 5
      assert RenderState.effective_text(state) == TextToWrite.take(5)
    end

    test "the modifiers leave it standing" do
      for action <- ["shift", "capslock"] do
        state = RenderState.new() |> quantity(5) |> act(action)

        assert state.text_quantity == 5, "#{action} is not an edit"
      end
    end

    test "the keystroke that clears it still lands on the typed text" do
      state = RenderState.new() |> type("ab") |> quantity(5) |> type("c")

      assert state.text == "abc"
      assert RenderState.effective_text(state) == "abc"
    end
  end

  describe "the panel's selector keys" do
    test "alignment holds one value, so the pair excludes itself" do
      state = RenderState.new() |> act("align_center")
      assert state.alignment == :center

      assert act(state, "align_left").alignment == :left
    end

    test "uppercase is a toggle" do
      state = RenderState.new() |> act("uppercase")
      assert state.transform_toupper

      refute act(state, "uppercase").transform_toupper
    end

    test "the five sources exclude each other" do
      for {action, source} <- [
            {"source_font_name", :font_name},
            {"source_alpha_upper", :alpha_upper},
            {"source_alpha_lower", :alpha_lower},
            {"source_numbers", :numbers},
            {"source_user", :user}
          ] do
        assert act(RenderState.new(), action).text_source == source
      end
    end

    test "a specimen leaves the typed text and the cursor alone" do
      state = RenderState.new() |> type("hello") |> act("source_numbers")

      assert state.text == "hello"
      assert state.cursor == 5
      assert RenderState.effective_text(state) == "0123456789"
    end

    test "the alphabets and the digits are what they say" do
      assert RenderState.new() |> act("source_alpha_upper") |> RenderState.effective_text() ==
               "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

      assert RenderState.new() |> act("source_alpha_lower") |> RenderState.effective_text() ==
               "abcdefghijklmnopqrstuvwxyz"
    end

    test "the font-name specimen names the selected font" do
      state = %{RenderState.new() | selected_font: "Chalkboard"} |> act("source_font_name")

      assert RenderState.effective_text(state) == "Chalkboard"
    end

    test "with no font selected it names nothing rather than raising" do
      assert RenderState.new() |> act("source_font_name") |> RenderState.effective_text() == ""
    end

    test "a specimen suppresses the caret, like the encoder's preset does" do
      assert RenderState.new() |> act("source_numbers") |> RenderState.overridden?()
      refute RenderState.new() |> act("source_user") |> RenderState.overridden?()
    end

    test "changing the source re-measures" do
      base = RenderState.new()

      refute RenderState.layout_fingerprint(act(base, "source_numbers")) ==
               RenderState.layout_fingerprint(base)
    end
  end

  describe "a keystroke returns the render to the typist" do
    test "typing leaves a specimen" do
      state = RenderState.new() |> act("source_numbers") |> type("a")

      assert state.text_source == :user
      assert RenderState.effective_text(state) == "a"
    end

    test "so does moving the caret" do
      assert RenderState.new()
             |> type("hi")
             |> act("source_alpha_upper")
             |> act("left")
             |> Map.fetch!(:text_source) == :user
    end

    test "a selector key does not cancel itself" do
      state = RenderState.new() |> act("source_numbers") |> act("uppercase")

      assert state.text_source == :numbers
      assert state.transform_toupper
    end

    test "PRINT and the modifiers leave the specimen standing" do
      for action <- ["print", "shift", "capslock"] do
        state = RenderState.new() |> act("source_alpha_lower") |> act(action)

        assert state.text_source == :alpha_lower, "#{action} must not clear the source"
      end
    end

    test "the encoder's preset lives inside user text" do
      {state, _commands, _effects} =
        RenderState.apply(RenderState.new(), {:text_quantity, :nudge_quantity, 2})

      assert RenderState.effective_text(state) == TextToWrite.take(2)

      specimen = act(state, "source_numbers")
      assert RenderState.effective_text(specimen) == "0123456789"
      assert RenderState.effective_text(act(specimen, "source_user")) == TextToWrite.take(2)
    end

    test "RESET puts everything back" do
      state =
        RenderState.new()
        |> act("source_numbers")
        |> act("uppercase")
        |> act("align_center")
        |> act("reset")

      assert state.text_source == :user
      refute state.transform_toupper
      assert state.alignment == :left
    end
  end
end
