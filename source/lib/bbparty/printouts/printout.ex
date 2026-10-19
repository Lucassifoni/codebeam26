defmodule Bbparty.Printouts.Printout do
  use Ecto.Schema
  import Ecto.Changeset

  alias Bbparty.RenderState

  @type t :: %__MODULE__{}

  schema "printouts" do
    field :state, :map
    field :printed_at, :utc_datetime_usec
  end

  @spec changeset(RenderState.t(), DateTime.t()) :: Ecto.Changeset.t()
  def changeset(%RenderState{} = render, %DateTime{} = printed_at) do
    %__MODULE__{}
    |> change(state: Map.from_struct(render), printed_at: printed_at)
    |> validate_required([:state, :printed_at])
  end
end
