defmodule Hardware.Components.Joystick.Display do
  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div class="w-50 relative">
      <div
        class="joystick w-[2px] bg-black h-[30px] left-[50%] top-[10px] absolute origin-bottom"
        phx-hook=".Joystick"
        id={@id}
      >
        <div class="handle w-4 h-4 rounded-full absolute top-0 -left-2 bg-black"></div>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Joystick">
        export default {
          mounted() {
            let down = false;
            let released = false;
            let initialX = 0;
            let currentX = 0;
            let pulser = null;
            let rafId = null;

            const RETURN_RATE = 0.18;
            const SETTLE_EPSILON = 0.5;
            const ANGLE_PER_UNIT = 0.6;

            const clamp = (v) => Math.max(-100, Math.min(100, v));

            const render = () => {
              const travel = clamp(currentX - initialX);
              this.el.style.transform = `rotate(${travel * ANGLE_PER_UNIT}deg)`;
            };

            const tick = () => {
              if (released) {
                currentX += (initialX - currentX) * RETURN_RATE;
                if (Math.abs(currentX - initialX) < SETTLE_EPSILON) {
                  currentX = 0;
                  initialX = 0;
                  released = false;
                  if (pulser) { clearInterval(pulser); pulser = null; }
                  render();
                  rafId = null;
                  return;
                }
              }
              render();
              rafId = requestAnimationFrame(tick);
            };

            const move = (e) => {
              if (!down) return;
              currentX = e.clientX;
            };

            const pulse = () => {
              const travel = clamp(currentX - initialX);
              this.pushEvent("component_input", {id: this.el.id, event: "deflect", payload: travel})
            };

            const cleanup = () => {
              document.removeEventListener("mouseup", cleanup);
              document.removeEventListener("mousemove", move);
              down = false;
              released = true;
            };

            this.el.addEventListener("mousedown", (e) => {
              down = true;
              released = false;
              initialX = e.clientX;
              currentX = e.clientX;
              if (!pulser) pulser = setInterval(pulse, 200);
              document.addEventListener("mouseup", cleanup);
              document.addEventListener("mousemove", move);
              if (rafId == null) rafId = requestAnimationFrame(tick);
            });

            this._teardown = () => {
              if (rafId != null) cancelAnimationFrame(rafId);
              if (pulser) clearInterval(pulser);
              document.removeEventListener("mouseup", cleanup);
              document.removeEventListener("mousemove", move);
            };
          },
          destroyed() {
            this._teardown && this._teardown();
          }
        }
      </script>
    </div>
    """
  end
end
