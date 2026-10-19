defmodule Bbparty.Bus.LedShadow.Frame do
  defstruct [:width, :bits]

  @type t :: %__MODULE__{width: pos_integer(), bits: non_neg_integer()}

  @spec new(pos_integer()) :: t()
  def new(width) when is_integer(width) and width > 0, do: %__MODULE__{width: width, bits: 0}

  @spec put(t(), integer(), boolean()) :: t()
  def put(%__MODULE__{width: width} = frame, channel, _on?)
      when not is_integer(channel) or channel < 0 or channel >= width,
      do: frame

  def put(%__MODULE__{bits: bits} = frame, channel, true),
    do: %{frame | bits: Bitwise.bor(bits, Bitwise.bsl(1, channel))}

  def put(%__MODULE__{bits: bits} = frame, channel, false),
    do: %{frame | bits: Bitwise.band(bits, Bitwise.bnot(Bitwise.bsl(1, channel)))}

  @spec lit?(t(), integer()) :: boolean()
  def lit?(%__MODULE__{bits: bits}, channel) when is_integer(channel) and channel >= 0,
    do: Bitwise.band(Bitwise.bsr(bits, channel), 1) == 1

  def lit?(_frame, _channel), do: false

  @spec to_binary(t()) :: binary()
  def to_binary(%__MODULE__{width: width, bits: bits}) do
    for byte <- 0..(bytes(width) - 1), into: <<>> do
      # <<>> is 1 byte
      <<Bitwise.bsr(bits, byte * 8)>>
    end
  end

  @spec bytes(pos_integer()) :: pos_integer()
  def bytes(width), do: div(width + 7, 8)
end
