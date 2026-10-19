defmodule Hardware.Components.FontSelector do
  @behaviour Hardware.Component

  alias Bbparty.FontMap

  defstruct selected_font: nil, module: nil

  @impl true
  def new(opts) do
    %__MODULE__{selected_font: nil, module: Keyword.get(opts, :module)}
  end

  @impl true
  def events(), do: [:select_font, :tag, :set_font]

  @impl true
  def editable_fields(), do: [module: :integer]

  @impl true
  def dimensions(), do: {50, 25}

  @impl true
  def input_binding(%__MODULE__{module: module}) when not is_nil(module), do: {:nfc, module}
  def input_binding(_state), do: nil

  @spec field_binding(%__MODULE__{}) :: {:field, :selected_font}
  def field_binding(%__MODULE__{}), do: {:field, :selected_font}

  @doc """
  A tag or a click on the on-screen list asks the core for a font. The highlight
  only moves when the core projects its choice back with `:set_font`, so the
  selector never shows a font the core does not hold.
  """
  @impl true
  def handle_event(state, :select_font, font), do: {:ok, state, [{:select_font, font}]}

  def handle_event(state, :tag, id) do
    case FontMap.known?(id) do
      true -> {:ok, state, [{:select_font, id}]}
      false -> {:ok, state}
    end
  end

  def handle_event(state, :set_font, font), do: {:ok, %{state | selected_font: font}}
end
