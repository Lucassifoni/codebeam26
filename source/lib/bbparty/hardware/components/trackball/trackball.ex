defmodule Hardware.Components.Trackball do
  @behaviour Hardware.Component

  @virtual_intensity 128

  @max_intensity 255

  defstruct intensity: 0, rolls: 0, module: nil

  @impl true
  def new(opts), do: %__MODULE__{module: Keyword.get(opts, :module)}

  @impl true
  def events(), do: [:activity, :spin]

  @impl true
  def editable_fields(), do: [module: :integer]

  @impl true
  def dimensions(), do: {40, 40}

  @impl true
  def input_binding(%__MODULE__{module: module}) when not is_nil(module), do: {:trackball, module}
  def input_binding(_state), do: nil

  @impl true
  def handle_event(%__MODULE__{} = state, :activity, count), do: roll(state, intensity(count))
  def handle_event(%__MODULE__{} = state, :spin, _payload), do: roll(state, @virtual_intensity)

  defp roll(state, intensity) do
    {:ok, %{state | intensity: intensity, rolls: state.rolls + 1}, [{:roll, intensity}]}
  end

  defp intensity(count) when is_integer(count), do: count |> max(0) |> min(@max_intensity)

  defp intensity(count) when is_binary(count) do
    case Integer.parse(count) do
      {value, _rest} -> intensity(value)
      :error -> @virtual_intensity
    end
  end

  defp intensity(_count), do: @virtual_intensity
end
