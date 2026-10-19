defmodule Bbparty.Keyboard.CommissioningWalkTest do
  use Bbparty.DataCase, async: false

  import ExUnit.CaptureIO, only: [with_io: 1]

  alias Bbparty.Bus.Module3Dispatcher
  alias Bbparty.Keyboard
  alias Bbparty.Keyboard.Commissioning
  alias Bbparty.Layout
  alias Hardware.Components.PushButton
  alias Hardware.PhysicalComponent

  @a {15, 20}
  @b {15, 25}
  @c {15, 24}

  setup do
    on_exit(&Module3Dispatcher.unsubscribe/0)
    :ok
  end

  defp id({drive, sense}), do: String.to_atom(Keyboard.key_id(drive, sense))

  defp register(address, attrs \\ %{}) do
    key = id(address)
    attrs = Map.merge(%{char: nil, shift: nil, action: nil}, attrs)
    {:ok, _} = Layout.create_component(key, PushButton, attrs, %{"x" => 0, "y" => 0})
    key
  end

  defp press_after(events) do
    Task.start_link(fn ->
      Enum.each(events, fn {delay, {drive, sense}} ->
        Process.sleep(delay)

        Phoenix.PubSub.broadcast(
          Bbparty.PubSub,
          Module3Dispatcher.topic(),
          {:module3, {:key_event, drive, sense, true}}
        )

        Phoenix.PubSub.broadcast(
          Bbparty.PubSub,
          Module3Dispatcher.topic(),
          {:module3, {:key_event, drive, sense, false}}
        )
      end)
    end)
  end

  defp walk(opts, events) do
    press_after(events)
    with_io(fn -> Commissioning.walk_keyboard(Keyword.put_new(opts, :timeout, 300)) end)
  end

  describe "walk_keyboard/1" do
    test "presses become a row, in order, and are written to the layout" do
      a = register(@a)
      b = register(@b)

      {report, _io} = walk([row: 1, pitch: 10], [{20, @a}, {20, @b}])

      assert Enum.map(report.cells, & &1.key) == [a, b]
      assert Layout.get_component(a).position == %{"x" => 0, "y" => 10}
      assert Layout.get_component(b).position == %{"x" => 10, "y" => 10}
    end

    test "the row's keys are grouped, so the canvas draws and drags it as one" do
      a = register(@a)
      b = register(@b)

      {report, _io} = walk([row: 1], [{20, @a}, {20, @b}])

      assert report.group == "row_1"
      assert Layout.get_component(a).group_id == "row_1"
      assert Layout.get_component(b).group_id == "row_1"
    end

    test "the group can be named, or refused" do
      a = register(@a)
      b = register(@b)

      walk([row: 0, group: "thumb_cluster"], [{20, @a}])
      walk([row: 1, group: nil], [{20, @b}])

      assert Layout.get_component(a).group_id == "thumb_cluster"
      assert Layout.get_component(b).group_id == nil
    end

    test "re-walking a row releases the keys that are no longer on it" do
      a = register(@a)
      b = register(@b)

      walk([row: 0], [{20, @a}, {20, @b}])
      {_report, io} = walk([row: 0], [{20, @a}])

      assert Layout.get_component(a).group_id == "row_0"
      assert Layout.get_component(b).group_id == nil
      assert io =~ "released from row_0"
    end

    test "a partial redo leaves the head of the row alone" do
      a = register(@a)
      b = register(@b)

      walk([row: 0], [{20, @a}, {20, @b}])
      walk([row: 0, col: 1], [{20, @b}])

      assert Layout.get_component(a).group_id == "row_0"
      assert Layout.get_component(b).group_id == "row_0"
    end

    test "another row's keys are not released" do
      a = register(@a)
      b = register(@b)

      walk([row: 0], [{20, @a}])
      walk([row: 1], [{20, @b}])

      assert Layout.get_component(a).group_id == "row_0"
      assert Layout.get_component(b).group_id == "row_1"
    end

    test "a release is not a press" do
      register(@a)
      register(@b)

      {report, _io} = walk([row: 0], [{20, @a}, {20, @b}])

      assert length(report.cells) == 2
    end

    test "a key pressed twice keeps its column" do
      a = register(@a)
      b = register(@b)

      {report, io} = walk([row: 0, pitch: 10], [{20, @a}, {20, @a}, {20, @b}])

      assert Enum.map(report.cells, &{&1.key, &1.col}) == [{a, 0}, {b, 1}]
      assert io =~ "already column 0"
    end

    test "the row closes on quiet, not on a count" do
      register(@a)

      {report, _io} = walk([row: 0], [{20, @a}])

      assert length(report.cells) == 1
    end

    test "write: false plans the row without moving anything" do
      a = register(@a)

      {report, _io} = walk([row: 1, pitch: 10, write: false], [{20, @a}])

      assert report.plan == [{a, %{"x" => 0, "y" => 10}}]
      assert Layout.get_component(a).position == %{"x" => 0, "y" => 0}
      assert Layout.get_component(a).group_id == nil
    end

    test "a key that is not in the layout is reported and skipped" do
      {report, io} = walk([row: 0], [{20, @a}])

      assert length(report.cells) == 1
      assert io =~ "not in the layout"
    end

    test "an address off the wired set is named, not turned into a key" do
      {report, io} = walk([row: 0], [{20, {2, 2}}])

      assert report.cells == []
      assert io =~ "outside the matrix"
    end

    test "meanings can be given in the same command" do
      a = register(@a)
      b = register(@b)

      {report, _io} =
        walk([row: 0, chars: "az", shift: "AZ"], [{20, @a}, {20, @b}])

      assert report.meanings.assignments == [
               {a, %{char: "a", shift: "A"}},
               {b, %{char: "z", shift: "Z"}}
             ]

      assert Layout.get_component(a).attrs.char == "a"
      assert Layout.get_component(b).attrs.shift == "Z"
    end

    test "leaves no subscription behind" do
      register(@a)
      walk([row: 0], [{20, @a}])

      Phoenix.PubSub.broadcast(
        Bbparty.PubSub,
        Module3Dispatcher.topic(),
        {:module3, {:key_event, 15, 20, true}}
      )

      refute_receive {:module3, _}, 100
    end
  end

  describe "assign_row/3" do
    setup do
      a = register(@a)
      b = register(@b)
      c = register(@c)

      {:ok, _} =
        Layout.move_components([
          {a, %{"x" => 0, "y" => 120}},
          {b, %{"x" => 120, "y" => 120}},
          {c, %{"x" => 240, "y" => 0}}
        ])

      Layout.set_group([a, b], "row_1")
      Layout.set_group([c], "row_0")

      %{a: a, b: b, c: c}
    end

    test "finds the row by its group, not by where it has been dragged", %{a: a, b: b} do
      {:ok, _} =
        Layout.move_components([{a, %{"x" => 17, "y" => 903}}, {b, %{"x" => 400, "y" => 5}}])

      {_result, _io} = with_io(fn -> Commissioning.assign_row(1, chars: "az") end)

      assert Layout.get_component(a).attrs.char == "a"
      assert Layout.get_component(b).attrs.char == "z"
    end

    test "a row grouped by hand can be named directly", %{c: c} do
      Layout.set_group([c], "thumb_cluster")

      {_result, _io} =
        with_io(fn -> Commissioning.assign_row(0, [chars: "!"], group: "thumb_cluster") end)

      assert Layout.get_component(c).attrs.char == "!"
    end

    test "writes the legend onto the row the layout holds", %{a: a, b: b, c: c} do
      {_result, _io} = with_io(fn -> Commissioning.assign_row(1, chars: "az") end)

      assert Layout.get_component(a).attrs.char == "a"
      assert Layout.get_component(b).attrs.char == "z"
      assert Layout.get_component(c).attrs.char == nil
    end

    test "an action key keeps the char it already had", %{a: a} do
      {:ok, _} = Layout.set_component_attr(a, :char, "!")

      {_result, _io} = with_io(fn -> Commissioning.assign_row(1, actions: [:backspace]) end)

      attrs = Layout.get_component(a).attrs
      assert attrs.action == "backspace"
      assert attrs.char == "!"
    end

    test "a running key takes its new meaning at once", %{a: a} do
      {:ok, _pid} = PhysicalComponent.start(a, Layout.get_component(a))
      on_exit(fn -> PhysicalComponent.stop(a) end)

      {_result, _io} = with_io(fn -> Commissioning.assign_row(1, chars: "a") end)

      assert %PushButton{char: "a"} = PhysicalComponent.query_state(a)
    end

    test "write: false reports the assignment without persisting it", %{a: a} do
      {result, _io} =
        with_io(fn -> Commissioning.assign_row(1, [chars: "a"], write: false) end)

      assert result.assignments == [{a, %{char: "a"}}]
      assert Layout.get_component(a).attrs.char == nil
    end

    test "a row nobody walked assigns nothing" do
      {result, _io} = with_io(fn -> Commissioning.assign_row(7, chars: "abc") end)

      assert result.assignments == []
      assert result.overflow == 3
    end
  end

  describe "keyboard_report/1" do
    test "prints the rows the layout believes in" do
      a = register(@a, %{char: "a"})
      b = register(@b, %{action: "backspace"})
      c = register(@c)

      {:ok, _} =
        Layout.move_components([
          {a, %{"x" => 0, "y" => 0}},
          {b, %{"x" => 120, "y" => 0}},
          {c, %{"x" => 0, "y" => 120}}
        ])

      Layout.set_group([a, b], "row_0")

      {rows, io} = with_io(fn -> Commissioning.keyboard_report() end)

      assert [%{group: "row_0", cells: first}, %{group: "row_1", cells: _}] = rows
      assert Enum.map(first, & &1.key) == [a, b]
      assert io =~ "a [backspace]"
      assert io =~ "·"
    end
  end
end
