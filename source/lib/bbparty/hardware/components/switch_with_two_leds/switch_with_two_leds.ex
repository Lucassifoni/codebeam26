defmodule Hardware.Components.SwitchWithTwoLeds do
  @behaviour Hardware.Component
  @behaviour Hardware.Output

  alias Bbparty.Bus.LedShadow

  @modes [:toggle, :position]

  defstruct feature: nil,
            mode: :toggle,
            position: false,
            active: false,
            available: false,
            module: nil,
            status_led: nil,
            available_led: nil

  @impl Hardware.Component
  def new(opts) do
    %__MODULE__{
      feature: attr(opts, :feature),
      mode: parse_mode(Keyword.get(opts, :mode)),
      position: false,
      active: false,
      available: false,
      module: attr(opts, :module),
      status_led: attr(opts, :status_led),
      available_led: attr(opts, :available_led)
    }
  end

  @impl Hardware.Component
  def events(), do: [:key_down, :key_up, :set_position, :set_active, :set_available]

  @impl Hardware.Component
  def editable_fields(),
    do: [
      feature: :string,
      mode: :string,
      module: :integer,
      status_led: :integer,
      available_led: :integer
    ]

  @impl Hardware.Component
  def dimensions(), do: {16, 20}

  @spec modes() :: [atom()]
  def modes(), do: @modes

  @spec feature_binding(%__MODULE__{}) :: {:feature, String.t()} | nil
  def feature_binding(%__MODULE__{feature: feature}) when is_binary(feature),
    do: {:feature, feature}

  def feature_binding(%__MODULE__{}), do: nil

  @impl Hardware.Component
  def handle_event(state, :key_down, _payload), do: transition(state, true)
  def handle_event(state, :key_up, _payload), do: transition(state, false)

  def handle_event(%__MODULE__{mode: :position} = state, :set_position, position)
      when is_boolean(position),
      do: {:ok, %{state | position: position}, set_feature(state, position)}

  def handle_event(state, :set_position, position) when is_boolean(position),
    do: {:ok, %{state | position: position}, []}

  def handle_event(state, :set_active, active) when is_boolean(active),
    do: {:ok, %{state | active: active}}

  def handle_event(state, :set_available, available) when is_boolean(available),
    do: {:ok, %{state | available: available}}

  def handle_event(state, _event, _payload), do: {:ok, state}

  @impl Hardware.Output
  def handle_transition(%__MODULE__{} = _old, %__MODULE__{} = new, _opts) do
    put_led(new, new.status_led, status_lit?(new))
    put_led(new, new.available_led, availability_lit?(new))
    :ok
  end

  @spec status_lit?(%__MODULE__{}) :: boolean()
  def status_lit?(%__MODULE__{active: active, available: available}), do: active and available

  @spec availability_lit?(%__MODULE__{}) :: boolean()
  def availability_lit?(%__MODULE__{available: available}), do: available

  defp transition(%__MODULE__{feature: nil} = state, position),
    do: {:ok, %{state | position: position}, []}

  defp transition(%__MODULE__{mode: :toggle} = state, position),
    do: {:ok, %{state | position: position}, [{:toggle_feature, state.feature}]}

  defp transition(%__MODULE__{mode: :position} = state, position),
    do: {:ok, %{state | position: position}, set_feature(state, position)}

  defp set_feature(%__MODULE__{feature: nil}, _position), do: []

  defp set_feature(%__MODULE__{feature: feature}, position),
    do: [{:set_feature, {feature, position}}]

  defp put_led(%__MODULE__{module: nil}, _channel, _on?), do: :ok
  defp put_led(%__MODULE__{}, nil, _on?), do: :ok
  defp put_led(%__MODULE__{module: module}, channel, on?), do: LedShadow.put(module, channel, on?)

  defp attr(opts, key), do: Keyword.get(opts, key)

  defp parse_mode(mode) when mode in @modes, do: mode
  defp parse_mode("position"), do: :position
  defp parse_mode(_mode), do: :toggle
end
