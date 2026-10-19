defmodule Bbparty.Print.TestPatternTest do
  use ExUnit.Case, async: true

  alias Bbparty.Print.{Raster, TestPattern}

  @width 200
  @height 100

  defp set?(x, y), do: TestPattern.bit(x, y, @width, @height) == 1

  describe "the border" do
    test "runs along all four edges" do
      assert set?(0, div(@height, 2))
      assert set?(@width - 1, div(@height, 2))
      assert set?(div(@width, 2), 0)
      assert set?(div(@width, 2), @height - 1)
    end

    test "is thin, not a filled edge" do
      refute set?(100, 80)
    end
  end

  describe "the corner blocks" do
    test "sit in all four corners" do
      assert set?(10, 10)
      assert set?(@width - 10, 10)
      assert set?(10, @height - 10)
      assert set?(@width - 10, @height - 10)
    end
  end

  describe "the diagonal" do
    test "runs corner to corner" do
      assert set?(0, 0)
      assert set?(@width - 1, @height - 1)
    end

    test "passes through the centre" do
      assert set?(div(@width, 2), div(@height, 2))
    end

    test "is absent where the line is not" do
      refute set?(div(@width, 2), div(@height, 4))
    end
  end

  describe "the ruler" do
    test "marks every 100 dots along the top" do
      assert set?(100, 10)
      refute set?(150, 10)
    end

    test "does not run the full height" do
      refute set?(100, 60)
    end
  end

  describe "packed/2" do
    test "produces one padded row per line" do
      {rows, bytes_per_row} = TestPattern.packed(@width, @height)

      assert bytes_per_row == Raster.bytes_per_row(@width)
      assert byte_size(rows) == bytes_per_row * @height
    end

    test "the first row is the border, so every bit of it is set" do
      {rows, bytes_per_row} = TestPattern.packed(@width, @height)
      <<first::binary-size(^bytes_per_row), _rest::binary>> = rows

      assert first == :binary.copy(<<0xFF>>, bytes_per_row)
    end
  end

  describe "label/2" do
    test "wraps the pattern at the dimensions asked for" do
      zpl = IO.iodata_to_binary(TestPattern.label(64, 8))

      assert zpl =~ "^PW64"
      assert zpl =~ "^LL8"
      assert zpl =~ "^GFA,64,64,8,"
    end

    test "defaults to the configured stock" do
      {width, height} = Bbparty.Print.Label.dots()
      zpl = IO.iodata_to_binary(TestPattern.label())

      assert zpl =~ "^PW#{width}"
      assert zpl =~ "^LL#{height}"
    end
  end
end
