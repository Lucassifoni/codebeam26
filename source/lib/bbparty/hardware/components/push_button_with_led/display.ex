defmodule Hardware.Components.PushButtonWithLed.Display do
  use Phoenix.Component

  attr :id, :any, required: true
  attr :attrs, :any, default: %{}
  attr :data, :any, required: true

  def render(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook=".PushButtonWithLed"
      data-value={@data.action || @data.char}
      class={[
        "flex h-full w-full flex-col items-center justify-center gap-px overflow-hidden rounded-[3px] border text-center text-[9px] leading-tight font-medium select-none",
        lit_class(@data.lit),
        @data.pushed && "translate-y-px shadow-inner"
      ]}
    >
      <span class="truncate px-0.5">{label(@data)}</span>
      <span class={[
        "font-mono text-[7px] leading-none tabular-nums",
        channel_class(@data.led, @data.lit)
      ]}>
        {channel(@data.led)}
      </span>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".PushButtonWithLed">
      export default {
        mounted() {
          const press = (event) => {
            this.pushEvent("component_input", {id: this.el.id, event: event, payload: null})
          }

          this.el.addEventListener("mousedown", (e) => {
            e.preventDefault()
            press("key_down")
            const up = () => {
              document.removeEventListener("mouseup", up)
              press("key_up")
            }
            document.addEventListener("mouseup", up)
          })
        }
      }
    </script>
    """
  end

  defp lit_class(true),
    do: "border-amber-500 bg-amber-300 text-amber-950 shadow-[0_0_6px_rgba(251,191,36,0.8)]"

  defp lit_class(_dark), do: "border-slate-400 bg-slate-200 text-slate-600"

  defp channel(nil), do: "led ?"
  defp channel(led), do: "led #{led}"

  defp channel_class(nil, _lit), do: "text-red-600"
  defp channel_class(_led, true), do: "text-amber-800"
  defp channel_class(_led, _dark), do: "text-slate-500"

  defp label(%{action: nil, char: nil}), do: "—"
  defp label(%{action: nil, char: char}), do: char
  defp label(%{action: action}), do: action |> to_string() |> String.replace("_", " ")
end
