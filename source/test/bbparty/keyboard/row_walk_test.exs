defmodule Bbparty.Keyboard.RowWalkTest do
  use ExUnit.Case, async: true

  alias Bbparty.Keyboard
  alias Bbparty.Keyboard.RowWalk

  defp press!(walk, key) do
    {:ok, walk, cell} = RowWalk.press(walk, key)
    {walk, cell}
  end

  defp fill(walk, keys), do: Enum.reduce(keys, walk, &elem(press!(&2, &1), 0))

  defp component(id, position, attrs \\ %{}, group_id \\ nil) do
    %{
      component_id: id,
      position: position,
      group_id: group_id,
      attrs: Map.merge(%{char: nil, shift: nil, action: nil}, attrs)
    }
  end

  describe "forming a row" do
    test "the n-th distinct press is column n" do
      {walk, first} = press!(RowWalk.new(row: 2), :key_15_20)
      {_walk, second} = press!(walk, :key_15_25)

      assert %{row: 2, col: 0} = first
      assert %{row: 2, col: 1} = second
    end

    test "positions follow the pitch and origin" do
      walk = RowWalk.new(row: 1, pitch: 10, origin: {-100, -200})

      {walk, first} = press!(walk, :key_15_20)
      {_walk, second} = press!(walk, :key_15_25)

      assert first.position == %{"x" => -100, "y" => -190}
      assert second.position == %{"x" => -90, "y" => -190}
    end

    test "the pitch defaults to the keyboard's" do
      {_walk, cell} = press!(RowWalk.new(row: 1), :key_15_20)

      assert cell.position == %{"x" => 0, "y" => Keyboard.pitch()}
    end

    test "a key pressed twice keeps the column it has" do
      walk = fill(RowWalk.new(), [:key_15_20, :key_15_25])

      assert {:error, {:already_in_row, :key_15_20, 0}} = RowWalk.press(walk, :key_15_20)

      {walk, next} = press!(walk, :key_15_24)
      assert next.col == 2
      assert RowWalk.keys(walk) == [:key_15_20, :key_15_25, :key_15_24]
    end

    test "starting at a column redoes the tail of a row" do
      {_walk, cell} = press!(RowWalk.new(row: 0, col: 4, pitch: 10), :key_15_20)

      assert cell.col == 4
      assert cell.position == %{"x" => 40, "y" => 0}
    end

    test "an already-placed key reports the column it actually has" do
      walk = RowWalk.new(col: 4) |> fill([:key_15_20, :key_15_25])

      assert {:error, {:already_in_row, :key_15_25, 5}} = RowWalk.press(walk, :key_15_25)
    end

    test "the plan is ready for Layout.move_components/1" do
      walk = RowWalk.new(row: 1, pitch: 10) |> fill([:key_15_20, :key_15_25])

      assert RowWalk.plan(walk) == [
               {:key_15_20, %{"x" => 0, "y" => 10}},
               {:key_15_25, %{"x" => 10, "y" => 10}}
             ]
    end

    test "an untouched row reports nothing" do
      report = RowWalk.report(RowWalk.new(row: 3))

      assert report == %{row: 3, group: "row_3", cells: [], plan: []}
    end

    test "the row is its own group unless one is named" do
      assert RowWalk.new(row: 2).group == RowWalk.group_id(2)
      assert RowWalk.new(row: 2, group: "thumb_cluster").group == "thumb_cluster"
      assert RowWalk.new(row: 2, group: nil).group == nil
    end
  end

  describe "meanings/2" do
    test "a string of chars lands on the row in order" do
      result = RowWalk.meanings([:a, :b, :c], chars: "xyz")

      assert result.assignments == [
               {:a, %{char: "x"}},
               {:b, %{char: "y"}},
               {:c, %{char: "z"}}
             ]

      assert result.untouched == []
      assert result.overflow == 0
    end

    test "shift runs in parallel with chars" do
      result = RowWalk.meanings([:a, :b], chars: "az", shift: "AZ")

      assert result.assignments == [
               {:a, %{char: "a", shift: "A"}},
               {:b, %{char: "z", shift: "Z"}}
             ]
    end

    test "an action is stored as the string the attr holds" do
      result = RowWalk.meanings([:a, :b], actions: [:shift, "BACKSPACE"])

      assert result.assignments == [{:a, %{action: "shift"}}, {:b, %{action: "backspace"}}]
    end

    test "a nil in a list leaves that key's attr alone" do
      result = RowWalk.meanings([:a, :b, :c], chars: [nil, "w", nil], actions: [:shift])

      assert result.assignments == [{:a, %{action: "shift"}}, {:b, %{char: "w"}}]
      assert result.untouched == [:c]
    end

    test "a grapheme spec assigns a space like any other char" do
      result = RowWalk.meanings([:a, :b], chars: "a ")

      assert result.assignments == [{:a, %{char: "a"}}, {:b, %{char: " "}}]
    end

    test "keys past the end of the spec are untouched" do
      result = RowWalk.meanings([:a, :b, :c], chars: "x")

      assert result.assignments == [{:a, %{char: "x"}}]
      assert result.untouched == [:b, :c]
      assert result.overflow == 0
    end

    test "a legend longer than the row is reported rather than dropped silently" do
      result = RowWalk.meanings([:a], chars: "xyz")

      assert result.overflow == 2
    end

    test "an unknown action is an error, and that key is not assigned" do
      result = RowWalk.meanings([:a, :b], chars: "xy", actions: [:backspce])

      assert result.errors == [{:a, {:unknown_action, :backspce}}]
      assert result.assignments == [{:b, %{char: "y"}}]
    end

    test "no spec at all touches nothing" do
      result = RowWalk.meanings([:a, :b], [])

      assert result.assignments == []
      assert result.untouched == [:a, :b]
    end
  end

  describe "rows/2 — reading the layout back" do
    test "a group is a row, whatever the keys' positions are" do
      components = [
        component(:key_15_25, %{"x" => 40, "y" => 900}, %{}, "row_0"),
        component(:key_15_20, %{"x" => 10, "y" => 30}, %{}, "row_0")
      ]

      assert [%{group: "row_0", cells: cells}] = RowWalk.rows(components)
      assert Enum.map(cells, & &1.key) == [:key_15_20, :key_15_25]
      assert Enum.map(cells, & &1.col) == [0, 1]
    end

    test "a grouped row is not split by the band its keys land in" do
      components = [
        component(:key_15_20, %{"x" => 0, "y" => 0}, %{}, "row_3"),
        component(:key_15_25, %{"x" => 120, "y" => 480}, %{}, "row_3")
      ]

      assert [%{group: "row_3", cells: [_, _]}] = RowWalk.rows(components)
    end

    test "keys with no group fall back to their position band" do
      components = [
        component(:key_15_25, %{"x" => 120, "y" => 0}, %{char: "b"}),
        component(:key_14_20, %{"x" => 0, "y" => 120}, %{char: "c"}),
        component(:key_15_20, %{"x" => 0, "y" => 0}, %{char: "a"})
      ]

      assert [%{group: "row_0", cells: first}, %{group: "row_1", cells: second}] =
               RowWalk.rows(components)

      assert Enum.map(first, & &1.key) == [:key_15_20, :key_15_25]
      assert Enum.map(second, & &1.char) == ["c"]
    end

    test "a group and a band with the same name are one row" do
      components = [
        component(:key_15_20, %{"x" => 0, "y" => 0}, %{}, "row_0"),
        component(:key_15_25, %{"x" => 120, "y" => 0})
      ]

      assert [%{group: "row_0", cells: [_, _]}] = RowWalk.rows(components)
    end

    test "a key nudged by hand stays on its band" do
      components = [
        component(:key_15_20, %{"x" => 3, "y" => 7}),
        component(:key_15_25, %{"x" => 118, "y" => -11})
      ]

      assert [%{group: "row_0", cells: cells}] = RowWalk.rows(components)
      assert Enum.map(cells, & &1.key) == [:key_15_20, :key_15_25]
    end

    test "rows come back top to bottom" do
      components = [
        component(:key_15_20, %{"x" => 0, "y" => 240}, %{}, "lower"),
        component(:key_15_25, %{"x" => 0, "y" => 0}, %{}, "upper")
      ]

      assert ["upper", "lower"] = Enum.map(RowWalk.rows(components), & &1.group)
    end

    test "anything that is not a module_3 key is dropped" do
      components = [
        component(:gauge_zoom, %{"x" => 0, "y" => 0}),
        component(:switch_0_0, %{"x" => 0, "y" => 0}),
        component(:key_15_20, %{"x" => 0, "y" => 0})
      ]

      assert [%{group: "row_0", cells: [%{key: :key_15_20}]}] = RowWalk.rows(components)
    end

    test "row_of/2 is the ordered keys of one row" do
      components = [
        component(:key_15_25, %{"x" => 120, "y" => 240}),
        component(:key_15_20, %{"x" => 0, "y" => 240}),
        component(:key_14_20, %{"x" => 0, "y" => 0})
      ]

      assert RowWalk.row_of(components, row: 2) == [:key_15_20, :key_15_25]
      assert RowWalk.row_of(components, row: 5) == []
    end

    test "row_of/2 can name a group made by hand in the control panel" do
      components = [
        component(:key_15_20, %{"x" => 0, "y" => 0}, %{}, "thumb_cluster"),
        component(:key_15_25, %{"x" => 120, "y" => 0})
      ]

      assert RowWalk.row_of(components, group: "thumb_cluster") == [:key_15_20]
      assert RowWalk.row_of(components, row: 0) == [:key_15_25]
    end

    test "the origin the walk used is the origin the read-back needs" do
      components = [component(:key_15_20, %{"x" => -100, "y" => -190})]

      assert RowWalk.row_of(components, row: 1, pitch: 10, origin: {-100, -200}) == [:key_15_20]
    end

    test "a component with no position reads as the origin row" do
      assert [%{group: "row_0"}] = RowWalk.rows([component(:key_15_20, nil)])
    end
  end
end
