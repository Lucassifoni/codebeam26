defmodule Bbparty.RenderState.Keys do
  alias Bbparty.Keyboard.Action
  alias Bbparty.RenderState
  alias Bbparty.RenderState.Editing
  alias Bbparty.RenderState.TextLayout
  alias Bbparty.RenderState.TextSource

  @reset "__RESET__"

  @hard_reset_hold_ms 5_000

  @printer "printer"

  @keeps_pending [:space, :shift, :capslock, :print, :dead]

  @spec press(RenderState.t(), map(), TextLayout.t()) :: {RenderState.t(), list()}
  def press(state, payload, layout) do
    case Action.parse(Map.get(payload, :action)) do
      {:ok, :dead} ->
        {state
         |> release_quantity(:dead)
         |> dead(effective_char(payload, state.shift_down, state.caps_lock)), []}

      {:ok, action} ->
        {state
         |> release_quantity(action)
         |> act(action, layout)
         |> hold(action, Map.get(payload, :at)), effects_for(action)}

      :error ->
        {type(state, effective_char(payload, state.shift_down, state.caps_lock)), []}
    end
  end

  @spec release(RenderState.t(), map()) :: {RenderState.t(), list()}
  def release(state, payload),
    do: release(state, Action.parse(Map.get(payload, :action)), Map.get(payload, :at))

  @spec type(RenderState.t(), String.t() | nil) :: RenderState.t()
  def type(state, @reset), do: RenderState.reset(state)
  def type(state, char), do: state |> TextSource.clear_quantity() |> Editing.type(char)

  @spec effective_char(map(), boolean(), boolean()) :: String.t() | nil
  def effective_char(payload, shift_down, caps_lock),
    do: pick(Map.get(payload, :char), Map.get(payload, :shift), shift_down, caps_lock)

  @spec hard_reset_hold_ms() :: pos_integer()
  def hard_reset_hold_ms, do: @hard_reset_hold_ms

  @spec referenced_ids() :: [String.t()]
  def referenced_ids, do: [@printer]

  defp dead(state, @reset), do: RenderState.reset(state)
  defp dead(state, mark), do: Editing.arm(state, mark)

  defp release(state, {:ok, :shift}, _at), do: {%{state | shift_down: false}, []}

  defp release(%RenderState{reset_pressed_at: down}, {:ok, :reset}, at)
       when is_integer(down) and is_integer(at) and at - down >= @hard_reset_hold_ms,
       do: RenderState.hard_reset()

  defp release(state, {:ok, :reset}, _at), do: {%{state | reset_pressed_at: nil}, []}
  defp release(state, _action, _at), do: {state, []}

  defp release_quantity(state, action) when action in [:print, :shift, :capslock], do: state

  defp release_quantity(state, action) do
    case action in Action.selectors() do
      true -> state
      false -> TextSource.clear_quantity(state)
    end
  end

  defp effects_for(:print), do: [{@printer, :print}]
  defp effects_for(_action), do: []

  defp hold(state, :reset, at), do: %{state | reset_pressed_at: at}
  defp hold(state, _action, _at), do: state

  defp pick(_char, shift, true, _caps) when is_binary(shift), do: shift
  defp pick(char, shift, _down, true), do: latched(char, shift)
  defp pick(char, _shift, _down, _caps), do: char

  defp latched(char, shift) when is_binary(shift) do
    case cased?(shift) do
      true -> shift
      false -> char
    end
  end

  defp latched(char, _shift), do: char

  defp cased?(text), do: String.downcase(text) != String.upcase(text)

  defp act(%RenderState{pending_diacritic: mark} = state, :backspace, _layout)
       when is_binary(mark),
       do: Editing.disarm(state)

  defp act(%RenderState{pending_diacritic: mark} = state, action, layout)
       when is_binary(mark) and action not in @keeps_pending,
       do: act(Editing.disarm(state), action, layout)

  defp act(state, :left, _layout), do: Editing.move_to(state, state.cursor - 1)
  defp act(state, :right, _layout), do: Editing.move_to(state, state.cursor + 1)
  defp act(state, :backspace, _layout), do: Editing.backspace(state)
  defp act(state, :enter, _layout), do: Editing.type(state, "\n")
  defp act(state, :space, _layout), do: Editing.type(state, " ")
  defp act(state, :shift, _layout), do: %{state | shift_down: true}
  defp act(state, :capslock, _layout), do: %{state | caps_lock: not state.caps_lock}
  defp act(state, :up, layout), do: Editing.vertical(state, -1, layout)
  defp act(state, :down, layout), do: Editing.vertical(state, 1, layout)
  defp act(state, :reset, _layout), do: RenderState.reset(state)
  defp act(state, :print, _layout), do: state
  defp act(state, :dead, _layout), do: state

  defp act(state, :align_left, _layout), do: %{state | alignment: :left}
  defp act(state, :align_center, _layout), do: %{state | alignment: :center}

  defp act(state, :uppercase, _layout),
    do: %{state | transform_toupper: not state.transform_toupper}

  defp act(state, :source_user, _layout), do: TextSource.select(state, :source_user)
  defp act(state, :source_font_name, _layout), do: TextSource.select(state, :source_font_name)
  defp act(state, :source_alpha_upper, _layout), do: TextSource.select(state, :source_alpha_upper)
  defp act(state, :source_alpha_lower, _layout), do: TextSource.select(state, :source_alpha_lower)
  defp act(state, :source_numbers, _layout), do: TextSource.select(state, :source_numbers)
end
