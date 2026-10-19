defmodule Bbparty.Layout.TransferStoreTest do
  use Bbparty.DataCase, async: true

  alias Bbparty.Layout
  alias Bbparty.Layout.ComponentInstance
  alias Bbparty.Layout.Transfer
  alias Bbparty.Layout.TransferStore

  @button Hardware.Components.PushButton
  @gauge Hardware.Components.NeedleGauge

  defp seed_layout() do
    {:ok, _} = Layout.create_component(:key_a, @button, %{"char" => "A", "shift" => "Q"})
    {:ok, _} = Layout.create_component(:gauge_1, @gauge, %{"duty_min" => "10"})
    {:ok, _} = Layout.move_component(:key_a, %{"x" => 12, "y" => 34})
    Layout.set_group([:key_a, :gauge_1], "panel")
    :ok
  end

  defp ids() do
    Repo.all(ComponentInstance) |> Enum.map(& &1.component_id) |> Enum.sort()
  end

  describe "export/0" do
    test "returns the five portable fields, unhydrated" do
      seed_layout()

      assert [gauge, key] = TransferStore.export() |> Enum.sort_by(& &1.component_id)

      assert key == %{
               component_id: "key_a",
               module: "Elixir.Hardware.Components.PushButton",
               attrs: %{"char" => "A", "shift" => "Q"},
               position: %{"x" => 12, "y" => 34},
               group_id: "panel"
             }

      assert gauge.position == nil
      refute Map.has_key?(key, :id)
      refute Map.has_key?(key, :inserted_at)
    end

    test "an empty layout exports an empty component list" do
      assert TransferStore.export() == []
      assert %{"components" => []} = Jason.decode!(TransferStore.export_json())
    end
  end

  describe "known_modules/0" do
    test "finds the real component modules with their editable fields" do
      modules = TransferStore.known_modules()

      assert modules["Elixir.Hardware.Components.PushButton"] == @button.editable_fields()
      assert Map.has_key?(modules, "Elixir.Hardware.Components.Trackball")
    end

    test "includes a component that declares a second behaviour" do
      assert Map.has_key?(TransferStore.known_modules(), "Elixir.Hardware.Components.NeedleGauge")
    end

    test "excludes display modules and anything without the behaviour" do
      refute Map.has_key?(
               TransferStore.known_modules(),
               "Elixir.Hardware.Components.PushButton.Display"
             )
    end
  end

  describe "round trip" do
    test "export -> import -> export is byte-identical" do
      seed_layout()
      json = TransferStore.export_json()

      assert {:ok, _report} = TransferStore.import_json(json, :replace_all)
      assert TransferStore.export_json() == json
    end

    test "a real export validates against the real module registry" do
      seed_layout()
      {:ok, envelope} = Transfer.decode(TransferStore.export_json())
      assert {:ok, rows} = Transfer.validate(envelope, TransferStore.known_modules())
      assert length(rows) == 2
    end

    test "importing into an empty database recreates the layout" do
      seed_layout()
      json = TransferStore.export_json()
      Repo.delete_all(ComponentInstance)

      assert {:ok, report} = TransferStore.import_json(json, :replace_all)
      assert report.inserted == ["gauge_1", "key_a"]
      assert TransferStore.export_json() == json
    end
  end

  describe "import mode :replace_all" do
    test "deletes rows absent from the file" do
      seed_layout()
      {:ok, _} = Layout.create_component(:stale, @button, %{})
      json = json_with(["key_a", "gauge_1"])

      assert {:ok, report} = TransferStore.import_json(json, :replace_all)
      assert report.deleted == ["stale"]
      assert ids() == ["gauge_1", "key_a"]
    end

    test "reports what actually changed, not merely what was rewritten" do
      seed_layout()

      json =
        TransferStore.export()
        |> Enum.map(fn
          %{component_id: "key_a"} = row -> %{row | position: %{"x" => 99, "y" => 99}}
          row -> row
        end)
        |> Transfer.to_json()

      assert {:ok, report} = TransferStore.import_json(json, :replace_all)
      assert report.updated == ["key_a"]
      assert report.unchanged == ["gauge_1"]
      assert report.changed == ["key_a"]
    end
  end

  describe "import mode :merge" do
    test "keeps rows absent from the file and updates the overlap" do
      seed_layout()
      {:ok, _} = Layout.create_component(:kept, @button, %{})

      json =
        Transfer.to_json([
          %{
            component_id: "key_a",
            module: "Elixir.Hardware.Components.PushButton",
            attrs: %{"char" => "Z"},
            position: %{"x" => 1, "y" => 2},
            group_id: nil
          },
          %{
            component_id: "new_one",
            module: "Elixir.Hardware.Components.PushButton",
            attrs: %{},
            position: nil,
            group_id: nil
          }
        ])

      assert {:ok, report} = TransferStore.import_json(json, :merge)
      assert report.inserted == ["new_one"]
      assert report.updated == ["key_a"]
      assert report.deleted == []
      assert ids() == ["gauge_1", "kept", "key_a", "new_one"]

      updated = Repo.get_by(ComponentInstance, component_id: "key_a")
      assert updated.attrs == %{"char" => "Z"}
      assert updated.position == %{"x" => 1, "y" => 2}
      assert updated.group_id == nil
    end

    test "merging a file identical to the database changes nothing" do
      seed_layout()
      json = TransferStore.export_json()

      assert {:ok, report} = TransferStore.import_json(json, :merge)
      assert report.changed == []
      assert report.unchanged == ["gauge_1", "key_a"]
      assert TransferStore.export_json() == json
    end
  end

  describe "an invalid file leaves the database untouched" do
    test "unknown module" do
      seed_layout()
      before = TransferStore.export_json()

      json =
        ~s({"format":"bbparty.layout","version":1,"components":[) <>
          ~s({"component_id":"x","module":"Hardware.Components.Teleporter",) <>
          ~s("attrs":{},"position":null,"group_id":null}]})

      assert {:error, [%{error: :unknown_module}]} =
               TransferStore.import_json(json, :replace_all)

      assert TransferStore.export_json() == before
    end

    test "malformed JSON" do
      seed_layout()
      before = TransferStore.export_json()

      assert {:error, [%{error: :malformed_json}]} =
               TransferStore.import_json("{not json", :replace_all)

      assert TransferStore.export_json() == before
    end

    test "duplicate ids inside the file" do
      seed_layout()
      before = TransferStore.export_json()
      duplicated = json_with(["key_a", "key_a"])

      assert {:error, [%{error: :duplicate_component_id}]} =
               TransferStore.import_json(duplicated, :replace_all)

      assert TransferStore.export_json() == before
    end
  end

  describe "import_json/2 mode argument" do
    test "is required and cannot be anything else" do
      assert_raise FunctionClauseError, fn ->
        TransferStore.import_json(TransferStore.export_json(), :whatever)
      end
    end
  end

  describe "restart_components/1" do
    test "tolerates ids that no longer exist" do
      assert TransferStore.restart_components(["never_existed"]) == :ok
      assert TransferStore.restart_components([]) == :ok
    end
  end

  defp json_with(component_ids) do
    row = fn id ->
      %{
        component_id: id,
        module: "Elixir.Hardware.Components.PushButton",
        attrs: %{},
        position: nil,
        group_id: nil
      }
    end

    %{
      "format" => Transfer.format(),
      "version" => Transfer.version(),
      "components" =>
        Enum.map(component_ids, &Transfer.encode([row.(&1)])["components"]) |> List.flatten()
    }
    |> Jason.encode!()
  end
end
