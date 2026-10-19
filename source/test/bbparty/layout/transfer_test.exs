defmodule Bbparty.Layout.TransferTest do
  use ExUnit.Case, async: true

  alias Bbparty.Layout.Transfer

  @registry %{
    "Hardware.Components.PushButton" => [char: :string, shift: :string],
    "Elixir.Hardware.Components.NeedleGauge" => [duty_min: :integer, duty_max: :integer],
    "Hardware.Components.Trackball" => []
  }

  defp row(overrides \\ %{}) do
    Map.merge(
      %{
        component_id: "key_a",
        module: "Elixir.Hardware.Components.PushButton",
        attrs: %{"char" => "A"},
        position: %{"x" => 10, "y" => 20},
        group_id: nil
      },
      overrides
    )
  end

  defp file(components, overrides \\ %{}) do
    Map.merge(
      %{"format" => "bbparty.layout", "version" => 1, "components" => components},
      overrides
    )
  end

  defp component(overrides \\ %{}) do
    Map.merge(
      %{
        "component_id" => "key_a",
        "module" => "Hardware.Components.PushButton",
        "attrs" => %{"char" => "A"},
        "position" => %{"x" => 10, "y" => 20},
        "group_id" => nil
      },
      overrides
    )
  end

  defp errors(result) do
    {:error, problems} = result
    Enum.map(problems, &{&1.component_id, &1.field, &1.error})
  end

  describe "encode/1" do
    test "writes the versioned envelope and the five portable fields" do
      assert %{"format" => "bbparty.layout", "version" => 1, "components" => [c]} =
               Transfer.encode([row()])

      assert Map.keys(c) |> Enum.sort() ==
               ~w(attrs component_id group_id module position)
    end

    test "carries no primary key and no timestamps" do
      %{"components" => [c]} =
        Transfer.encode([Map.merge(row(), %{id: 42, inserted_at: ~U[2026-01-01 00:00:00Z]})])

      refute Map.has_key?(c, "id")
      refute Map.has_key?(c, "inserted_at")
      refute Map.has_key?(c, "updated_at")
    end

    test "module names are written in alias form" do
      %{"components" => [c]} = Transfer.encode([row()])
      assert c["module"] == "Hardware.Components.PushButton"
    end

    test "accepts atom or string keyed rows and atom module names" do
      %{"components" => [c]} =
        Transfer.encode([
          %{
            "component_id" => :key_a,
            "module" => Hardware.Components.PushButton,
            "attrs" => %{char: "A"},
            "position" => nil,
            "group_id" => :keyboard
          }
        ])

      assert c == %{
               "component_id" => "key_a",
               "module" => "Hardware.Components.PushButton",
               "attrs" => %{"char" => "A"},
               "position" => nil,
               "group_id" => "keyboard"
             }
    end

    test "nil attrs become an empty object" do
      %{"components" => [c]} = Transfer.encode([row(%{attrs: nil})])
      assert c["attrs"] == %{}
    end

    test "components are sorted by component_id, so row order never shows in a diff" do
      %{"components" => components} =
        Transfer.encode([
          row(%{component_id: "c"}),
          row(%{component_id: "a"}),
          row(%{component_id: "b"})
        ])

      assert Enum.map(components, & &1["component_id"]) == ~w(a b c)
    end
  end

  describe "to_json/1" do
    test "is stable: the same rows in any order produce identical bytes" do
      rows = [row(%{component_id: "a"}), row(%{component_id: "b"})]
      assert Transfer.to_json(rows) == Transfer.to_json(Enum.reverse(rows))
    end

    test "holds no timestamp, so an unchanged layout re-exports identically" do
      refute Transfer.to_json([row()]) =~ "exported_at"
    end
  end

  describe "decode/1" do
    test "round-trips through JSON" do
      {:ok, envelope} = Transfer.decode(Transfer.to_json([row()]))
      assert {:ok, [decoded]} = Transfer.validate(envelope, @registry)
      assert decoded == row()
    end

    test "malformed JSON is a structured problem, not a raise" do
      assert errors(Transfer.decode("{oops")) == [{nil, :file, :malformed_json}]
    end
  end

  describe "validate/1 envelope" do
    test "accepts a valid file" do
      assert {:ok, [_]} = Transfer.validate(file([component()]), @registry)
    end

    test "rejects a foreign format" do
      assert {nil, :format, :unknown_format} in errors(
               Transfer.validate(file([], %{"format" => "something.else"}), @registry)
             )
    end

    test "rejects an unsupported version rather than guessing" do
      assert {nil, :version, :unsupported_version} in errors(
               Transfer.validate(file([], %{"version" => 2}), @registry)
             )
    end

    test "rejects components that are not a list" do
      assert {nil, :components, :not_a_list} in errors(
               Transfer.validate(file([], %{"components" => %{}}), @registry)
             )
    end

    test "rejects a non-object envelope" do
      assert errors(Transfer.validate("nope", @registry)) == [{nil, :envelope, :not_an_object}]
    end
  end

  describe "validate/1 rows" do
    test "rejects an unknown module" do
      assert errors(
               Transfer.validate(
                 file([component(%{"module" => "Hardware.Components.Teleporter"})]),
                 @registry
               )
             ) == [{"key_a", :module, :unknown_module}]
    end

    test "accepts either module spelling" do
      assert {:ok, [a]} = Transfer.validate(file([component()]), @registry)

      assert {:ok, [b]} =
               Transfer.validate(
                 file([component(%{"module" => "Elixir.Hardware.Components.PushButton"})]),
                 @registry
               )

      assert a.module == "Elixir.Hardware.Components.PushButton"
      assert a.module == b.module
    end

    test "rejects a missing or empty component_id" do
      assert {nil, :component_id, :invalid_component_id} in errors(
               Transfer.validate(file([component(%{"component_id" => ""})]), @registry)
             )

      assert {nil, :component_id, :invalid_component_id} in errors(
               Transfer.validate(file([Map.delete(component(), "component_id")]), @registry)
             )
    end

    test "rejects duplicate component_ids inside the file" do
      assert errors(Transfer.validate(file([component(), component()]), @registry)) ==
               [{"key_a", :component_id, :duplicate_component_id}]
    end

    test "rejects malformed positions" do
      for bad <- [%{"x" => 1}, %{"x" => "10", "y" => 2}, [1, 2], "10,20"] do
        assert {"key_a", :position, :malformed_position} in errors(
                 Transfer.validate(file([component(%{"position" => bad})]), @registry)
               )
      end
    end

    test "accepts a null position and a null group_id" do
      assert {:ok, [r]} =
               Transfer.validate(
                 file([component(%{"position" => nil, "group_id" => nil})]),
                 @registry
               )

      assert r.position == nil and r.group_id == nil
    end

    test "rejects a non-string group_id" do
      assert {"key_a", :group_id, :invalid_group_id} in errors(
               Transfer.validate(file([component(%{"group_id" => 3})]), @registry)
             )
    end

    test "rejects attrs outside the module's editable_fields" do
      assert errors(
               Transfer.validate(
                 file([component(%{"attrs" => %{"char" => "A", "colour" => "red"}})]),
                 @registry
               )
             ) == [{"key_a", :attrs, :unknown_attr}]
    end

    test "a module with no editable fields accepts no attrs at all" do
      assert errors(
               Transfer.validate(
                 file([
                   component(%{
                     "component_id" => "ball",
                     "module" => "Hardware.Components.Trackball",
                     "attrs" => %{"speed" => 3}
                   })
                 ]),
                 @registry
               )
             ) == [{"ball", :attrs, :unknown_attr}]
    end

    test "rejects attrs that are not an object" do
      assert {"key_a", :attrs, :not_an_object} in errors(
               Transfer.validate(file([component(%{"attrs" => [1, 2]})]), @registry)
             )
    end

    test "missing attrs default to an empty map" do
      assert {:ok, [r]} = Transfer.validate(file([Map.delete(component(), "attrs")]), @registry)
      assert r.attrs == %{}
    end

    test "rejects a component that is not an object" do
      assert errors(Transfer.validate(file(["nope"]), @registry)) ==
               [{nil, :component, :not_an_object}]
    end
  end

  describe "validate/1 reports everything at once" do
    test "collects problems across rows and fields" do
      problems =
        errors(
          Transfer.validate(
            file([
              component(%{"module" => "Hardware.Components.Teleporter"}),
              component(%{
                "component_id" => "gauge",
                "module" => "Hardware.Components.NeedleGauge",
                "position" => "nope",
                "attrs" => %{"nope" => 1}
              }),
              component(%{
                "component_id" => "gauge",
                "module" => "Hardware.Components.NeedleGauge",
                "attrs" => %{}
              })
            ]),
            @registry
          )
        )

      assert {"key_a", :module, :unknown_module} in problems
      assert {"gauge", :position, :malformed_position} in problems
      assert {"gauge", :attrs, :unknown_attr} in problems
      assert {"gauge", :component_id, :duplicate_component_id} in problems
      assert length(problems) == 4
    end

    test "every unknown attr key is listed, not just the first" do
      problems =
        Transfer.validate(
          file([component(%{"attrs" => %{"a" => 1, "b" => 2}})]),
          @registry
        )

      assert {:error, [%{value: "a"}, %{value: "b"}]} = problems
    end
  end

  describe "format_problems/1" do
    test "renders one readable line per problem" do
      {:error, problems} =
        Transfer.validate(file([component(%{"module" => "Nope"})], %{"version" => 9}), @registry)

      text = Transfer.format_problems(problems)
      assert text =~ "file: version: unsupported_version"
      refute text =~ "Nope"
    end

    test "names the offending component" do
      {:error, problems} = Transfer.validate(file([component(%{"module" => "Nope"})]), @registry)

      assert Transfer.format_problems(problems) =~
               ~s|component #0 (key_a): module: unknown_module|
    end
  end

  describe "module name helpers" do
    test "short_module/1 and long_module/1 are inverses" do
      assert Transfer.short_module(Hardware.Components.PushButton) ==
               "Hardware.Components.PushButton"

      assert Transfer.long_module("Hardware.Components.PushButton") ==
               "Elixir.Hardware.Components.PushButton"

      assert Transfer.long_module("Elixir.Hardware.Components.PushButton") ==
               "Elixir.Hardware.Components.PushButton"
    end
  end
end
