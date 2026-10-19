defmodule Bbparty.Bus.Module3 do
  @module_id 0x03

  @spec module_id() :: 0x03
  def module_id, do: @module_id

  @spec ping() :: binary()
  def ping, do: <<0x11>>

  @spec decode(binary()) :: {:ok, term()} | :error
  def decode(<<0x81>>), do: {:ok, {:pong}}
  def decode(<<0x82, drive, sense, 0>>), do: {:ok, {:key_event, drive, sense, false}}
  def decode(<<0x82, drive, sense, 1>>), do: {:ok, {:key_event, drive, sense, true}}
  def decode(_), do: :error
end
