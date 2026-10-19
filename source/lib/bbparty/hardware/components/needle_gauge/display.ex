defmodule Hardware.Components.NeedleGauge.Display do
  use Phoenix.Component

  defp compute_rotation(value) when is_number(value) do
    value / 100 * 120 + -60
  end

  defp compute_rotation(_), do: -60

  attr :attrs, :any
  attr :data, :any

  def render(assigns) do
    ~H"""
    <div class="w-48 h-24 bg-blue-300 relative">
      <div
        class="needle w-[2px] bg-red-500 h-[80px] left-[50%] top-[10px] absolute origin-bottom"
        style={"transform: rotate(#{compute_rotation(@data.progress)}deg)"}
      >
      </div>
    </div>
    """
  end
end
