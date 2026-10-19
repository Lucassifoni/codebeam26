defmodule Hardware.Components.PushButtonWithLed do
  @behaviour Hardware.Component
  @behaviour Hardware.Output

  alias Bbparty.Bus.LedShadow
  alias Bbparty.Keyboard.Action

  defstruct pushed: false,
            lit: false,
            char: nil,
            shift: nil,
            action: nil,
            module: nil,
            led: nil

  @impl Hardware.Component
  def new(opts) do
    %__MODULE__{
      pushed: false,
      lit: false,
      char: Keyword.get(opts, :char),
      shift: Keyword.get(opts, :shift),
      action: Keyword.get(opts, :action),
      module: Keyword.get(opts, :module),
      led: Keyword.get(opts, :led)
    }
  end

  @impl Hardware.Component
  def events(), do: [:key_up, :key_down, :set_pushed, :set_lit]

  @impl Hardware.Component
  def editable_fields(),
    do: [char: :string, shift: :string, action: :string, module: :integer, led: :integer]

  @impl Hardware.Component
  def dimensions(), do: {17, 17}

  @spec action_binding(%__MODULE__{}) :: {:action, atom()} | nil
  def action_binding(%__MODULE__{action: action}) do
    case Action.parse(action) do
      {:ok, parsed} -> {:action, parsed}
      :error -> nil
    end
  end

  @impl Hardware.Component
  def handle_event(%__MODULE__{char: nil, action: nil} = state, :key_up, _),
    do: {:ok, %{state | pushed: false}, []}

  def handle_event(state, :key_up, _),
    do: {:ok, %{state | pushed: false}, [{:key_up, meaning(state)}]}

  def handle_event(%__MODULE__{char: nil, action: nil} = state, :key_down, _),
    do: {:ok, %{state | pushed: true}, []}

  def handle_event(state, :key_down, _),
    do: {:ok, %{state | pushed: true}, [{:key_down, meaning(state)}]}

  def handle_event(state, :set_pushed, pushed) when is_boolean(pushed),
    do: {:ok, %{state | pushed: pushed}, []}

  def handle_event(state, :set_lit, lit) when is_boolean(lit), do: {:ok, %{state | lit: lit}}

  def handle_event(state, _event, _payload), do: {:ok, state}

  @impl Hardware.Output
  def handle_transition(%__MODULE__{} = _old, %__MODULE__{} = new, _opts) do
    case bound?(new) do
      true -> LedShadow.put(new.module, new.led, new.lit)
      false -> :ok
    end

    :ok
  end

  @spec meaning(%__MODULE__{}) :: %{char: String.t() | nil, shift: term(), action: term()}
  def meaning(%__MODULE__{} = state),
    do: %{char: state.char, shift: state.shift, action: state.action}

  defp bound?(%__MODULE__{module: module, led: led}), do: not is_nil(module) and not is_nil(led)
end
