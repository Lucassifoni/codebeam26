defmodule Hardware.Components.PushButton do
  @behaviour Hardware.Component

  defstruct [:pushed, :char, :shift, :action, :red]

  @impl true
  def new(opts) do
    %__MODULE__{
      pushed: false,
      char: Keyword.get(opts, :char, nil),
      shift: Keyword.get(opts, :shift, nil),
      action: Keyword.get(opts, :action, nil),
      red: Keyword.get(opts, :red) == true
    }
  end

  @impl true
  def editable_fields(),
    do: [char: :string, shift: :string, action: :string, red: :boolean]

  @impl true
  def events(), do: [:key_up, :key_down, :set_pushed]

  @impl true
  def dimensions(), do: {17, 17}

  @impl true
  def handle_event(%__MODULE__{char: nil, action: nil} = state, :key_up, _),
    do: {:ok, %{state | pushed: false}, []}

  @impl true
  def handle_event(state, :key_up, _),
    do: {:ok, %{state | pushed: false}, [{:key_up, meaning(state)}]}

  @impl true
  def handle_event(%__MODULE__{char: nil, action: nil} = state, :key_down, _),
    do: {:ok, %{state | pushed: true}, []}

  @impl true
  def handle_event(state, :key_down, _),
    do: {:ok, %{state | pushed: true}, [{:key_down, meaning(state)}]}

  @impl true
  def handle_event(state, :set_pushed, pushed) when is_boolean(pushed),
    do: {:ok, %{state | pushed: pushed}, []}

  @spec meaning(%__MODULE__{}) :: %{char: String.t() | nil, shift: term(), action: term()}
  def meaning(%__MODULE__{} = state),
    do: %{char: state.char, shift: state.shift, action: state.action}
end
