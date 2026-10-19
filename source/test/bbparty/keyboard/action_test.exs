defmodule Bbparty.Keyboard.ActionTest do
  use ExUnit.Case, async: true

  alias Bbparty.Keyboard.Action

  test "the panel's control keys are the whole vocabulary" do
    assert Enum.sort(Action.all()) ==
             Enum.sort(~w(
                 up down left right backspace enter space shift capslock reset print dead
                 align_left align_center uppercase
                 source_user source_font_name source_alpha_upper source_alpha_lower
                 source_numbers
               )a)
  end

  test "dead is the only action that reads the key's char" do
    assert Action.dead?(:dead)
    assert Action.parse("dead") == {:ok, :dead}

    for action <- Action.all() -- [:dead] do
      refute Action.dead?(action), "#{action} ignores char, it does not arm it"
    end
  end

  test "the selectors are the keys that carry an LED" do
    assert Enum.sort(Action.selectors()) ==
             Enum.sort(~w(
                 align_left align_center uppercase
                 source_user source_font_name source_alpha_upper source_alpha_lower
                 source_numbers
               )a)

    assert Enum.all?(Action.selectors(), &(&1 in Action.all()))
    assert length(Action.selectors()) == 8
  end

  test "reset, print and the selectors are not editing actions" do
    refute Action.editing?(:reset)
    refute Action.editing?(:print)

    for action <- Action.selectors() do
      refute Action.editing?(action), "#{action} selects a state, it does not edit"
    end

    for action <- (Action.all() -- [:reset, :print]) -- Action.selectors() do
      assert Action.editing?(action), "#{action} should be an editing action"
    end
  end

  test "parses what the inspector stores, forgiving case and stray whitespace" do
    assert Action.parse("UP") == {:ok, :up}
    assert Action.parse(" capslock ") == {:ok, :capslock}
    assert Action.parse("BackSpace") == {:ok, :backspace}
    assert Action.parse(:enter) == {:ok, :enter}
  end

  test "an unknown or absent value is inert, so the key types its char instead" do
    for value <- [nil, "", "BACKSPCE", "ctrl", "  ", 42] do
      assert Action.parse(value) == :error
    end
  end

  test "names the two actions a text offset cannot answer on its own" do
    assert Enum.filter(Action.all(), &Action.layout_dependent?/1) == [:up, :down]
  end
end
