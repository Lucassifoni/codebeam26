defmodule Bbparty.RenderState.Font do
  alias Bbparty.FontMap
  alias Bbparty.RenderState

  @spec select(RenderState.t(), String.t()) :: RenderState.t()
  def select(state, ""), do: %{state | selected_font: nil}

  def select(state, font) do
    case FontMap.known?(font) do
      true -> %{state | selected_font: font}
      false -> state
    end
  end

  @spec toggle_feature(RenderState.t(), String.t()) :: RenderState.t()
  def toggle_feature(state, tag),
    do: set_feature(state, tag, tag not in state.cumulative_features)

  @spec set_feature(RenderState.t(), String.t(), boolean()) :: RenderState.t()
  def set_feature(state, tag, on?),
    do: %{state | cumulative_features: put_feature(state.cumulative_features, tag, on?)}

  defp put_feature(features, tag, true) do
    case tag in features do
      true -> features
      false -> features ++ [tag]
    end
  end

  defp put_feature(features, tag, false), do: List.delete(features, tag)
end
