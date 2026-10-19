defmodule Bbparty.Print.PipelineTest do
  use ExUnit.Case, async: true

  alias Bbparty.Print.{Raster, Zpl}

  defp png(pixels, width, height, bands) do
    {:ok, image} =
      Vix.Vips.Image.new_from_binary(pixels, width, height, bands, :VIPS_FORMAT_UCHAR)

    {:ok, buffer} = Vix.Vips.Image.write_to_buffer(image, ".png")
    buffer
  end

  defp decode(buffer) do
    {:ok, image} = Vix.Vips.Image.new_from_buffer(buffer)
    {:ok, pixels} = Vix.Vips.Image.write_to_binary(image)

    {pixels, Vix.Vips.Image.width(image), Vix.Vips.Image.height(image),
     Vix.Vips.Image.bands(image)}
  end

  defp black, do: <<0, 0, 0>>
  defp white, do: <<255, 255, 255>>

  describe "a PNG through libvips and into packed rows" do
    test "pixels survive the round trip byte for byte" do
      raw = :binary.copy(black(), 4) <> :binary.copy(white(), 4)

      {pixels, width, height, bands} = decode(png(raw, 8, 1, 3))

      assert {width, height, bands} == {8, 1, 3}
      assert pixels == raw
    end

    test "a half-black row packs to the bits you would write by hand" do
      raw = :binary.copy(black(), 4) <> :binary.copy(white(), 4)

      {pixels, width, _height, bands} = decode(png(raw, 8, 1, 3))

      assert {<<0b11110000>>, 1} = Raster.pack(pixels, width, channels: bands)
    end

    test "rows stay in order" do
      row_a = :binary.copy(black(), 8)
      row_b = :binary.copy(white(), 8)

      {pixels, width, _height, bands} = decode(png(row_a <> row_b, 8, 2, 3))

      assert {<<0xFF, 0x00>>, 1} = Raster.pack(pixels, width, channels: bands)
    end

    test "an alpha channel is carried through and ignored by the luma" do
      raw = :binary.copy(<<0, 0, 0, 255>>, 4) <> :binary.copy(<<255, 255, 255, 255>>, 4)

      {pixels, width, _height, bands} = decode(png(raw, 8, 1, 4))

      assert bands == 4
      assert {<<0b11110000>>, 1} = Raster.pack(pixels, width, channels: bands)
    end

    test "reaches ZPL with the geometry it started with" do
      raw = :binary.copy(black(), 8 * 3)

      {pixels, width, height, bands} = decode(png(raw, 8, 3, 3))
      zpl = IO.iodata_to_binary(Zpl.from_pixels(pixels, width, height, channels: bands))

      assert zpl =~ "^PW8"
      assert zpl =~ "^LL3"
      assert zpl =~ "^GFA,3,3,1,FFFFFF"
    end
  end

  describe "the antialiasing a real capture carries" do
    test "a soft stem edge becomes a hard one" do
      stem =
        <<255, 255, 255>> <>
          <<200, 200, 200>> <> <<90, 90, 90>> <> <<0, 0, 0>> <> <<0, 0, 0>> <> <<120, 120, 120>>

      {pixels, width, _height, bands} = decode(png(stem, 6, 1, 3))

      assert {<<0b00111100>>, 1} = Raster.pack(pixels, width, channels: bands)
    end
  end
end
