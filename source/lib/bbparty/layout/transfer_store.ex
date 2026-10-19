defmodule Bbparty.Layout.TransferStore do
  import Ecto.Query

  alias Bbparty.Layout.ComponentInstance
  alias Bbparty.Layout.Transfer
  alias Bbparty.Repo
  alias Hardware.PhysicalComponent

  @modules_prefix "Elixir.Hardware.Components."

  @type mode :: :replace_all | :merge

  @type report :: %{
          inserted: [String.t()],
          updated: [String.t()],
          unchanged: [String.t()],
          deleted: [String.t()],
          changed: [String.t()]
        }

  @spec export() :: [Transfer.row()]
  def export() do
    from(c in ComponentInstance,
      select: %{
        component_id: c.component_id,
        module: c.module,
        attrs: c.attrs,
        position: c.position,
        group_id: c.group_id
      }
    )
    |> Repo.all()
  end

  @spec export_json() :: String.t()
  def export_json(), do: export() |> Transfer.to_json()

  @spec known_modules() :: Transfer.registry()
  def known_modules() do
    :code.all_available()
    |> Enum.map(fn {name, _path, _loaded} -> to_string(name) end)
    |> Enum.filter(&String.starts_with?(&1, @modules_prefix))
    |> Enum.map(&String.to_atom/1)
    |> Enum.filter(&component_module?/1)
    |> Map.new(fn module -> {to_string(module), editable_fields(module)} end)
  end

  defp component_module?(module) do
    Code.ensure_loaded?(module) and Hardware.Component in behaviours(module)
  end

  defp behaviours(module) do
    module.__info__(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()
  end

  defp editable_fields(module) do
    case function_exported?(module, :editable_fields, 0) do
      true -> module.editable_fields()
      false -> []
    end
  end

  @spec import_json(String.t(), mode()) :: {:ok, report()} | {:error, [Transfer.problem()]}
  def import_json(json, mode) when mode in [:replace_all, :merge] do
    with {:ok, envelope} <- Transfer.decode(json),
         {:ok, rows} <- Transfer.validate(envelope, known_modules()) do
      import_rows(rows, mode)
    end
  end

  @spec import_rows([Transfer.row()], mode()) :: {:ok, report()} | {:error, [Transfer.problem()]}
  def import_rows(rows, mode) when mode in [:replace_all, :merge] do
    Repo.transaction(fn -> write(rows, mode) end)
  end

  defp write(rows, :replace_all) do
    previous = export()
    Repo.delete_all(ComponentInstance)
    Enum.each(rows, &insert!/1)
    report(previous, rows, :replace_all)
  end

  defp write(rows, :merge) do
    previous = export()
    existing = Repo.all(ComponentInstance) |> Map.new(&{&1.component_id, &1})

    Enum.each(rows, fn row ->
      case Map.get(existing, row.component_id) do
        nil -> insert!(row)
        instance -> update!(instance, row)
      end
    end)

    report(previous, rows, :merge)
  end

  defp insert!(row) do
    %ComponentInstance{}
    |> ComponentInstance.changeset(row)
    |> Repo.insert()
    |> or_rollback(row)
  end

  defp update!(instance, row) do
    instance
    |> ComponentInstance.changeset(row)
    |> Repo.update()
    |> or_rollback(row)
  end

  defp or_rollback({:ok, instance}, _row), do: instance

  defp or_rollback({:error, changeset}, row) do
    Repo.rollback([
      %{
        index: nil,
        component_id: row.component_id,
        field: :row,
        error: :write_failed,
        value: inspect(changeset.errors)
      }
    ])
  end

  defp report(previous, rows, mode) do
    before = encoded_by_id(previous)
    incoming = encoded_by_id(rows)

    inserted = Map.keys(incoming) -- Map.keys(before)
    common = Map.keys(incoming) -- inserted

    {updated, unchanged} =
      Enum.split_with(common, &(Map.get(before, &1) != Map.get(incoming, &1)))

    deleted = deleted_ids(mode, Map.keys(before) -- Map.keys(incoming))

    %{
      inserted: Enum.sort(inserted),
      updated: Enum.sort(updated),
      unchanged: Enum.sort(unchanged),
      deleted: Enum.sort(deleted),
      changed: Enum.sort(inserted ++ updated ++ deleted)
    }
  end

  defp deleted_ids(:replace_all, missing), do: missing
  defp deleted_ids(:merge, _missing), do: []

  defp encoded_by_id(rows) do
    Transfer.encode(rows)
    |> Map.fetch!("components")
    |> Map.new(&{&1["component_id"], &1})
  end

  @spec restart_components([String.t() | atom()]) :: :ok
  def restart_components(ids) do
    Enum.each(ids, fn id ->
      PhysicalComponent.stop(id)

      case fetch_instance(id) do
        nil -> :ok
        instance -> PhysicalComponent.start(instance.component_id, instance)
      end
    end)
  end

  defp fetch_instance(id) do
    from(c in ComponentInstance, where: c.component_id == ^to_string(id))
    |> Repo.one()
    |> hydrate()
  end

  defp hydrate(nil), do: nil
  defp hydrate(instance), do: ComponentInstance.hydrate(instance)
end
