defmodule Bbparty.Bus.FrameTest do
  use ExUnit.Case, async: true

  alias Bbparty.Bus.Cobs
  alias Bbparty.Bus.Frame
  alias Bbparty.Bus.Frame.Reader

  test "encode appends a 0x00 delimiter to the COBS body" do
    body = <<0x02, 0x11, 0x22>>
    encoded = Frame.encode(body)
    assert encoded == Cobs.encode(body) <> <<0x00>>
    assert :binary.last(encoded) == 0x00
  end

  test "reassembles a frame fed one byte at a time" do
    body = <<0x02, 0x00, 0x11, 0x00, 0x42>>
    wire = Frame.encode(body)

    {reader, frames} =
      Enum.reduce(:binary.bin_to_list(wire), {Reader.new(), []}, fn byte, {reader, acc} ->
        {reader, new_frames} = Reader.push(reader, <<byte>>)
        {reader, acc ++ new_frames}
      end)

    assert frames == [body]
    assert reader.buffer == <<>>
  end

  test "extracts two frames present in one chunk" do
    b1 = <<0x01, 0x02, 0x03>>
    b2 = <<0xAA, 0x00, 0xBB>>
    chunk = Frame.encode(b1) <> Frame.encode(b2)

    {reader, frames} = Reader.push(Reader.new(), chunk)
    assert frames == [b1, b2]
    assert reader.buffer == <<>>
  end

  test "reassembles a frame split across two push calls" do
    body = <<0x10, 0x20, 0x00, 0x30>>
    wire = Frame.encode(body)
    split_at = div(byte_size(wire), 2)
    <<part1::binary-size(split_at), part2::binary>> = wire

    {reader, frames1} = Reader.push(Reader.new(), part1)
    assert frames1 == []

    {_reader, frames2} = Reader.push(reader, part2)
    assert frames2 == [body]
  end

  test "ignores an empty frame (lone delimiter)" do
    body = <<0x05, 0x06>>
    chunk = <<0x00>> <> Frame.encode(body) <> <<0x00, 0x00>>

    {_reader, frames} = Reader.push(Reader.new(), chunk)
    assert frames == [body]
  end

  test "drops a malformed COBS frame and continues" do
    good = <<0x07>>
    chunk = <<0x05, 0x01, 0x00>> <> Frame.encode(good)

    {_reader, frames} = Reader.push(Reader.new(), chunk)
    assert frames == [good]
  end
end
