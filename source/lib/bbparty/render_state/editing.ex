defmodule Bbparty.RenderState.Editing do
  alias Bbparty.Keyboard.Diacritic
  alias Bbparty.RenderState
  alias Bbparty.RenderState.TextLayout

  @spec type(RenderState.t(), String.t() | nil) :: RenderState.t()
  def type(state, nil), do: state

  def type(%RenderState{pending_diacritic: mark} = state, " ") when is_binary(mark),
    do: state |> disarm() |> type(mark)

  def type(%RenderState{pending_diacritic: mark} = state, char) when is_binary(mark) do
    case Diacritic.compose(mark, char) do
      {:ok, composed} -> state |> disarm() |> type(composed)
      :error -> state |> disarm() |> type(mark) |> type(char)
    end
  end

  def type(state, char) do
    {before, rest} = String.split_at(state.text, cursor_in(state))

    %{
      state
      | text: before <> char <> rest,
        cursor: cursor_in(state) + String.length(char),
        goal_x: nil
    }
  end

  @spec arm(RenderState.t(), String.t() | nil) :: RenderState.t()
  def arm(state, nil), do: state

  def arm(%RenderState{pending_diacritic: pending} = state, mark) when is_binary(pending),
    do: state |> disarm() |> type(pending) |> arm(mark)

  def arm(state, mark) do
    case Diacritic.mark?(mark) do
      true -> %{state | pending_diacritic: mark, goal_x: nil}
      false -> type(state, mark)
    end
  end

  @spec disarm(RenderState.t()) :: RenderState.t()
  def disarm(state), do: %{state | pending_diacritic: nil}

  @spec backspace(RenderState.t()) :: RenderState.t()
  def backspace(state), do: backspace(state, cursor_in(state))

  @spec move_to(RenderState.t(), integer()) :: RenderState.t()
  def move_to(state, position),
    do: %{state | cursor: clamp(position, 0, String.length(state.text)), goal_x: nil}

  @spec cursor_in(RenderState.t()) :: non_neg_integer()
  def cursor_in(state), do: clamp(state.cursor, 0, String.length(state.text))

  @spec vertical(RenderState.t(), -1 | 1, TextLayout.t()) :: RenderState.t()
  def vertical(state, direction, layout) do
    case TextLayout.stale?(layout, RenderState.layout_fingerprint(state)) do
      true -> move_line(state, direction, hard_lines(state))
      false -> move_line(state, direction, layout)
    end
  end

  defp backspace(state, 0), do: %{state | cursor: 0, goal_x: nil}

  defp backspace(state, at) do
    {before, rest} = String.split_at(state.text, at)
    %{state | text: String.slice(before, 0, at - 1) <> rest, cursor: at - 1, goal_x: nil}
  end

  defp move_line(state, direction, layout) do
    target = TextLayout.line_of(layout, cursor_in(state)) + direction
    step(state, layout, target, target >= 0 and target < TextLayout.line_count(layout))
  end

  defp step(state, _layout, _target, false), do: state

  defp step(state, layout, target, true) do
    goal = state.goal_x || TextLayout.x_of(layout, cursor_in(state))
    land(state, layout, target, goal, goal && TextLayout.nearest(layout, target, goal))
  end

  defp land(state, layout, target, goal, offset) when is_integer(offset),
    do: %{state | cursor: min(offset, line_limit(state, layout, target)), goal_x: goal}

  defp land(state, layout, target, _goal, _offset) do
    line = TextLayout.line_of(layout, cursor_in(state))
    column = cursor_in(state) - TextLayout.line_start(layout, line)
    landing = TextLayout.line_start(layout, target) + column

    %{state | cursor: min(landing, line_limit(state, layout, target)), goal_x: nil}
  end

  defp line_limit(state, layout, line),
    do: TextLayout.line_end(layout, line, String.length(state.text))

  defp hard_lines(state) do
    starts =
      state.text
      |> String.graphemes()
      |> Enum.with_index()
      |> Enum.filter(fn {grapheme, _index} -> grapheme == "\n" end)
      |> Enum.map(fn {_grapheme, index} -> index + 1 end)

    %TextLayout{fingerprint: RenderState.layout_fingerprint(state), line_starts: [0 | starts]}
  end

  defp clamp(value, low, high), do: value |> max(low) |> min(high)
end
