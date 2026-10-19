defmodule Bbparty.RenderState.TextSource do
  alias Bbparty.RenderState
  alias Bbparty.RenderState.TextToWrite

  @alpha_upper "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  @alpha_lower "abcdefghijklmnopqrstuvwxyz"
  @numbers "0123456789"

  @sources %{
    source_user: :user,
    source_font_name: :font_name,
    source_alpha_upper: :alpha_upper,
    source_alpha_lower: :alpha_lower,
    source_numbers: :numbers
  }

  @spec sources() :: %{atom() => atom()}
  def sources, do: @sources

  @spec select(RenderState.t(), atom()) :: RenderState.t()
  def select(state, action) when is_map_key(@sources, action),
    do: %{state | text_source: Map.fetch!(@sources, action)}

  @spec effective_text(RenderState.t()) :: String.t()
  def effective_text(%RenderState{text_source: :font_name, selected_font: font}), do: font || ""
  def effective_text(%RenderState{text_source: :alpha_upper}), do: @alpha_upper
  def effective_text(%RenderState{text_source: :alpha_lower}), do: @alpha_lower
  def effective_text(%RenderState{text_source: :numbers}), do: @numbers

  def effective_text(%RenderState{text_quantity: n}) when is_integer(n) and n > 0,
    do: TextToWrite.take(n)

  def effective_text(%RenderState{text: text}), do: text

  @spec overridden?(RenderState.t()) :: boolean()
  def overridden?(%RenderState{text_source: source}) when source != :user, do: true
  def overridden?(%RenderState{text_quantity: n}), do: is_integer(n) and n > 0

  @spec clear_quantity(RenderState.t()) :: RenderState.t()
  def clear_quantity(state), do: %{state | text_quantity: 0, text_source: :user}

  @spec nudge_quantity(RenderState.t(), integer()) :: RenderState.t()
  def nudge_quantity(state, chars),
    do: %{state | text_quantity: clamp(state.text_quantity + chars, 0, TextToWrite.count())}

  @spec roll_word(RenderState.t(), String.t()) :: RenderState.t()
  def roll_word(state, word) when is_binary(word) do
    %{
      clear_quantity(state)
      | text: word,
        cursor: String.length(word),
        goal_x: nil,
        pending_diacritic: nil
    }
  end

  defp clamp(value, low, high), do: value |> max(low) |> min(high)
end
