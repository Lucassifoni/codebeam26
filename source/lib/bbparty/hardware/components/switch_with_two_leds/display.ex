defmodule Hardware.Components.SwitchWithTwoLeds.Display do
  use Phoenix.Component

  attr :id, :any, required: true
  attr :attrs, :any, default: %{}
  attr :data, :any, required: true

  def render(assigns) do
    ~H"""
    <div
      phx-click="component_input"
      phx-value-id={@id}
      phx-value-event={edge(@data.position)}
      class="flex h-full w-full cursor-pointer flex-col items-center justify-between gap-px overflow-hidden rounded-[3px] border border-slate-400 bg-slate-100 px-0.5 py-px text-center text-[9px] leading-tight select-none"
    >
      <div class="flex w-full items-center justify-center gap-0.5">
        <span class={["h-2 w-2 rounded-full border", status_class(@data)]}></span>
        <span class={["h-2 w-2 rounded-full border", availability_class(@data)]}></span>
      </div>

      <span class="truncate font-medium text-slate-700">{label(@data)}</span>

      <div class={[
        "flex h-3 w-4 rounded-sm border border-slate-500 bg-slate-300",
        (@data.position && "items-end") || "items-start"
      ]}>
        <span class="h-1.5 w-full rounded-[1px] bg-slate-600"></span>
      </div>

      <span class={["font-mono text-[7px] leading-none tabular-nums", channels_class(@data)]}>
        {channels(@data)}
      </span>
    </div>
    """
  end

  defp edge(true), do: "key_up"
  defp edge(_down), do: "key_down"

  defp status_class(data) do
    case Hardware.Components.SwitchWithTwoLeds.status_lit?(data) do
      true -> "border-green-600 bg-green-400 shadow-[0_0_5px_rgba(74,222,128,0.9)]"
      false -> "border-slate-400 bg-green-900/20"
    end
  end

  defp availability_class(data) do
    case Hardware.Components.SwitchWithTwoLeds.availability_lit?(data) do
      true -> "border-red-600 bg-red-400 shadow-[0_0_5px_rgba(248,113,113,0.9)]"
      false -> "border-slate-400 bg-red-900/20"
    end
  end

  defp label(%{feature: nil}), do: "—"
  defp label(%{feature: feature, mode: :position}), do: "#{feature}="
  defp label(%{feature: feature}), do: feature

  defp channels(%{status_led: status, available_led: available}),
    do: "#{channel(status)}/#{channel(available)}"

  defp channel(nil), do: "?"
  defp channel(channel), do: to_string(channel)

  defp channels_class(%{module: nil}), do: "text-red-600"
  defp channels_class(%{status_led: nil}), do: "text-red-600"
  defp channels_class(%{available_led: nil}), do: "text-red-600"
  defp channels_class(_claimed), do: "text-slate-500"
end
