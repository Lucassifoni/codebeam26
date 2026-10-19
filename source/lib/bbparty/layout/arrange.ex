defmodule Bbparty.Layout.Arrange do
  @type box :: %{x: number(), y: number(), w: number(), h: number()}
  @type boxes :: %{optional(any()) => box()}

  @spec translate(boxes(), number(), number()) :: boxes()
  def translate(boxes, dx, dy) do
    Map.new(boxes, fn {id, b} -> {id, %{b | x: b.x + dx, y: b.y + dy}} end)
  end

  @spec align(boxes(), :left | :hcenter | :right | :top | :vcenter | :bottom) :: boxes()
  def align(boxes, edge) when edge in [:left, :hcenter, :right] do
    {lo, hi} = span(boxes, :x, :w)
    Map.new(boxes, fn {id, b} -> {id, %{b | x: edge_coord(edge, b.w, lo, hi)}} end)
  end

  def align(boxes, edge) when edge in [:top, :vcenter, :bottom] do
    {lo, hi} = span(boxes, :y, :h)
    Map.new(boxes, fn {id, b} -> {id, %{b | y: edge_coord(edge, b.h, lo, hi)}} end)
  end

  @spec distribute(boxes(), :horizontal | :vertical) :: boxes()
  def distribute(boxes, _axis) when map_size(boxes) < 3, do: boxes
  def distribute(boxes, :horizontal), do: spread(boxes, :x, :w)
  def distribute(boxes, :vertical), do: spread(boxes, :y, :h)

  defp edge_coord(edge, _size, lo, _hi) when edge in [:left, :top], do: lo
  defp edge_coord(edge, size, _lo, hi) when edge in [:right, :bottom], do: hi - size
  defp edge_coord(_center, size, lo, hi), do: (lo + hi) / 2 - size / 2

  defp span(boxes, pos, size) do
    coords = Enum.map(boxes, fn {_id, b} -> Map.get(b, pos) end)
    extents = Enum.map(boxes, fn {_id, b} -> Map.get(b, pos) + Map.get(b, size) end)
    {Enum.min(coords), Enum.max(extents)}
  end

  defp spread(boxes, pos, size) do
    sorted = Enum.sort_by(boxes, fn {_id, b} -> Map.get(b, pos) end)
    {lo, hi} = span(boxes, pos, size)
    total = Enum.reduce(sorted, 0, fn {_id, b}, acc -> acc + Map.get(b, size) end)
    gap = (hi - lo - total) / (length(sorted) - 1)

    {placed, _cursor} =
      Enum.map_reduce(sorted, lo, fn {id, b}, cursor ->
        {{id, Map.put(b, pos, cursor)}, cursor + Map.get(b, size) + gap}
      end)

    Map.new(placed)
  end
end
