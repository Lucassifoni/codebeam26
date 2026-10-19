defmodule Bbparty.Printouts do
  import Ecto.Query

  alias Bbparty.Printouts.Printout
  alias Bbparty.Repo
  alias Bbparty.RenderState

  @spec record(RenderState.t(), DateTime.t()) :: {:ok, Printout.t()} | {:error, term()}
  def record(%RenderState{} = render, printed_at \\ DateTime.utc_now()) do
    render
    |> Printout.changeset(printed_at)
    |> Repo.insert()
  end

  @spec get!(integer() | String.t()) :: Printout.t()
  def get!(id), do: Repo.get!(Printout, id)

  @spec list() :: [Printout.t()]
  def list do
    Printout
    |> order_by([p], asc: p.printed_at, asc: p.id)
    |> Repo.all()
  end

  @doc """
  Printouts newest first, `:limit` at a time (24 by default). Pass the last
  printout of a page as `:after` to get the one following it.
  """
  @spec page(keyword()) :: [Printout.t()]
  def page(opts \\ []) do
    Printout
    |> older_than(Keyword.get(opts, :after))
    |> order_by([p], desc: p.printed_at, desc: p.id)
    |> limit(^Keyword.get(opts, :limit, 24))
    |> Repo.all()
  end

  defp older_than(query, nil), do: query

  defp older_than(query, %Printout{printed_at: at, id: id}),
    do: where(query, [p], p.printed_at < ^at or (p.printed_at == ^at and p.id < ^id))

  @spec count() :: non_neg_integer()
  def count, do: Repo.aggregate(Printout, :count)
end
