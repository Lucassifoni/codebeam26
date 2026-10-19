defmodule Bbparty.Bus.LedShadow.FrameTest do
  use ExUnit.Case, async: true

  alias Bbparty.Bus.LedShadow.Frame

  describe "a board's picture" do
    test "starts dark" do
      frame = Frame.new(8)

      assert Frame.to_binary(frame) == <<0>>
      refute Frame.lit?(frame, 0)
    end

    test "channel 0 is the low bit of the first byte, as the shift register sees it" do
      assert Frame.new(8) |> Frame.put(0, true) |> Frame.to_binary() == <<0b0000_0001>>
      assert Frame.new(8) |> Frame.put(7, true) |> Frame.to_binary() == <<0b1000_0000>>
    end

    test "channels accumulate into one picture" do
      frame = Frame.new(8) |> Frame.put(1, true) |> Frame.put(4, true)

      assert Frame.to_binary(frame) == <<0b0001_0010>>
      assert Frame.lit?(frame, 1)
      assert Frame.lit?(frame, 4)
      refute Frame.lit?(frame, 2)
    end

    test "putting is idempotent" do
      once = Frame.new(8) |> Frame.put(3, true)
      twice = Frame.put(once, 3, true)

      assert once == twice
    end

    test "darkening leaves its neighbours alone" do
      frame =
        Frame.new(8) |> Frame.put(2, true) |> Frame.put(3, true) |> Frame.put(2, false)

      assert Frame.to_binary(frame) == <<0b0000_1000>>
    end

    test "a wide board spans as many bytes as it needs" do
      frame = Frame.new(64) |> Frame.put(0, true) |> Frame.put(63, true)

      assert byte_size(Frame.to_binary(frame)) == 8
      assert Frame.to_binary(frame) == <<1, 0, 0, 0, 0, 0, 0, 0b1000_0000>>
    end

    test "bytes/1 rounds up" do
      assert Frame.bytes(8) == 1
      assert Frame.bytes(9) == 2
      assert Frame.bytes(60) == 8
    end
  end

  describe "a channel the board does not have" do
    test "is ignored rather than raised" do
      frame = Frame.new(8)

      assert Frame.put(frame, 8, true) == frame
      assert Frame.put(frame, -1, true) == frame
      assert Frame.put(frame, nil, true) == frame
    end

    test "reads as dark" do
      refute Frame.lit?(Frame.new(8), 12)
      refute Frame.lit?(Frame.new(8), -3)
    end
  end

  test "a rebuilt picture is byte-identical to the incremental one" do
    channels = [0, 3, 5, 7]

    incremental = Enum.reduce(channels, Frame.new(8), &Frame.put(&2, &1, true))
    rebuilt = Enum.reduce(Enum.reverse(channels), Frame.new(8), &Frame.put(&2, &1, true))

    assert Frame.to_binary(incremental) == Frame.to_binary(rebuilt)
  end
end
