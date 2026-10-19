defmodule Bbparty.Bus.Module4 do
  alias Bbparty.TrackballPanel

  @module_id 0x04

  @spec module_id() :: 0x04
  def module_id, do: @module_id

  @spec ping() :: binary()
  def ping, do: <<0x11>>

  @spec decode(binary()) :: {:ok, term()} | :error
  def decode(<<0x81>>), do: {:ok, {:pong}}

  def decode(<<0x82, bits>>) do
    case bits < Bitwise.bsl(1, TrackballPanel.buttons()) do
      true -> {:ok, {:buttons, bits}}
      false -> :error
    end
  end

  def decode(<<0x83, count>>), do: {:ok, {:activity, count}}
  def decode(_), do: :error
end
