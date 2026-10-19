defmodule Bbparty.RenderState.TextLayout do
  defstruct fingerprint: nil, line_starts: [0], xs: %{}

  @type t :: %__MODULE__{
          fingerprint: term(),
          line_starts: [non_neg_integer()],
          xs: %{non_neg_integer() => [number()]}
        }

  @spec empty() :: t()
  def empty, do: %__MODULE__{}

  @spec from_params(map()) :: t()
  def from_params(params) when is_map(params) do
    %__MODULE__{
      fingerprint: params["fingerprint"],
      line_starts: line_starts(params["line_starts"]),
      xs: xs(params["xs"])
    }
  end

  def from_params(_params), do: empty()

  defp line_starts(starts) when is_list(starts) do
    valid = Enum.all?(starts, &(is_integer(&1) and &1 >= 0))
    ascending = starts == Enum.sort(starts) and starts == Enum.uniq(starts)

    case starts != [] and valid and ascending and hd(starts) == 0 do
      true -> starts
      false -> [0]
    end
  end

  defp line_starts(_starts), do: [0]

  defp xs(map) when is_map(map) do
    for {line, values} <- map,
        {index, ""} <- [to_index(line)],
        is_list(values) and values != [] and Enum.all?(values, &is_number/1),
        into: %{},
        do: {index, values}
  end

  defp xs(_map), do: %{}

  defp to_index(line) when is_integer(line), do: {line, ""}
  defp to_index(line) when is_binary(line), do: Integer.parse(line)
  defp to_index(_line), do: :error

  @spec stale?(t(), term()) :: boolean()
  def stale?(%__MODULE__{fingerprint: measured}, current), do: measured != current

  @spec line_count(t()) :: pos_integer()
  def line_count(%__MODULE__{line_starts: starts}), do: length(starts)

  @spec line_of(t(), non_neg_integer()) :: non_neg_integer()
  def line_of(%__MODULE__{line_starts: starts}, offset) do
    starts
    |> Enum.take_while(&(&1 <= offset))
    |> length()
    |> Kernel.-(1)
    |> max(0)
  end

  @spec line_start(t(), integer()) :: non_neg_integer()
  def line_start(%__MODULE__{line_starts: starts}, line),
    do: Enum.at(starts, line, List.last(starts))

  @spec line_end(t(), integer(), non_neg_integer()) :: non_neg_integer()
  def line_end(%__MODULE__{} = layout, line, text_length) do
    case line + 1 < line_count(layout) do
      true -> max(line_start(layout, line + 1) - 1, 0)
      false -> text_length
    end
  end

  @spec x_of(t(), non_neg_integer()) :: number() | nil
  def x_of(%__MODULE__{} = layout, offset) do
    line = line_of(layout, offset)

    case Map.get(layout.xs, line) do
      nil -> nil
      values -> Enum.at(values, offset - line_start(layout, line))
    end
  end

  @spec nearest(t(), integer(), number()) :: non_neg_integer() | nil
  def nearest(%__MODULE__{} = layout, line, goal_x) do
    case Map.get(layout.xs, line) do
      nil ->
        nil

      values ->
        index =
          values
          |> Enum.with_index()
          |> Enum.min_by(fn {x, _index} -> abs(x - goal_x) end)
          |> elem(1)

        line_start(layout, line) + index
    end
  end
end
