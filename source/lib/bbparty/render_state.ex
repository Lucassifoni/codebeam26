defmodule Bbparty.RenderState do
  alias Bbparty.FontMap
  alias Bbparty.RenderState.Editing
  alias Bbparty.RenderState.Font
  alias Bbparty.RenderState.Keys
  alias Bbparty.RenderState.Sizings
  alias Bbparty.RenderState.Projections
  alias Bbparty.RenderState.TextLayout
  alias Bbparty.RenderState.TextSource

  defstruct [
    :zoom,
    :kerning,
    :leading,
    :selected_font,
    :available_features,
    :text,
    :text_quantity,
    :text_source,
    :alignment,
    :transform_toupper,
    :cumulative_features,
    :cursor,
    :goal_x,
    :shift_down,
    :caps_lock,
    :pending_diacritic,
    :reset_pressed_at
  ]

  @type t :: %__MODULE__{}

  @type command :: Projections.command()

  @layout_fields [
    :text,
    :text_quantity,
    :text_source,
    :kerning,
    :leading,
    :selected_font,
    :alignment,
    :transform_toupper,
    :cumulative_features,
    :pending_diacritic
  ]

  @fit_bounds {8, 200}

  def new() do
    %__MODULE__{
      zoom: 0.0,
      kerning: 0,
      leading: 1.2,
      selected_font: nil,
      available_features: [],
      text: "",
      text_quantity: 0,
      text_source: :user,
      alignment: :left,
      transform_toupper: false,
      cumulative_features: [],
      cursor: 0,
      goal_x: nil,
      shift_down: false,
      caps_lock: false,
      pending_diacritic: nil,
      reset_pressed_at: nil
    }
  end

  def apply(state, event, %TextLayout{} = layout) do
    {new_state, effects} = do_apply(state, event, layout)
    {new_state, Projections.propagate(state, new_state), effects}
  end

  def apply(state, event), do: __MODULE__.apply(state, event, TextLayout.empty())

  defp do_apply(state, {id, :nudge, value}, _layout), do: {Sizings.nudge(state, id, value), []}

  defp do_apply(state, {_id, :nudge_quantity, chars}, _layout) when is_integer(chars),
    do: {TextSource.nudge_quantity(state, chars), []}

  defp do_apply(state, {_id, :toggle_feature, tag}, _layout) when is_binary(tag),
    do: {Font.toggle_feature(state, tag), []}

  defp do_apply(state, {_id, :set_feature, {tag, on?}}, _layout)
       when is_binary(tag) and is_boolean(on?),
       do: {Font.set_feature(state, tag, on?), []}

  defp do_apply(state, {_id, :select_font, font}, _layout), do: {Font.select(state, font), []}

  defp do_apply(state, {_id, :key_down, payload}, layout) when is_map(payload),
    do: Keys.press(state, payload, layout)

  defp do_apply(state, {_id, :key_down, char}, _layout) when is_binary(char),
    do: {Keys.type(state, char), []}

  defp do_apply(state, {_id, :key_up, payload}, _layout) when is_map(payload),
    do: Keys.release(state, payload)

  defp do_apply(state, {_id, :roll, %{word: word}}, _layout) when is_binary(word),
    do: {TextSource.roll_word(state, word), []}

  defp do_apply(state, _event, _layout), do: {state, []}

  @spec reset(t()) :: t()
  def reset(state) do
    %{
      new()
      | selected_font: state.selected_font,
        cumulative_features: Enum.filter(state.cumulative_features, &FontMap.latching?/1)
    }
  end

  @spec hard_reset() :: {t(), [{:bus, :reboot_boards}]}
  def hard_reset, do: {new(), [{:bus, :reboot_boards}]}

  defdelegate effective_text(state), to: TextSource
  defdelegate overridden?(state), to: TextSource

  @spec composition(t()) :: {String.t(), String.t() | nil, String.t()}
  def composition(%__MODULE__{pending_diacritic: mark} = state) when is_binary(mark) do
    case overridden?(state) do
      true ->
        {effective_text(state), nil, ""}

      false ->
        {before, rest} = String.split_at(state.text, Editing.cursor_in(state))
        {before, mark, rest}
    end
  end

  def composition(state), do: {effective_text(state), nil, ""}

  @spec magnification(t()) :: float()
  def magnification(%__MODULE__{zoom: zoom}), do: :math.pow(2, zoom)

  @spec fit_bounds() :: {number(), number()}
  def fit_bounds, do: @fit_bounds

  @spec layout_fingerprint(t()) :: String.t()
  def layout_fingerprint(state),
    do: state |> Map.take(@layout_fields) |> :erlang.phash2() |> Integer.to_string()

  @spec referenced_ids() :: MapSet.t(String.t())
  def referenced_ids do
    Sizings.referenced_ids()
    |> Enum.concat(Projections.referenced_ids())
    |> Enum.concat(Keys.referenced_ids())
    |> MapSet.new()
  end


end
