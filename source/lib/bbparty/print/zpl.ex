defmodule Bbparty.Print.Zpl do
  alias Bbparty.Print.Raster

  @spec label(binary(), pos_integer(), pos_integer(), pos_integer(), keyword()) :: iodata()
  def label(packed, width, height, bytes_per_row, opts \\ []) do
    [
      "^XA",
      "^LH0,0",
      "^PW#{width}",
      "^LL#{height}",
      darkness(Keyword.get(opts, :darkness)),
      speed(Keyword.get(opts, :speed)),
      cut(Keyword.get(opts, :cut)),
      "^FO0,0",
      graphic_field(packed, bytes_per_row),
      "^FS",
      "^XZ"
    ]
  end

  @spec graphic_field(binary(), pos_integer()) :: iodata()
  def graphic_field(packed, bytes_per_row) do
    total = byte_size(packed)
    ["^GFA,#{total},#{total},#{bytes_per_row},", Base.encode16(packed)]
  end

  @spec from_pixels(binary(), pos_integer(), pos_integer(), keyword()) :: iodata()
  def from_pixels(pixels, width, height, opts \\ []) do
    {packed, bytes_per_row} =
      Raster.pack(pixels, width, Keyword.take(opts, [:channels, :cutoff]))

    label(packed, width, height, bytes_per_row, Keyword.take(opts, [:darkness, :speed, :cut]))
  end

  defp darkness(nil), do: []
  defp darkness(level) when level in 0..30, do: "~SD#{String.pad_leading("#{level}", 2, "0")}"

  defp speed(nil), do: []
  defp speed(ips) when is_integer(ips), do: "^PR#{ips}"

  defp cut(true), do: "^MMC"
  defp cut(_other), do: []
end
