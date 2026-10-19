defmodule Bbparty.RenderState.Sizings do
  alias Bbparty.RenderState

  @bounds %{
    zoom: {-2.0, 2.0},
    kerning: {-0.2, 2.0},
    leading: {0.5, 2.0}
  }

  @rates %{
    zoom: 0.2,
    kerning: 0.08,
    leading: 0.075
  }

  @joysticks %{
    "font_size_joystick" => :zoom,
    "kerning_joystick" => :kerning,
    "line_height_joystick" => :leading
  }

  @spec bounds() :: %{atom() => {number(), number()}}
  def bounds, do: @bounds

  @spec rates() :: %{atom() => number()}
  def rates, do: @rates

  @spec referenced_ids() :: [String.t()]
  def referenced_ids, do: Map.keys(@joysticks)

  @spec nudge(RenderState.t(), atom() | String.t(), number()) :: RenderState.t()
  def nudge(state, joystick, value),
    do: nudge_field(state, @joysticks[to_string(joystick)], value)

  @spec nudge(number(), number(), number(), {number(), number()}) :: number()
  def nudge(current, value, rate, {min, max}), do: clamp(current + value / 100 * rate, min, max)

  defp nudge_field(state, nil, _value), do: state

  defp nudge_field(state, field, value),
    do: Map.put(state, field, nudge(Map.get(state, field), value, @rates[field], @bounds[field]))

  defp clamp(value, low, high), do: value |> max(low) |> min(high)
end
