defmodule Hardware.Components.RotaryEncoder.Display do
  use Phoenix.Component

  @detents_per_turn 24

  attr :id, :any, required: true
  attr :attrs, :any, default: %{}
  attr :data, :any, required: true

  def render(assigns) do
    assigns = assign(assigns, :angle, angle(assigns.data.quantity))

    ~H"""
    <div
      id={@id}
      phx-hook=".Knob"
      data-id={@id}
      title="drag up to write the text character by character — shift for ten"
      class="flex h-full w-full cursor-ns-resize flex-col items-center justify-center gap-0.5 select-none"
    >
      <svg viewBox="0 0 40 40" class="h-full min-h-0 flex-1">
        <circle cx="20" cy="20" r="17" fill="#e2e8f0" stroke="#94a3b8" stroke-width="1.5" />
        <circle cx="20" cy="20" r="3" fill="#94a3b8" />
        <line
          x1="20"
          y1="20"
          x2="20"
          y2="6"
          stroke="#0f172a"
          stroke-width="2.5"
          stroke-linecap="round"
          transform={"rotate(#{@angle} 20 20)"}
        />
      </svg>
      <span class="text-[10px] leading-none font-medium tabular-nums text-slate-700">
        {@data.quantity}
      </span>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Knob">
      const PIXELS_PER_DETENT = 6

      export default {
        mounted() {
          const turn = (detents) => {
            if (detents === 0) return
            this.pushEvent("component_input", {id: this.el.dataset.id, event: "turn", payload: detents})
          }

          this.el.addEventListener("mousedown", (e) => {
            e.preventDefault()
            const startY = e.clientY
            const step = e.shiftKey ? 10 : 1
            let sent = 0

            const onMove = (ev) => {
              const detents = Math.trunc((startY - ev.clientY) / PIXELS_PER_DETENT)
              turn((detents - sent) * step)
              sent = detents
            }
            const onUp = () => {
              document.removeEventListener("mousemove", onMove)
              document.removeEventListener("mouseup", onUp)
            }

            document.addEventListener("mousemove", onMove)
            document.addEventListener("mouseup", onUp)
          })
        }
      }
    </script>
    """
  end

  defp angle(quantity) when is_integer(quantity),
    do: Integer.mod(quantity, @detents_per_turn) * (360 / @detents_per_turn)

  defp angle(_quantity), do: 0

  def detents_per_turn, do: @detents_per_turn
end
