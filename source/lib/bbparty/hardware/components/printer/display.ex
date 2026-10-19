defmodule Hardware.Components.Printer.Display do
  use Phoenix.Component

  alias Bbparty.Print.Preview

  def render(assigns) do
    assigns = assign(assigns, %{preview: Preview.last(), src: Preview.last_data_uri()})

    ~H"""
    <div class="flex h-full w-full flex-col overflow-hidden bg-neutral-900 p-1">
      <img
        :if={@src}
        src={@src}
        alt="last sticker"
        class="min-h-0 w-full flex-1 object-contain"
      />
      <div :if={!@src} class="flex flex-1 items-center justify-center text-[9px] text-neutral-500">
        no sticker yet
      </div>
      <div :if={@preview} class="shrink-0 text-center text-[8px] leading-tight text-neutral-400">
        {@preview.width}×{@preview.height}
        <span class={if @preview.printed?, do: "text-emerald-400", else: "text-amber-400"}>
          {if @preview.printed?, do: "printed", else: "preview"}
        </span>
      </div>
    </div>
    """
  end
end
