defmodule Bbparty.Print.ZplTest do
  use ExUnit.Case, async: true

  alias Bbparty.Print.Zpl

  defp render(iodata), do: IO.iodata_to_binary(iodata)

  describe "label/5" do
    setup do
      %{zpl: render(Zpl.label(<<0xFF, 0x00>>, 9, 2, 2))}
    end

    test "opens and closes a label", %{zpl: zpl} do
      assert String.starts_with?(zpl, "^XA")
      assert String.ends_with?(zpl, "^XZ")
    end

    test "declares the label's dot dimensions", %{zpl: zpl} do
      assert zpl =~ "^PW9"
      assert zpl =~ "^LL2"
    end

    test "homes at the origin", %{zpl: zpl} do
      assert zpl =~ "^LH0,0"
      assert zpl =~ "^FO0,0"
    end

    test "carries no text or fonts — the typography is the browser's", %{zpl: zpl} do
      refute zpl =~ "^A"
      refute zpl =~ "^FD"
    end

    test "leaves darkness, speed and cutter mode to the printer's own settings", %{zpl: zpl} do
      refute zpl =~ "~SD"
      refute zpl =~ "^PR"
      refute zpl =~ "^MM"
    end

    test "unless they are given" do
      zpl = render(Zpl.label(<<0>>, 8, 1, 1, darkness: 12, speed: 4, cut: true))

      assert zpl =~ "~SD12"
      assert zpl =~ "^PR4"
      assert zpl =~ "^MMC"
    end

    test "cutter mode is opt-in, so a false does not assert tear-off either" do
      refute render(Zpl.label(<<0>>, 8, 1, 1, cut: false)) =~ "^MM"
    end

    test "a single-digit darkness is padded, as ZPL wants" do
      assert render(Zpl.label(<<0>>, 8, 1, 1, darkness: 5)) =~ "~SD05"
    end
  end

  describe "graphic_field/2" do
    test "both counts are the total byte size, and the third is the row width" do
      packed = :binary.copy(<<0xAB>>, 296)

      assert render(Zpl.graphic_field(packed, 148)) =~ "^GFA,296,296,148,"
    end

    test "the data is uppercase ASCII hex" do
      assert render(Zpl.graphic_field(<<0xDE, 0xAD, 0xBE, 0xEF>>, 4)) =~ "DEADBEEF"
    end

    test "every byte of the raster survives into the field" do
      packed = :binary.copy(<<0x5A>>, 100)
      [_header, hex] = Zpl.graphic_field(packed, 10)

      assert byte_size(hex) == 200
      assert Base.decode16!(hex) == packed
    end
  end

  describe "from_pixels/4" do
    test "packs and wraps in one step" do
      pixels = :binary.copy(<<0, 0, 0, 255>>, 8)

      zpl = render(Zpl.from_pixels(pixels, 8, 1))

      assert zpl =~ "^GFA,1,1,1,FF"
      assert zpl =~ "^PW8"
    end

    test "raster options reach the raster and label options the label" do
      pixels = :binary.copy(<<200, 200, 200, 255>>, 8)

      zpl = render(Zpl.from_pixels(pixels, 8, 1, cutoff: 220, darkness: 8, cut: true))

      assert zpl =~ "FF"
      assert zpl =~ "~SD08"
      assert zpl =~ "^MMC"
    end

    test "the row width it declares is the one the raster actually used" do
      pixels = :binary.copy(<<0, 0, 0, 255>>, 9 * 3)

      zpl = render(Zpl.from_pixels(pixels, 9, 3))

      assert zpl =~ "^GFA,6,6,2,"
    end
  end

  describe "the installed label" do
    test "100x50 mm at 300 dpi is 148 bytes across and 591 rows down" do
      {width, height} = {1181, 591}
      pixels = :binary.copy(<<255, 255, 255, 255>>, width * height)

      zpl = render(Zpl.from_pixels(pixels, width, height))

      assert zpl =~ "^PW1181"
      assert zpl =~ "^LL591"
      assert zpl =~ "^GFA,87468,87468,148,"
    end
  end
end
