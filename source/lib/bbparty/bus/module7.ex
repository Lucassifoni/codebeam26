defmodule Bbparty.Bus.Module7 do
  @module_id 0x07

  @snapshot_bytes 8
  @led_bytes 8

  @spec module_id() :: 0x07
  def module_id, do: @module_id

  @spec ping() :: binary()
  def ping, do: <<0x11>>

  @spec set_leds(binary()) :: binary()
  def set_leds(<<bits::binary-size(@led_bytes)>>), do: <<0x12, bits::binary>>

  @spec request_sync() :: binary()
  def request_sync, do: <<0x16>>

  @spec decode(binary()) :: {:ok, term()} | :error
  def decode(<<0x81>>), do: {:ok, {:pong}}
  def decode(<<0x82, drive, sense, 0>>), do: {:ok, {:key_event, drive, sense, false}}
  def decode(<<0x82, drive, sense, 1>>), do: {:ok, {:key_event, drive, sense, true}}

  def decode(<<0x88, bits::binary-size(@snapshot_bytes)>>) do
    {:ok, {:snapshot, :binary.decode_unsigned(bits, :little)}}
  end

  def decode(_), do: :error

  @spec led_bytes() :: pos_integer()
  def led_bytes, do: @led_bytes
end
