defmodule Hardware.Components.PushButton.Display do
  use Phoenix.Component

  attr :id, :any, required: true
  attr :attrs, :any, default: %{}
  attr :data, :any, required: true

  def render(assigns) do
    ~H"""
    <div
      id={@id}
      data-value={@data.char}
      phx-hook=".PushButton"
      class={[
        "relative flex h-full w-full items-center justify-center overflow-hidden",
        "rounded-[3px] border text-center select-none",
        cap_class(@data.red),
        @data.pushed && "translate-y-px shadow-inner"
      ]}
    >
      <span
        :if={present?(@data.shift)}
        class={["absolute top-0 left-0.5 text-[7px] leading-tight", shift_class(@data.red)]}
      >
        {@data.shift}
      </span>
      <span class={["truncate px-0.5 leading-tight font-medium", size_class(@data)]}>
        {label(@data)}
      </span>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".PushButton">
      export default {
        mounted() {
        let down = false;
          const cleanup = () => {
            document.removeEventListener("mouseup", cleanup);
            this.pushEvent("component_input", {id: this.el.id, event: "key_up", payload: this.el.dataset.value});
            down = false;
          };

          this.el.addEventListener("mousedown", (e) => {
            down = true;
            document.addEventListener("mouseup", cleanup);
            this.pushEvent("component_input", {id: this.el.id, event: "key_down", payload: this.el.dataset.value});
          });

          this._teardown = () => {
            cleanup();
            document.removeEventListener("mouseup", cleanup);
          };
        },
        destroyed() {
          this._teardown && this._teardown();
        }
      }
    </script>
    """
  end

  defp cap_class(true), do: "border-red-500 bg-red-400 text-white"
  defp cap_class(_black), do: "border-slate-400 bg-slate-200 text-slate-700"

  defp shift_class(true), do: "text-white/80"
  defp shift_class(_black), do: "text-slate-500"

  defp size_class(%{action: action}) when action not in [nil, "", "dead"], do: "text-[8px]"
  defp size_class(_glyph), do: "text-[13px]"

  defp label(%{action: "dead", char: char}), do: char
  defp label(%{action: action}) when action not in [nil, ""], do: spaced(action)
  defp label(%{char: char}) when char not in [nil, ""], do: char
  defp label(_unassigned), do: "—"

  defp spaced(action), do: action |> to_string() |> String.replace("_", " ")

  defp present?(value), do: value not in [nil, ""]
end
