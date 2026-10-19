defmodule Bbparty.Bus.Module2 do
  @module_id 0x02

  @spec module_id() :: 0x02
  def module_id, do: @module_id

  @spec ping() :: binary()
  def ping, do: <<0x11>>

  @spec set_leds(0..255 | binary()) :: binary()
  def set_leds(bits) when is_integer(bits) and bits in 0..255, do: <<0x12, bits>>
  def set_leds(<<bits>>), do: <<0x12, bits>>

  @spec set_gauge(0..255, 0..255) :: binary()
  def set_gauge(index, value) when index in 0..255 and value in 0..255 do
    <<0x13, index, value>>
  end

  @spec set_brightness(0..255) :: binary()
  def set_brightness(level) when level in 0..255, do: <<0x15, level>>

  @spec request_sync() :: binary()
  def request_sync, do: <<0x16>>

  @spec write_tag(String.t()) :: binary()
  def write_tag(text) when is_binary(text) do
    len = byte_size(text)

    if len > 46 do
      raise ArgumentError, "write_tag text must be at most 46 bytes, got #{len}"
    end

    <<0x14, len, text::binary>>
  end

  @spec key_event(0..255, boolean()) :: binary()
  def key_event(index, pressed) when index in 0..255 and is_boolean(pressed) do
    <<0x82, index, if(pressed, do: 1, else: 0)>>
  end

  @spec decode(binary()) :: {:ok, term()} | :error
  def decode(<<0x81>>), do: {:ok, {:pong}}
  def decode(<<0x82, index, pressed>>), do: {:ok, {:key_event, index, pressed == 1}}

  def decode(<<0x83, a::16, b::16, c::16>>) do
    {:ok, {:axes, {a, b, c}}}
  end

  def decode(<<0x84, d>>), do: {:ok, {:encoder, signed_int8(d)}}

  def decode(<<0x85, uid_len, uid::binary-size(uid_len), sak, len, text::binary-size(len)>>) do
    {:ok, {:tag_read, %{uid: uid, sak: sak, text: text}}}
  end

  def decode(<<0x86>>), do: {:ok, {:tag_gone}}

  def decode(<<0x87, status, uid_len, uid::binary-size(uid_len)>>) do
    {:ok, {:write_result, %{ok: status == 0, uid: uid}}}
  end

  def decode(<<0x88, bits>>), do: {:ok, {:snapshot, bits}}

  def decode(<<0x8F, subsystem, index>>), do: {:ok, {:fault, subsystem(subsystem), index}}

  def decode(_), do: :error

  @spec fault_description(atom() | 0..255, 0..255) :: String.t()
  def fault_description(:nfc, 0x00),
    do:
      "NFC: nothing answered on I2C — check SDA/SCL are not swapped, the level shifter's channels, and the reader's 5 V rail"

  def fault_description(:nfc, 0xFF),
    do: "NFC: the reader answered at 0x28 but would not initialise"

  def fault_description(:nfc, address),
    do:
      "NFC: no reader at 0x28, but 0x#{Integer.to_string(address, 16)} answered — the board is strapped to another address"

  def fault_description(:nfc_task, _index),
    do: "NFC: the polling task could not be started — the reader is never polled"

  def fault_description(:gauge, index), do: "gauge #{index}: ledc channel would not attach"

  def fault_description(:led_brightness, _index),
    do: "LED brightness: the /OE ledc channel would not attach"

  def fault_description(subsystem, index), do: "subsystem #{subsystem}, index #{index}"

  defp subsystem(0x01), do: :gauge
  defp subsystem(0x02), do: :led_brightness
  defp subsystem(0x03), do: :nfc
  defp subsystem(0x04), do: :nfc_task
  defp subsystem(other), do: other

  @spec signed_int8(0..255) :: -128..127
  defp signed_int8(byte) do
    <<value::signed-integer-8>> = <<byte>>
    value
  end
end
