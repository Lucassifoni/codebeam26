defmodule Bbparty.Repo.Migrations.CreatePrintouts do
  use Ecto.Migration

  def change do
    create table(:printouts) do
      add :state, :map, null: false
      add :printed_at, :utc_datetime_usec, null: false
    end

    create index(:printouts, [:printed_at])
  end
end
