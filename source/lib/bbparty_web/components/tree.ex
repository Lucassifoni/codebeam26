defmodule BbpartyWeb.Components.Tree do
  use Phoenix.Component

  attr :node, :any
  attr :cache, :map

  def render_tree(assigns) do
    {type, id, children, module, attrs} = assigns.node

    apply(__MODULE__, :"render_#{type}", [
      %{id: id, children: children, module: module, attrs: attrs, cache: assigns.cache}
    ])
  end

  attr :id, :any
  attr :children, :any
  attr :attrs, :any
  attr :cache, :map

  def render_block(assigns) do
    ~H"""
    <div class="p-2">
      <.render_tree :for={child <- @children} node={child} cache={@cache} />
    </div>
    """
  end

  attr :id, :any
  attr :children, :any
  attr :attrs, :any
  attr :module, :any
  attr :cache, :map

  def render_component(assigns) do
    ~H"""
    <div class="relative">
      <div class="text-[9px] absolute -top-2 left-2">
        {@id} / {String.replace("#{@module}", "Elixir.Hardware.Components.", "")}
      </div>
      <div class="m-2 border border-black min-w-10 min-h-10">
        {apply(:"#{@module}.Display", :render, [%{id: @id, attrs: @attrs, data: @cache[@id]}])}
      </div>
    </div>
    """
  end

  attr :id, :any
  attr :children, :any
  attr :attrs, :any
  attr :cache, :map

  def render_cols(assigns) do
    ~H"""
    <div class="flex flex-wrap justify-around w-full p-2">
      {@id}
      <.render_tree :for={child <- @children} node={child} cache={@cache} />
    </div>
    """
  end
end
