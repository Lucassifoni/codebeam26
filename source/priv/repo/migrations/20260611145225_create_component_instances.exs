defmodule Bbparty.Repo.Migrations.CreateComponentInstances do
  use Ecto.Migration

  def change do
    create table(:component_instances) do
      add :component_id, :binary
      add :module, :binary
      add :attrs, :map
      add :position, :map
      add :group_id, :binary
      timestamps(type: :utc_datetime)
    end

    create unique_index(:component_instances, [:component_id], name: :unique_component_ids_index)
  end
end
