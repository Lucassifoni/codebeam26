defmodule Bbparty.Bus.Module7Test do
  use ExUnit.Case, async: true

  alias Bbparty.Bus.Module7
  alias Bbparty.SwitchPanel

  describe "command encoders" do
    test "ping" do
      assert Module7.ping() == <<0x11>>
    end

    test "request_sync" do
      assert Module7.request_sync() == <<0x16>>
    end

    test "set_leds carries the whole eight-byte chain" do
      frame = <<0x01, 0, 0, 0, 0, 0, 0, 0x80>>
      assert Module7.set_leds(frame) == <<0x12, frame::binary>>
    end

    test "set_leds refuses a frame that is not the chain's width" do
      assert_raise FunctionClauseError, fn -> Module7.set_leds(<<0x01>>) end
      assert_raise FunctionClauseError, fn -> Module7.set_leds(<<0::size(72)>>) end
    end
  end

  describe "report decoding" do
    test "pong" do
      assert Module7.decode(<<0x81>>) == {:ok, {:pong}}
    end

    test "key event carries the raw crosspoint" do
      assert Module7.decode(<<0x82, 4, 5, 1>>) == {:ok, {:key_event, 4, 5, true}}
      assert Module7.decode(<<0x82, 4, 5, 0>>) == {:ok, {:key_event, 4, 5, false}}
    end

    test "a crosspoint on a spare line decodes — the bus is eight by eight" do
      assert Module7.decode(<<0x82, 7, 7, 1>>) == {:ok, {:key_event, 7, 7, true}}
    end

    test "a pressed flag other than 0 or 1 is a corrupt frame" do
      assert Module7.decode(<<0x82, 1, 1, 2>>) == :error
      assert Module7.decode(<<0x82, 1, 1, 255>>) == :error
    end

    test "truncated key events" do
      assert Module7.decode(<<0x82>>) == :error
      assert Module7.decode(<<0x82, 3>>) == :error
      assert Module7.decode(<<0x82, 3, 4>>) == :error
    end

    test "snapshot bit is drive * 8 + sense" do
      body = <<0x88, 0x01, 0x01, 0x00, 0x00, 0x20, 0x00, 0x00, 0x80>>
      assert {:ok, {:snapshot, bits}} = Module7.decode(body)

      assert SwitchPanel.pressed(bits) == [{0, 0}, {1, 0}, {4, 5}, {7, 7}]
    end

    test "an all-open snapshot is still a snapshot" do
      assert Module7.decode(<<0x88, 0, 0, 0, 0, 0, 0, 0, 0>>) == {:ok, {:snapshot, 0}}
    end

    test "a snapshot of the wrong width is a corrupt frame" do
      assert Module7.decode(<<0x88, 0xFF>>) == :error
      assert Module7.decode(<<0x88, 0::size(56)>>) == :error
      assert Module7.decode(<<0x88, 0::size(72)>>) == :error
    end

    test "trailing bytes are not silently accepted" do
      assert Module7.decode(<<0x81, 0>>) == :error
      assert Module7.decode(<<0x82, 3, 4, 1, 0>>) == :error
    end

    test "unknown opcodes" do
      assert Module7.decode(<<0x99>>) == :error
      assert Module7.decode(<<>>) == :error
    end
  end
end
