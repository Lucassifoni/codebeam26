defmodule Hardware.Components.Joystick do
  @behaviour Hardware.Component

  @virtual_deadzone 3

  defstruct center: 2048,
            low: 0,
            high: 4095,
            deadzone: 80,
            smoothing: 0.2,
            sensitivity: 0.4,
            invert: false,
            module: nil,
            axis: nil,
            ema: 2048.0

  @impl true
  def new(opts) do
    center = attr(opts, :center, 2048)

    %__MODULE__{
      center: center,
      low: attr(opts, :low, 0),
      high: attr(opts, :high, 4095),
      deadzone: attr(opts, :deadzone, 80),
      smoothing: attr(opts, :smoothing, 0.2),
      sensitivity: attr(opts, :sensitivity, 0.4),
      invert: bool_attr(opts, :invert, false),
      module: attr(opts, :module, nil),
      axis: attr(opts, :axis, nil),
      ema: center * 1.0
    }
  end

  @impl true
  def events(), do: [:axis, :deflect]

  @impl true
  def editable_fields() do
    [
      center: :integer,
      low: :integer,
      high: :integer,
      deadzone: :integer,
      smoothing: :float,
      sensitivity: :float,
      invert: :boolean,
      module: :integer,
      axis: :integer
    ]
  end

  @impl true
  def dimensions(), do: {50, 45}

  @impl true
  def input_binding(%__MODULE__{module: m, axis: a}) when not is_nil(m) and not is_nil(a),
    do: {:axis, m, a}

  def input_binding(_state), do: nil

  @impl true
  def handle_event(%__MODULE__{} = state, :axis, raw) when is_number(raw) do
    ema = state.ema + (raw - state.ema) * state.smoothing
    {:ok, %{state | ema: ema}, emits(normalize(ema, state), state)}
  end

  def handle_event(%__MODULE__{} = state, :deflect, travel) when is_number(travel) do
    {:ok, state, emits(virtual_norm(travel), state)}
  end

  @spec normalize(number(), %__MODULE__{}) :: float()
  def normalize(raw, %__MODULE__{center: c, deadzone: dz} = state) do
    orient(side(raw - c, dz, state), state.invert)
  end

  defp orient(norm, true), do: -norm
  defp orient(norm, false), do: norm

  defp side(deflection, dz, %__MODULE__{high: hi, center: c}) when deflection > dz,
    do: clamp_unit(ratio(deflection - dz, hi - c - dz))

  defp side(deflection, dz, %__MODULE__{low: lo, center: c}) when deflection < -dz,
    do: -clamp_unit(ratio(-deflection - dz, c - lo - dz))

  defp side(_deflection, _dz, _state), do: 0.0

  defp virtual_norm(travel) when abs(travel) < @virtual_deadzone, do: 0.0
  defp virtual_norm(travel), do: clamp_unit(abs(travel) / 100) * sign(travel)

  defp emits(norm, _state) when norm == 0.0, do: []
  defp emits(norm, state), do: [{:nudge, norm * 100 * state.sensitivity}]

  defp ratio(_num, span) when span <= 0, do: 1.0
  defp ratio(num, span), do: num / span

  defp clamp_unit(x), do: x |> max(0.0) |> min(1.0)

  defp sign(x) when x >= 0, do: 1
  defp sign(_x), do: -1

  defp attr(opts, key, default), do: Keyword.get(opts, key) || default

  defp bool_attr(opts, key, default) do
    case Keyword.get(opts, key) do
      nil -> default
      value -> value
    end
  end
end
