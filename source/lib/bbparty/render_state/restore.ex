defmodule Bbparty.RenderState.Restore do
  alias Bbparty.RenderState
  alias Bbparty.RenderState.TextSource

  @alignments [:left, :center]

  @spec from_stored(map()) :: RenderState.t()
  def from_stored(stored) when is_map(stored) do
    fields =
      RenderState.new()
      |> Map.from_struct()
      |> Map.new(fn {field, default} ->
        {field, restore_field(field, stored_value(stored, field), default)}
      end)

    struct(RenderState, fields)
  end

  defp stored_value(stored, field) do
    case Map.fetch(stored, Atom.to_string(field)) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(stored, field)
    end
  end

  defp restore_field(:text_source, {:ok, value}, default),
    do: known_atom(value, Map.values(TextSource.sources()), default)

  defp restore_field(:alignment, {:ok, value}, default),
    do: known_atom(value, @alignments, default)

  defp restore_field(_field, {:ok, value}, _default), do: value
  defp restore_field(_field, :error, default), do: default

  defp known_atom(value, allowed, default),
    do: Enum.find(allowed, default, &(Atom.to_string(&1) == to_string(value)))
end
