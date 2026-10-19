defmodule Bbparty.Bus.Module2Test do
  use ExUnit.Case, async: true

  alias Bbparty.Bus.Module2

  describe "command encoders" do
    test "ping" do
      assert Module2.ping() == <<0x11>>
    end

    test "set_leds" do
      assert Module2.set_leds(0) == <<0x12, 0x00>>
      assert Module2.set_leds(0xA5) == <<0x12, 0xA5>>
      assert Module2.set_leds(255) == <<0x12, 0xFF>>
    end

    test "set_gauge addresses one channel" do
      assert Module2.set_gauge(0, 128) == <<0x13, 0, 128>>
      assert Module2.set_gauge(2, 255) == <<0x13, 2, 255>>
    end

    test "write_tag encodes length prefix and text" do
      assert Module2.write_tag("ABC") == <<0x14, 3, "ABC">>
      assert Module2.write_tag("") == <<0x14, 0>>
    end

    test "write_tag accepts exactly 46 bytes" do
      text = String.duplicate("x", 46)
      assert Module2.write_tag(text) == <<0x14, 46>> <> text
    end

    test "write_tag rejects a 47-byte string" do
      text = String.duplicate("x", 47)
      assert_raise ArgumentError, fn -> Module2.write_tag(text) end
    end
  end

  describe "report decoding" do
    test "pong" do
      assert Module2.decode(<<0x81>>) == {:ok, {:pong}}
    end

    test "a key event carries its index and edge" do
      assert Module2.decode(<<0x82, 5, 1>>) == {:ok, {:key_event, 5, true}}
      assert Module2.decode(<<0x82, 5, 0>>) == {:ok, {:key_event, 5, false}}
    end

    test "a snapshot carries committed state" do
      assert Module2.decode(<<0x88, 0xC3>>) == {:ok, {:snapshot, 0xC3}}
    end

    test "a fault names the subsystem that failed to start" do
      assert Module2.decode(<<0x8F, 0x01, 2>>) == {:ok, {:fault, :gauge, 2}}
      assert Module2.decode(<<0x8F, 0x02, 0>>) == {:ok, {:fault, :led_brightness, 0}}
    end

    test "the nfc reader's faults name what to check" do
      assert Module2.decode(<<0x8F, 0x03, 0x00>>) == {:ok, {:fault, :nfc, 0x00}}
      assert Module2.fault_description(:nfc, 0x00) =~ "swapped"
      assert Module2.fault_description(:nfc, 0xFF) =~ "would not initialise"
      assert Module2.fault_description(:nfc, 0x2A) =~ "0x2A answered"
    end

    test "a failed NFC task decodes and says the reader is idle" do
      assert Module2.decode(<<0x8F, 0x04, 0>>) == {:ok, {:fault, :nfc_task, 0}}
      assert Module2.fault_description(:nfc_task, 0) =~ "never polled"
    end

    test "a gauge fault names its channel" do
      assert Module2.fault_description(:gauge, 2) =~ "gauge 2"
    end

    test "an unknown fault still says something" do
      assert Module2.fault_description(0x7B, 4) =~ "123"
    end

    test "an unknown subsystem is passed through rather than dropped" do
      assert Module2.decode(<<0x8F, 0x7B, 0>>) == {:ok, {:fault, 0x7B, 0}}
    end

    test "the old button bitmap is no longer a message" do
      assert Module2.decode(<<0x82, 0xC3>>) == :error
    end

    test "axes as raw 12-bit ADC (big-endian uint16 per axis)" do
      assert Module2.decode(<<0x83, 0x00, 0x00, 0x08, 0x00, 0x0F, 0xFF>>) ==
               {:ok, {:axes, {0, 2048, 4095}}}
    end

    test "encoder with signed int8 value" do
      assert Module2.decode(<<0x84, 0xFF>>) == {:ok, {:encoder, -1}}
      assert Module2.decode(<<0x84, 0x0A>>) == {:ok, {:encoder, 10}}
      assert Module2.decode(<<0x84, 0x80>>) == {:ok, {:encoder, -128}}
    end

    test "tag_read with a 7-byte UID and text" do
      uid = <<0x04, 0xA2, 0x3B, 0x91, 0x0C, 0x55, 0xEE>>
      text = "HELLO-42"

      assert Module2.decode(
               <<0x85, byte_size(uid)>> <>
                 uid <> <<0x08, byte_size(text)>> <> text
             ) ==
               {:ok, {:tag_read, %{uid: uid, sak: 0x08, text: text}}}
    end

    test "tag_gone" do
      assert Module2.decode(<<0x86>>) == {:ok, {:tag_gone}}
    end

    test "write_result ok and failure" do
      uid = <<0x11, 0x22, 0x33, 0x44>>

      assert Module2.decode(<<0x87, 0x00, byte_size(uid)>> <> uid) ==
               {:ok, {:write_result, %{ok: true, uid: uid}}}

      assert Module2.decode(<<0x87, 0x01, byte_size(uid)>> <> uid) ==
               {:ok, {:write_result, %{ok: false, uid: uid}}}
    end

    test "unknown opcode is an error" do
      assert Module2.decode(<<0x99>>) == :error
    end

    test "short report is an error" do
      assert Module2.decode(<<0x83, 0x00>>) == :error
      assert Module2.decode(<<>>) == :error
    end
  end

  describe "key_event/2" do
    test "encodes the board's KeyEvent report" do
      assert Module2.key_event(6, true) == <<0x82, 6, 1>>
      assert Module2.key_event(5, false) == <<0x82, 5, 0>>
    end

    test "round-trips through decode/1" do
      assert Module2.decode(Module2.key_event(6, true)) == {:ok, {:key_event, 6, true}}
      assert Module2.decode(Module2.key_event(0, false)) == {:ok, {:key_event, 0, false}}
    end
  end
end
