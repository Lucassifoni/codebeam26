defmodule Bbparty.LayoutTest do
  use Bbparty.DataCase, async: true

  alias Bbparty.Layout
  alias Bbparty.RenderState
  alias Hardware.Components.PushButton

  describe "create_component/4" do
    test "stores an explicit position" do
      {:ok, _} = Layout.create_component(:key_1_2, PushButton, %{}, %{"x" => 24, "y" => 48})

      assert Layout.get_component(:key_1_2).position == %{"x" => 24, "y" => 48}
    end

    test "a second insert on the same id fails on the unique index" do
      {:ok, _} = Layout.create_component(:key_1_2, PushButton)

      assert {:error, changeset} = Layout.create_component(:key_1_2, PushButton)
      refute changeset.valid?
    end
  end

  describe "move_components/1" do
    defp key_at(row, column) do
      drive = Enum.at(Bbparty.Keyboard.drive_lines(), row)
      sense = Enum.at(Bbparty.Keyboard.sense_lines(), column)
      String.to_atom("key_#{drive}_#{sense}")
    end

    setup do
      {:ok, _} = Layout.create_component(key_at(0, 0), PushButton, %{}, %{"x" => 7, "y" => 7})
      {:ok, _} = Layout.create_component(key_at(1, 2), PushButton, %{}, %{"x" => 7, "y" => 7})
      :ok
    end

    test "applies a whole plan" do
      plan = Bbparty.Keyboard.grid_plan([key_at(0, 0), key_at(1, 2)])

      assert {:ok, moved} = Layout.move_components(plan)
      assert length(moved) == 2
      assert Layout.get_component(key_at(0, 0)).position == %{"x" => 0, "y" => 0}
      assert Layout.get_component(key_at(1, 2)).position == %{"x" => 240, "y" => 120}
    end

    test "an unknown id rolls the whole plan back" do
      plan = Bbparty.Keyboard.grid_plan([key_at(0, 0), key_at(4, 4)])

      assert catch_error(Layout.move_components(plan))
      assert Layout.get_component(key_at(0, 0)).position == %{"x" => 7, "y" => 7}
    end
  end

  describe "rename_component/2" do
    setup do
      {:ok, _} = Layout.create_component(:key_1_2, PushButton, %{char: "a"})
      :ok
    end

    test "moves the row to the new id, keeping its attrs" do
      assert {:ok, _} = Layout.rename_component(:key_1_2, :key_3_4)

      assert [%{component_id: :key_3_4} = instance] = Layout.list_components()
      assert instance.attrs.char == "a"
    end

    test "refuses an id the render graph names literally" do
      referenced = RenderState.referenced_ids() |> Enum.at(0) |> String.to_atom()

      assert {:error, :referenced_by_graph} = Layout.rename_component(:key_1_2, referenced)
      assert [%{component_id: :key_1_2}] = Layout.list_components()
    end

    test "refuses to rename away from a graph-referenced id" do
      referenced = RenderState.referenced_ids() |> Enum.at(0) |> String.to_atom()
      {:ok, _} = Layout.create_component(referenced, PushButton)

      assert {:error, :referenced_by_graph} = Layout.rename_component(referenced, :key_9_9)
    end

    test "refuses a collision with an existing component" do
      {:ok, _} = Layout.create_component(:key_3_4, PushButton)

      assert {:error, changeset} = Layout.rename_component(:key_1_2, :key_3_4)
      refute changeset.valid?
    end

    test "reports a missing component rather than raising" do
      assert {:error, :not_found} = Layout.rename_component(:key_9_9, :key_8_8)
    end
  end
end
