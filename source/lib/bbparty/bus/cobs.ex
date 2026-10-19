defmodule Bbparty.Bus.Cobs do
  @spec encode(binary()) :: binary()
  def encode(data) when is_binary(data) do
    encode_block(data, [], [])
  end

  @spec decode(binary()) :: {:ok, binary()} | :error
  def decode(data) when is_binary(data) do
    decode(data, [])
  end

  defp encode_block(<<>>, group, acc) do
    finalize(group, acc)
  end

  defp encode_block(<<0, rest::binary>>, group, acc) do
    encode_block(rest, [], flush(group, acc))
  end

  defp encode_block(<<byte, rest::binary>>, group, acc) do
    group = [group, byte]

    case group_length(group) do
      254 -> encode_block(rest, [], flush_full(group, acc))
      _ -> encode_block(rest, group, acc)
    end
  end

  defp flush(group, acc) do
    code = group_length(group) + 1
    [acc, code, group]
  end

  defp flush_full(group, acc) do
    [acc, 0xFF, group]
  end

  defp finalize(group, acc) do
    code = group_length(group) + 1
    IO.iodata_to_binary([acc, code, group])
  end

  defp group_length(group), do: IO.iodata_length(group)

  defp decode(<<>>, acc), do: {:ok, IO.iodata_to_binary(acc)}

  defp decode(<<code, rest::binary>>, acc) do
    len = code - 1

    case rest do
      <<chunk::binary-size(^len), tail::binary>> ->
        acc = [acc, chunk]

        cond do
          code == 0xFF -> decode(tail, acc)
          tail == <<>> -> {:ok, IO.iodata_to_binary(acc)}
          true -> decode(tail, [acc, 0])
        end

      _ ->
        :error
    end
  end
end
