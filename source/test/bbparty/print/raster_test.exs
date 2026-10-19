defmodule Bbparty.Print.RasterTest do
  use ExUnit.Case, async: true

  alias Bbparty.Print.Raster

  defp black, do: <<0, 0, 0, 255>>
  defp white, do: <<255, 255, 255, 255>>
  defp gray(v), do: <<v, v, v, 255>>

  defp row(pixels), do: Enum.reduce(pixels, <<>>, &(&2 <> &1))

  describe "bytes_per_row/1" do
    test "pads up to a whole byte" do
      assert Raster.bytes_per_row(8) == 1
      assert Raster.bytes_per_row(9) == 2
      assert Raster.bytes_per_row(1) == 1
    end

    test "the real label is 148 bytes a row" do
      assert Raster.bytes_per_row(1181) == 148
    end
  end

  describe "luma/1" do
    test "greyscale passes through" do
      assert Raster.luma(<<0>>) == 0
      assert Raster.luma(<<200>>) == 200
    end

    test "colour weights by Rec. 601, so green dominates" do
      assert Raster.luma(<<255, 0, 0, 255>>) == 76
      assert Raster.luma(<<0, 255, 0, 255>>) == 149
      assert Raster.luma(<<0, 0, 255, 255>>) == 29
    end

    test "RGB without an alpha channel works too" do
      assert Raster.luma(<<255, 255, 255>>) == 255
    end
  end

  describe "pack/3" do
    test "dark pixels set bits, light ones clear them" do
      pixels = row([black(), white(), black(), white(), white(), white(), white(), white()])

      assert {<<0b10100000>>, 1} = Raster.pack(pixels, 8)
    end

    test "bits are MSB first, so the leftmost dot is the high bit" do
      pixels = row([black(), white(), white(), white(), white(), white(), white(), white()])

      assert {<<0b10000000>>, 1} = Raster.pack(pixels, 8)
    end

    test "a short row is padded with unset bits" do
      pixels = row([black(), black(), black()])

      assert {<<0b11100000>>, 1} = Raster.pack(pixels, 3)
    end

    test "each row is padded independently, not the raster as a whole" do
      pixels = row([black(), black(), black(), black(), black(), black()])

      assert {<<0b11100000, 0b11100000>>, 1} = Raster.pack(pixels, 3)
    end

    test "the reported row width matches the data" do
      pixels = row(List.duplicate(white(), 9))
      {packed, bytes_per_row} = Raster.pack(pixels, 9)

      assert bytes_per_row == 2
      assert byte_size(packed) == 2
    end

    test "many rows produce bytes_per_row * rows" do
      pixels = row(List.duplicate(white(), 9 * 5))
      {packed, bytes_per_row} = Raster.pack(pixels, 9)

      assert byte_size(packed) == bytes_per_row * 5
    end
  end

  describe "the threshold" do
    test "splits at the midpoint by default" do
      assert {<<0b10000000>>, 1} = Raster.pack(row([gray(127)]), 1)
      assert {<<0b00000000>>, 1} = Raster.pack(row([gray(128)]), 1)
    end

    test "the cutoff is adjustable for stock that reads light or dark" do
      pixels = row([gray(200)])

      assert {<<0b00000000>>, 1} = Raster.pack(pixels, 1)
      assert {<<0b10000000>>, 1} = Raster.pack(pixels, 1, cutoff: 220)
    end

    test "an antialiased edge becomes a hard boundary, not a gradient" do
      edge = row([gray(0), gray(40), gray(90), gray(160), gray(210), gray(255)])

      assert {<<0b11100000>>, 1} = Raster.pack(edge, 6)
    end
  end

  describe "channel layouts" do
    test "greyscale input, one byte a pixel" do
      pixels = <<0, 255, 0, 255, 255, 255, 255, 255>>

      assert {<<0b10100000>>, 1} = Raster.pack(pixels, 8, channels: 1)
    end

    test "RGB input, three bytes a pixel" do
      pixels = <<0, 0, 0>> <> <<255, 255, 255>>

      assert {<<0b10000000>>, 1} = Raster.pack(pixels, 2, channels: 3)
    end
  end

  describe "the installed geometry" do
    test "a full white label is 148 * 591 bytes of nothing" do
      {width, height} = {1181, 591}
      pixels = :binary.copy(<<255, 255, 255, 255>>, width * height)

      {packed, bytes_per_row} = Raster.pack(pixels, width)

      assert bytes_per_row == 148
      assert byte_size(packed) == 148 * height
      assert packed == :binary.copy(<<0>>, 148 * height)
    end
  end
end
