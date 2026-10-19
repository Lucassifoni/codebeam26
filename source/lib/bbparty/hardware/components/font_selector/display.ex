defmodule Hardware.Components.FontSelector.Display do
  use Phoenix.Component

  attr :id, :any, required: true
  attr :attrs, :any, default: %{}
  attr :data, :any, required: true

  def render(assigns) do
    ~H"""
    <div class="flex h-full w-full flex-col overflow-hidden bg-slate-100">
      <div class="shrink-0 px-1 py-0.5 text-[8px] font-semibold tracking-wide text-slate-500 uppercase">
        font
      </div>
      <div class="min-h-0 flex-1 overflow-y-auto">
        <button
          :for={id <- Bbparty.FontMap.ids()}
          type="button"
          phx-click="component_input"
          phx-value-event="select_font"
          phx-value-id={@id}
          phx-value-payload={if @data.selected_font == id, do: "", else: id}
          style={"font-family: '#{Bbparty.FontMap.family_for_font(id)}', sans-serif"}
          class={[
            "block w-full truncate px-1 text-left text-[10px] leading-tight",
            if(@data.selected_font == id, do: "bg-yellow-200 font-semibold", else: "hover:bg-white")
          ]}
        >
          Aa {id}
        </button>
      </div>
    </div>
    """
  end
end
