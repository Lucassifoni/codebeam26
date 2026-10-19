defmodule Bbparty.Print.Raster do
  @default_cutoff 128

  @red 299
  @green 587
  @blue 114

  @spec pack(binary(), pos_integer(), keyword()) :: {binary(), pos_integer()}
  def pack(pixels, width, opts \\ []) when is_binary(pixels) and width > 0 do
    channels = Keyword.get(opts, :channels, 4)
    cutoff = Keyword.get(opts, :cutoff, @default_cutoff)
    row_bytes = width * channels

    packed =
      for <<row::binary-size(^row_bytes) <- pixels>>, into: <<>> do
        pack_row(row, channels, cutoff)
      end

    {packed, bytes_per_row(width)}
  end

  @spec bytes_per_row(pos_integer()) :: pos_integer()
  def bytes_per_row(width), do: div(width + 7, 8)

  @spec luma(binary()) :: 0..255
  def luma(<<gray>>), do: gray
  def luma(<<r, g, b, _rest::binary>>), do: div(r * @red + g * @green + b * @blue, 1000)
  def luma(<<r, g, b>>), do: div(r * @red + g * @green + b * @blue, 1000)

  defp pack_row(row, channels, cutoff) do
    bits =
      for <<pixel::binary-size(^channels) <- row>>, into: <<>> do
        <<burn(pixel, cutoff)::1>>
      end

    <<bits::bitstring, 0::size(padding(bit_size(bits)))>>
  end

  defp burn(pixel, cutoff) do
    case luma(pixel) < cutoff do
      true -> 1
      false -> 0
    end
  end

  defp padding(bits), do: rem(8 - rem(bits, 8), 8)
end
