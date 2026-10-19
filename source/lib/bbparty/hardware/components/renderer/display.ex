defmodule Hardware.Components.Renderer.Display do
  use Phoenix.Component

  attr :id, :any, required: true
  attr :attrs, :any, default: %{}
  attr :data, :any, required: true

  def render(assigns) do
    ~H"""
    <div id={"renderer-#{@id}"} phx-update="ignore" class="h-full w-full overflow-hidden bg-black">
      <iframe
        src="/render?mirror"
        title="renderer"
        tabindex="-1"
        class="pointer-events-none h-full w-full border-0"
      >
      </iframe>
    </div>
    """
  end
end
