defmodule Hardware.Components.NeedleGauge do
  @behaviour Hardware.Component
  @behaviour Hardware.Output

  alias Bbparty.Bus.{Link, Module2}

  defstruct progress: 50, module: nil, gauge: nil, duty_min: 0, duty_max: 255

  @impl Hardware.Component
  def new(opts) do
    %__MODULE__{
      progress: 50,
      module: attr(opts, :module, nil),
      gauge: attr(opts, :gauge, nil),
      duty_min: attr(opts, :duty_min, 0),
      duty_max: attr(opts, :duty_max, 255)
    }
  end

  @impl Hardware.Component
  def events(), do: [:set_progress]

  @impl Hardware.Component
  def editable_fields(),
    do: [module: :integer, gauge: :integer, duty_min: :integer, duty_max: :integer]

  @impl Hardware.Component
  def dimensions(), do: {50, 25}

  @impl Hardware.Component
  def handle_event(state, :set_progress, v) when is_number(v) and v >= 0 and v <= 100 do
    {:ok, %{state | progress: v}}
  end

  @impl Hardware.Output
  def handle_transition(%__MODULE__{} = _old, %__MODULE__{} = new, _opts) do
    if bound?(new) do
      Link.send_command(new.module, Module2.set_gauge(new.gauge, duty(new)))
    end

    :ok
  end

  @spec duty(%__MODULE__{}) :: 0..255
  def duty(%__MODULE__{progress: p, duty_min: lo, duty_max: hi}), do: pct_to_duty(p, lo, hi)

  @spec pct_to_duty(number(), integer(), integer()) :: 0..255
  def pct_to_duty(pct, duty_min, duty_max) do
    (pct / 100 * (duty_max - duty_min) + duty_min)
    |> round()
    |> max(0)
    |> min(255)
  end

  defp bound?(%__MODULE__{module: m, gauge: g}), do: not is_nil(m) and not is_nil(g)

  defp attr(opts, key, default), do: Keyword.get(opts, key) || default
end
