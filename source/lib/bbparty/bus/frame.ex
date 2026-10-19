defmodule Bbparty.Bus.Frame do
  alias Bbparty.Bus.Cobs

  @delimiter 0x00

  @spec encode(binary()) :: binary()
  def encode(body) when is_binary(body) do
    Cobs.encode(body) <> <<@delimiter>>
  end

  defmodule Reader do
    alias Bbparty.Bus.Cobs

    @delimiter 0x00

    @enforce_keys [:buffer]
    defstruct buffer: <<>>

    @type t :: %__MODULE__{buffer: binary()}

    @spec new() :: t()
    def new, do: %__MODULE__{buffer: <<>>}

    @spec push(t(), binary()) :: {t(), [binary()]}
    def push(%__MODULE__{buffer: buffer}, chunk) when is_binary(chunk) do
      {frames, rest} = split(buffer <> chunk, [])
      {%__MODULE__{buffer: rest}, frames}
    end

    defp split(data, acc) do
      case :binary.split(data, <<@delimiter>>) do
        [rest] ->
          {Enum.reverse(acc), rest}

        [segment, rest] ->
          split(rest, prepend_frame(segment, acc))
      end
    end

    defp prepend_frame(<<>>, acc), do: acc

    defp prepend_frame(segment, acc) do
      case Cobs.decode(segment) do
        {:ok, body} -> [body | acc]
        :error -> acc
      end
    end
  end
end
