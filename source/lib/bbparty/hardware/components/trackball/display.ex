defmodule Hardware.Components.Trackball.Display do
  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div
      id={@id}
      data-rolls={@data.rolls}
      phx-hook=".Trackball"
      class="w-full h-full bg-black flex items-center justify-center cursor-pointer select-none"
      title={"#{@data.rolls} rolls, last intensity #{@data.intensity}"}
      phx-click="component_input"
      phx-value-id={@id}
      phx-value-event="spin"
    >
      <div
        data-die
        class="rounded-full w-3/4 h-3/4 bg-white text-6xl leading-none flex items-center justify-center"
      >
        <span class="block">🎲</span>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Trackball">
      export default {
        mounted() {
          this._rolls = this.el.dataset.rolls;
        },

        updated() {
          const rolls = this.el.dataset.rolls;
          if (rolls === this._rolls) return;
          this._rolls = rolls;
          this.flash();
        },

        flash() {
          const die = this.el.querySelector("[data-die]");
          if (!die || typeof die.animate !== "function") return;

          this._animation && this._animation.cancel();

          this._animation = die.animate(
            [
              {transform: "scale(1) rotate(0deg)", filter: "brightness(1)"},
              {transform: "scale(1.25) rotate(180deg)", filter: "brightness(1.9)"},
              {transform: "scale(1) rotate(360deg)", filter: "brightness(1)"}
            ],
            {duration: 450, easing: "cubic-bezier(.2,.8,.2,1)"}
          );
        },

        destroyed() {
          this._animation && this._animation.cancel();
        }
      }
    </script>
    """
  end
end
