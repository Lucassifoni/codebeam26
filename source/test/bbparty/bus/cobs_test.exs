defmodule Bbparty.Bus.CobsTest do
  use ExUnit.Case, async: true

  alias Bbparty.Bus.Cobs

  describe "known vectors" do
    test "encode single non-zero byte" do
      assert Cobs.encode(<<0x11>>) == <<0x02, 0x11>>
    end

    test "encode empty binary" do
      assert Cobs.encode(<<>>) == <<0x01>>
    end

    test "encode single zero byte" do
      assert Cobs.encode(<<0x00>>) == <<0x01, 0x01>>
    end

    test "encode <<1,2,3>>" do
      assert Cobs.encode(<<1, 2, 3>>) == <<0x04, 1, 2, 3>>
    end

    test "encode never contains a zero byte" do
      for data <- [<<0>>, <<0, 0, 0>>, <<1, 0, 2, 0, 3>>, :binary.copy(<<1>>, 300)] do
        refute String.contains?(Cobs.encode(data), <<0>>)
      end
    end
  end

  describe "round trip" do
    inputs = [
      empty: <<>>,
      all_zeros: <<0, 0, 0, 0>>,
      one_two_three: <<1, 2, 3>>,
      interior_zeros: <<1, 0, 2, 0, 0, 3, 4, 0>>,
      leading_zero: <<0, 1, 2, 3>>,
      trailing_zero: <<1, 2, 3, 0>>,
      long_run_255: :binary.copy(<<1>>, 255),
      long_run_300: :binary.copy(<<1>>, 300),
      run_with_zero: :binary.copy(<<7>>, 260) <> <<0>> <> :binary.copy(<<9>>, 10)
    ]

    for {name, data} <- inputs do
      test "round-trips #{name}" do
        data = unquote(data)
        assert {:ok, ^data} = Cobs.decode(Cobs.encode(data))
      end
    end

    test "round-trips many random binaries including zeros and long runs" do
      for _ <- 1..200 do
        len = :rand.uniform(600) - 1
        data = for(_ <- 1..len, into: <<>>, do: <<:rand.uniform(256) - 1>>)
        assert {:ok, ^data} = Cobs.decode(Cobs.encode(data))
      end
    end
  end

  describe "decode errors" do
    test "code overrunning the buffer is an error" do
      assert Cobs.decode(<<0x05, 1, 2>>) == :error
    end

    test "a zero code byte is an error" do
      assert Cobs.decode(<<0x00>>) == :error
    end

    test "trailing group promising more bytes than present is an error" do
      assert Cobs.decode(<<0x03, 0x41>>) == :error
    end
  end
end
