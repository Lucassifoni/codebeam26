defmodule Bbparty.Layout do
  alias Bbparty.Layout.ComponentInstance
  alias Bbparty.Repo

  @spec autoregister?() :: boolean()
  def autoregister?, do: Application.get_env(:bbparty, :key_autoregister, false)

  def list_components() do
    Repo.all(ComponentInstance) |> Enum.map(&ComponentInstance.hydrate/1)
  end

  def create_component(id, module, attrs \\ %{}, position \\ nil) do
    %ComponentInstance{}
    |> ComponentInstance.changeset(%{
      component_id: to_string(id),
      module: to_string(module),
      attrs: attrs,
      position: position
    })
    |> Repo.insert()
  end

  defp select_component(id) do
    import Ecto.Query
    from(c in ComponentInstance, where: c.component_id == ^to_string(id))
  end

  def get_component(id) do
    select_component(id)
    |> Repo.one!()
    |> ComponentInstance.hydrate()
  end

  def delete_component(id) do
    Repo.transaction(fn ->
      get_component(id)
      |> Repo.delete()
    end)
  end

  def move_component(id, new_pos) do
    Repo.transaction(fn ->
      {:ok, c} =
        get_component(id) |> ComponentInstance.changeset(%{position: new_pos}) |> Repo.update()

      c
    end)
  end

  def move_components(plan) do
    Repo.transaction(fn ->
      Enum.map(plan, fn {id, position} ->
        {:ok, moved} =
          get_component(id)
          |> ComponentInstance.changeset(%{position: position})
          |> Repo.update()

        moved
      end)
    end)
  end

  def set_component_attr(id, key, value) do
    Repo.transaction(fn ->
      component = get_component(id)

      editable =
        if Code.ensure_loaded?(component.module) and
             function_exported?(component.module, :editable_fields, 0),
           do: Keyword.keys(component.module.editable_fields()),
           else: []

      if key in editable do
        {:ok, c} =
          ComponentInstance.changeset(component, %{attrs: %{component.attrs | key => value}})
          |> Repo.update()

        c
      else
        :error
      end
    end)
  end

  def rename_component(old_id, new_id) do
    with :ok <- ensure_not_referenced(old_id),
         :ok <- ensure_not_referenced(new_id),
         {:ok, instance} <- fetch_component(old_id) do
      instance
      |> ComponentInstance.changeset(%{component_id: to_string(new_id)})
      |> Repo.update()
    end
  end

  defp ensure_not_referenced(id) do
    case MapSet.member?(Bbparty.RenderState.referenced_ids(), to_string(id)) do
      true -> {:error, :referenced_by_graph}
      false -> :ok
    end
  end

  defp fetch_component(id) do
    case Repo.one(select_component(id)) do
      nil -> {:error, :not_found}
      instance -> {:ok, ComponentInstance.hydrate(instance)}
    end
  end

  def set_group(ids, group_id) do
    import Ecto.Query
    ids = Enum.map(ids, &to_string/1)

    from(c in ComponentInstance, where: c.component_id in ^ids)
    |> Repo.update_all(set: [group_id: group_id])
  end
end
