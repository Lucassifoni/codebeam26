defmodule Bbparty.RenderStateFeaturesTest do
  use ExUnit.Case, async: true

  alias Bbparty.FontMap
  alias Bbparty.RenderState
  alias Bbparty.RenderState.Projections

  @rich "Boogy Brut Bold"
  @bare "BBWB"

  defp fold(state, event) do
    {new_state, commands, _effects} = RenderState.apply(state, event)
    {new_state, commands}
  end

  defp toggle(state, tag), do: fold(state, {:switch_0_0, :toggle_feature, tag})
  defp set(state, tag, on?), do: fold(state, {:switch_3_0, :set_feature, {tag, on?}})
  defp select(state, font), do: fold(state, {:tag_reader, :select_font, font})

  defp state_after(result), do: elem(result, 0)

  defp command_for(commands, tag) do
    for {{:feature, ^tag} = _target, command} <- commands, do: command
  end

  describe "the toggle grid" do
    test "a transition adds the feature" do
      {state, _} = toggle(RenderState.new(), "liga")
      assert "liga" in state.cumulative_features
    end

    test "toggling twice restores the set" do
      before = RenderState.new()

      after_two =
        before
        |> toggle("liga")
        |> state_after()
        |> toggle("liga")
        |> state_after()

      assert after_two.cumulative_features == before.cumulative_features
    end

    test "features accumulate in the order they were turned on" do
      state =
        RenderState.new()
        |> toggle("smcp")
        |> state_after()
        |> toggle("liga")
        |> state_after()

      assert state.cumulative_features == ["smcp", "liga"]
    end
  end

  describe "the value grid" do
    test "the position is the value, and repeating it changes nothing" do
      state = RenderState.new() |> set("dlig", true) |> state_after()
      assert "dlig" in state.cumulative_features

      again = state |> set("dlig", true) |> state_after()
      assert again.cumulative_features == state.cumulative_features
    end

    test "turning one off that was never on is not an error" do
      before = RenderState.new()
      {state, _} = set(before, "dlig", false)
      assert state.cumulative_features == before.cumulative_features
    end

    test "a whole snapshot's worth of positions applies as state" do
      state =
        Enum.reduce([{"liga", true}, {"dlig", false}, {"smcp", true}], RenderState.new(), fn
          {tag, on?}, acc -> acc |> set(tag, on?) |> state_after()
        end)

      assert "liga" in state.cumulative_features
      assert "smcp" in state.cumulative_features
      refute "dlig" in state.cumulative_features
    end
  end

  describe "an active feature under a font that lacks it" do
    test "stays in the set" do
      state =
        RenderState.new()
        |> toggle("liga")
        |> state_after()
        |> select(@bare)
        |> state_after()

      assert "liga" in state.cumulative_features
    end

    test "is projected as unavailable, while still active" do
      state = RenderState.new() |> toggle("liga") |> state_after()
      {_state, commands} = select(state, @bare)

      assert command_for(commands, "liga") == [{:set_available, false}]

      {_state, commands} = select(state, @rich)
      assert command_for(commands, "liga") == [{:set_available, true}]
    end
  end

  describe "projections" do
    test "a toggle tells every switch what it now is, by feature and not by id" do
      {_state, commands} = toggle(RenderState.new(), "liga")

      assert command_for(commands, "liga") == [{:set_active, true}]
      assert command_for(commands, "dlig") == [{:set_active, false}]
      assert length(commands) == length(FontMap.all_features())
    end

    test "every target is a feature address" do
      {_state, commands} = toggle(RenderState.new(), "liga")

      assert Enum.all?(commands, fn {target, _command} -> match?({:feature, _tag}, target) end)
    end

    test "selecting a font reflects availability onto every feature" do
      {_state, commands} = select(RenderState.new(), @rich)
      available = FontMap.features_for_font(@rich)

      for tag <- FontMap.all_features() do
        assert command_for(commands, tag) == [{:set_available, tag in available}]
      end
    end

    test "selecting a font shows it on the selector" do
      {_state, commands} = select(RenderState.new(), @rich)

      assert {{:field, :selected_font}, {:set_font, @rich}} in commands
    end

    test "a hard reset clears the selector, which never chose the font itself" do
      state = RenderState.new() |> select(@rich) |> state_after()
      {reset, _effects} = RenderState.hard_reset()

      assert {{:field, :selected_font}, {:set_font, nil}} in Projections.propagate(state, reset)
    end

    test "a full sync shows the font on the selector" do
      state = RenderState.new() |> select(@rich) |> state_after()

      assert {{:field, :selected_font}, {:set_font, @rich}} in Projections.sync(state)
    end

    test "the selector and the knob are reached by meaning, not by name" do
      refute MapSet.member?(RenderState.referenced_ids(), "font_selector")
      refute MapSet.member?(RenderState.referenced_ids(), "text_quantity")
    end

    test "a full sync carries both halves for every feature" do
      state =
        RenderState.new() |> toggle("liga") |> state_after() |> select(@rich) |> state_after()

      commands = Projections.sync(state)

      assert {:set_active, true} in command_for(commands, "liga")
      assert {:set_available, true} in command_for(commands, "liga")
    end
  end

  describe "the composite switch" do
    @composite "smcp+c2sc"

    test "goes into the set as one entry" do
      state = RenderState.new() |> toggle(@composite) |> state_after()

      assert state.cumulative_features == [@composite]
      refute "c2sc" in state.cumulative_features
    end

    test "is a switch of its own: it does not follow the plain smcp lever" do
      state = RenderState.new() |> toggle("smcp") |> state_after()

      refute @composite in state.cumulative_features
    end

    test "is available only under a font that carries both tags" do
      {_state, commands} = select(RenderState.new(), @bare)
      assert command_for(commands, @composite) == [{:set_available, false}]

      {_state, commands} = select(RenderState.new(), @rich)
      assert command_for(commands, @composite) == [{:set_available, true}]
    end
  end

  describe "RESET" do
    defp reset(state),
      do: fold(state, {:some_key, :key_down, %{char: nil, shift: nil, action: "reset"}})

    test "clears the stylistic sets and the projection follows" do
      state = RenderState.new() |> toggle("ss01") |> state_after()

      {reset, commands} = reset(state)

      refute "ss01" in reset.cumulative_features
      assert command_for(commands, "ss01") == [{:set_active, false}]
    end

    test "leaves a lever's feature on, since the lever is still thrown" do
      state =
        RenderState.new()
        |> toggle("liga")
        |> state_after()
        |> toggle("smcp+c2sc")
        |> state_after()
        |> toggle("ss12")
        |> state_after()

      {reset, _commands} = reset(state)

      assert reset.cumulative_features == ["liga", "smcp+c2sc"]
    end

    test "keeps the font, and with it every lamp's availability" do
      state = RenderState.new() |> select(@rich) |> state_after()

      {reset, commands} = reset(state)

      assert reset.selected_font == @rich
      assert Enum.filter(commands, &match?({_, {:set_available, _}}, &1)) == []
    end
  end

  describe "what the fold refuses" do
    test "a feature that is not a string" do
      before = RenderState.new()
      assert state_after(fold(before, {:x, :toggle_feature, :liga})) == before
      assert state_after(fold(before, {:x, :toggle_feature, nil})) == before
    end

    test "a position that is not a boolean" do
      before = RenderState.new()
      assert state_after(fold(before, {:x, :set_feature, {"liga", 1}})) == before
      assert state_after(fold(before, {:x, :set_feature, "liga"})) == before
    end
  end

  describe "the layout fingerprint" do
    test "moves when the feature set does — the page has to be re-measured" do
      before = RenderState.new()
      after_toggle = before |> toggle("liga") |> state_after()

      refute RenderState.layout_fingerprint(before) ==
               RenderState.layout_fingerprint(after_toggle)
    end
  end
end
