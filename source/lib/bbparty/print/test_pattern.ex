defmodule Bbparty.Print.TestPattern do
  alias Bbparty.Print.{Label, Raster, Zpl}

  @border 4
  @corner 40
  @tick_spacing 100
  @tick_width 3
  @tick_length 24
  @diagonal_width 1.5

  @spec packed(pos_integer(), pos_integer()) :: {binary(), pos_integer()}
  def packed(width, height) do
    rows =
      for y <- 0..(height - 1), into: <<>> do
        bits = for x <- 0..(width - 1), into: <<>>, do: <<bit(x, y, width, height)::1>>
        pad = rem(8 - rem(bit_size(bits), 8), 8)
        <<bits::bitstring, 0::size(pad)>>
      end

    {rows, Raster.bytes_per_row(width)}
  end

  @spec label(pos_integer() | nil, pos_integer() | nil) :: iodata()
  def label(width \\ nil, height \\ nil) do
    {default_width, default_height} = Label.dots()
    width = width || default_width
    height = height || default_height

    {rows, bytes_per_row} = packed(width, height)
    Zpl.label(rows, width, height, bytes_per_row)
  end

  @spec bit(non_neg_integer(), non_neg_integer(), pos_integer(), pos_integer()) :: 0 | 1
  def bit(x, y, width, height) do
    cases = [
      border?(x, y, width, height),
      corner?(x, y, width, height),
      diagonal?(x, y, width, height),
      tick?(x, y)
    ]

    if Enum.any?(cases), do: 1, else: 0
  end

  defp border?(x, y, width, height) do
    x < @border or x >= width - @border or y < @border or y >= height - @border
  end

  defp corner?(x, y, width, height) do
    (x < @corner or x >= width - @corner) and (y < @corner or y >= height - @corner)
  end

  defp diagonal?(_x, _y, width, height) when width < 2 or height < 2, do: false

  defp diagonal?(x, y, width, height) do
    abs(y - x * (height - 1) / (width - 1)) <= @diagonal_width
  end

  defp tick?(x, y) do
    y < @tick_length and rem(x, @tick_spacing) < @tick_width
  end
end
