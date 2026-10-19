defmodule Hardware.Components.RotaryEncoder do
  @behaviour Hardware.Component

  defstruct quantity: 0, chars_per_detent: 1, invert: false, module: nil

  @impl true
  def new(opts) do
    %__MODULE__{
      quantity: 0,
      chars_per_detent: attr(opts, :chars_per_detent, 1),
      invert: bool_attr(opts, :invert, false),
      module: attr(opts, :module, nil)
    }
  end

  @impl true
  def events(), do: [:turn, :detents, :set_quantity]

  @impl true
  def editable_fields(), do: [module: :integer, chars_per_detent: :integer, invert: :boolean]

  @impl true
  def dimensions(), do: {24, 24}

  @impl true
  def input_binding(%__MODULE__{module: module}) when not is_nil(module), do: {:encoder, module}
  def input_binding(_state), do: nil

  @spec field_binding(%__MODULE__{}) :: {:field, :text_quantity}
  def field_binding(%__MODULE__{}), do: {:field, :text_quantity}

  @impl true
  def handle_event(%__MODULE__{} = state, :detents, detents) when is_number(detents) do
    handle_event(state, :turn, orient(detents, state.invert))
  end

  def handle_event(%__MODULE__{} = state, :turn, detents) when is_number(detents) do
    case round(detents * state.chars_per_detent) do
      0 -> {:ok, state}
      chars -> {:ok, state, [{:nudge_quantity, chars}]}
    end
  end

  def handle_event(%__MODULE__{} = state, :set_quantity, quantity) when is_integer(quantity),
    do: {:ok, %{state | quantity: quantity}}

  def handle_event(%__MODULE__{} = state, _event, _payload), do: {:ok, state}

  defp orient(detents, true), do: -detents
  defp orient(detents, false), do: detents

  defp attr(opts, key, default), do: Keyword.get(opts, key) || default

  defp bool_attr(opts, key, default) do
    case Keyword.get(opts, key) do
      nil -> default
      value -> value
    end
  end
end
