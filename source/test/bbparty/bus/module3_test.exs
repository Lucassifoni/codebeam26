defmodule Bbparty.Bus.Module3Test do
  use ExUnit.Case, async: true

  alias Bbparty.Bus.Module3

  describe "command encoders" do
    test "ping" do
      assert Module3.ping() == <<0x11>>
    end
  end

  describe "report decoding" do
    test "pong" do
      assert Module3.decode(<<0x81>>) == {:ok, {:pong}}
    end

    test "key event carries the raw crosspoint" do
      assert Module3.decode(<<0x82, 10, 25, 1>>) == {:ok, {:key_event, 10, 25, true}}
      assert Module3.decode(<<0x82, 10, 25, 0>>) == {:ok, {:key_event, 10, 25, false}}
      assert Module3.decode(<<0x82, 0, 0, 1>>) == {:ok, {:key_event, 0, 0, true}}
    end

    test "an address outside the matrix still decodes — range is the host's business" do
      assert Module3.decode(<<0x82, 200, 200, 1>>) == {:ok, {:key_event, 200, 200, true}}
    end

    test "a pressed flag other than 0 or 1 is a corrupt frame" do
      assert Module3.decode(<<0x82, 1, 1, 2>>) == :error
      assert Module3.decode(<<0x82, 1, 1, 255>>) == :error
    end

    test "truncated key events" do
      assert Module3.decode(<<0x82>>) == :error
      assert Module3.decode(<<0x82, 3>>) == :error
      assert Module3.decode(<<0x82, 3, 4>>) == :error
    end

    test "trailing bytes are not silently accepted" do
      assert Module3.decode(<<0x82, 3, 4, 1, 0>>) == :error
      assert Module3.decode(<<0x81, 0>>) == :error
    end

    test "unknown opcodes and an empty body" do
      assert Module3.decode(<<0x83, 1, 2, 3>>) == :error
      assert Module3.decode(<<0x11>>) == :error
      assert Module3.decode(<<>>) == :error
    end
  end
end
