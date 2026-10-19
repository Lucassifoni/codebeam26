defmodule Bbparty.Bus.Module4Test do
  use ExUnit.Case, async: true

  alias Bbparty.Bus.Module4

  describe "command encoders" do
    test "ping" do
      assert Module4.ping() == <<0x11>>
    end
  end

  describe "report decoding" do
    test "pong" do
      assert Module4.decode(<<0x81>>) == {:ok, {:pong}}
    end

    test "buttons carry the whole field, not an edge" do
      assert Module4.decode(<<0x82, 0b00>>) == {:ok, {:buttons, 0}}
      assert Module4.decode(<<0x82, 0b01>>) == {:ok, {:buttons, 1}}
      assert Module4.decode(<<0x82, 0b11>>) == {:ok, {:buttons, 3}}
    end

    test "a bit above the wired buttons is a corrupt frame" do
      assert Module4.decode(<<0x82, 0b100>>) == :error
      assert Module4.decode(<<0x82, 255>>) == :error
    end

    test "activity carries a saturated pulse count" do
      assert Module4.decode(<<0x83, 0>>) == {:ok, {:activity, 0}}
      assert Module4.decode(<<0x83, 12>>) == {:ok, {:activity, 12}}
      assert Module4.decode(<<0x83, 255>>) == {:ok, {:activity, 255}}
    end

    test "truncated bodies" do
      assert Module4.decode(<<0x82>>) == :error
      assert Module4.decode(<<0x83>>) == :error
      assert Module4.decode(<<>>) == :error
    end

    test "trailing bytes are not silently accepted" do
      assert Module4.decode(<<0x81, 0>>) == :error
      assert Module4.decode(<<0x82, 1, 0>>) == :error
      assert Module4.decode(<<0x83, 1, 0>>) == :error
    end

    test "an unknown opcode" do
      assert Module4.decode(<<0x84, 1>>) == :error
      assert Module4.decode(<<0x11>>) == :error
    end
  end
end
