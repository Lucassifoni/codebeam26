defmodule BbpartyWeb.ControlPanelLive do
  use BbpartyWeb, :live_view
  alias Hardware.PhysicalComponent
  alias Bbparty.Layout
  alias Bbparty.Layout.Arrange

  @grid_mm 10

  @state_flush_ms 100
  @staged_states :bbparty_staged_component_states
  @flush_timer :bbparty_component_state_flush_timer

  def mount(_, _, socket) do
    Phoenix.PubSub.subscribe(Bbparty.PubSub, "components")
    Bbparty.Print.Preview.subscribe()

    modules = get_modules()

    {:ok,
     socket
     |> assign(:components, Layout.list_components())
     |> assign(:available_modules, modules)
     |> assign(:add_module, modules |> Map.keys() |> List.first())
     |> assign(:selected, MapSet.new())
     |> assign(:rename_error, nil)
     |> assign(:sticker_version, 0)
     |> assign(:filter, "")
     |> assign(:component_state_cache, build_component_state_cache())
     |> put_private(@staged_states, %{})
     |> put_private(@flush_timer, nil)
     |> derive()}
  end

  def get_modules() do
    :code.all_available()
    |> Enum.map(fn {a, _, _} -> :"#{a}" end)
    |> Enum.filter(fn mod -> String.starts_with?("#{mod}", "Elixir.Hardware.Components.") end)
    |> Enum.filter(&component?/1)
    |> Enum.map(fn mod ->
      {mod, if(function_exported?(mod, :editable_fields, 0), do: mod.editable_fields(), else: [])}
    end)
    |> Enum.into(%{})
  end

  defp datalist_for(:action), do: "keyboard-actions"
  defp datalist_for(:feature), do: "font-features"
  defp datalist_for(:mode), do: "switch-modes"
  defp datalist_for(_field), do: false

  defp component?(module) do
    module.__info__(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
    |> Enum.member?(Hardware.Component)
  end

  def build_component_state_cache() do
    Layout.list_components()
    |> Enum.filter(fn %{component_id: id} -> PhysicalComponent.running?(id) end)
    |> Map.new(fn %{component_id: id} -> {id, PhysicalComponent.query_state(id)} end)
  end

  def int_or(value, fallback) do
    case Integer.parse(String.trim(to_string(value))) do
      {n, _} -> n
      :error -> fallback
    end
  end

  def visible_components(components, filter) do
    needle = filter |> to_string() |> String.trim() |> String.downcase()

    components
    |> Enum.filter(fn c ->
      needle == "" or String.contains?(String.downcase(to_string(c.component_id)), needle) or
        String.contains?(String.downcase(short_name(c.module)), needle)
    end)
    |> Enum.sort_by(fn c -> to_string(c.component_id) end)
  end

  def handle_event("filter", %{"q" => q}, socket) do
    {:noreply, socket |> assign(:filter, q) |> derive()}
  end

  def handle_event("select_add_module", %{"module" => mod}, socket) do
    {:noreply, assign(socket, :add_module, parse_module(mod))}
  end

  def handle_event("add_component", %{"component_id" => id, "module" => mod} = params, socket) do
    module = parse_module(mod)
    attrs = Map.get(params, "attrs", %{})

    case Layout.create_component(id, module, attrs) do
      {:ok, _} ->
        instance = Layout.get_component(id)
        PhysicalComponent.start(instance.component_id, instance)
        Bbparty.RenderStateServer.sync()
        {:noreply, reload(socket)}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_component", %{"id" => id}, socket) do
    PhysicalComponent.stop(id)
    Layout.delete_component(id)

    {:noreply,
     socket |> assign(:selected, MapSet.delete(socket.assigns.selected, id)) |> reload()}
  end

  def handle_event("update_component", %{"component_id" => id} = params, socket) do
    Enum.each(Map.get(params, "attrs", %{}), fn {key, value} ->
      Layout.set_component_attr(id, String.to_existing_atom(key), value)
    end)

    instance = Layout.get_component(id)
    PhysicalComponent.reconfigure(instance.component_id, instance)

    if PhysicalComponent.running?(instance.component_id) do
      PhysicalComponent.query_state(instance.component_id)
    end

    Enum.each(Map.keys(Bbparty.Bus.LedShadow.boards()), &Bbparty.Bus.LedShadow.blank/1)
    Bbparty.RenderStateServer.sync()
    {:noreply, reload(socket)}
  end

  def handle_event("rename_component", %{"component_id" => id, "new_id" => new_id}, socket) do
    case Layout.rename_component(id, new_id) do
      {:ok, _instance} ->
        PhysicalComponent.stop(id)
        instance = Layout.get_component(new_id)
        PhysicalComponent.start(instance.component_id, instance)

        {:noreply,
         socket
         |> assign(:selected, MapSet.new())
         |> assign(:rename_error, nil)
         |> reload()}

      {:error, reason} ->
        {:noreply, assign(socket, :rename_error, rename_error(reason))}
    end
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    selected = socket.assigns.selected

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, put_selection(socket, selected)}
  end

  def handle_event("select_only", %{"id" => id}, socket) do
    {:noreply, socket |> put_selection(MapSet.new([id])) |> assign(:rename_error, nil)}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, put_selection(socket, MapSet.new())}
  end

  def handle_event("move_component", %{"id" => id, "dx" => dx, "dy" => dy}, socket) do
    socket
    |> boxes_for(move_targets(socket, id))
    |> Arrange.translate(dx, dy)
    |> persist_positions()

    {:noreply, reload(socket)}
  end

  def handle_event("set_position", %{"component_id" => id, "x" => x, "y" => y}, socket) do
    current = Layout.get_component(id).position
    Layout.move_component(id, %{"x" => int_or(x, current["x"]), "y" => int_or(y, current["y"])})

    {:noreply, reload(socket)}
  end

  def handle_event("align", %{"edge" => edge}, socket) do
    socket
    |> boxes_for(socket.assigns.selected)
    |> Arrange.align(String.to_existing_atom(edge))
    |> persist_positions()

    {:noreply, reload(socket)}
  end

  def handle_event("distribute", %{"axis" => axis}, socket) do
    socket
    |> boxes_for(socket.assigns.selected)
    |> Arrange.distribute(String.to_existing_atom(axis))
    |> persist_positions()

    {:noreply, reload(socket)}
  end

  def handle_event("group", _params, socket) do
    Layout.set_group(MapSet.to_list(socket.assigns.selected), new_group_id())
    {:noreply, reload(socket)}
  end

  def handle_event("ungroup", _params, socket) do
    Layout.set_group(MapSet.to_list(socket.assigns.selected), nil)
    {:noreply, reload(socket)}
  end

  def handle_event("move_group", %{"group_id" => gid, "dx" => dx, "dy" => dy}, socket) do
    socket
    |> boxes_for_group(gid)
    |> Arrange.translate(dx, dy)
    |> persist_positions()

    {:noreply, reload(socket)}
  end

  def handle_event("component_input", %{"id" => id, "event" => event} = params, socket) do
    PhysicalComponent.handle_event(
      id,
      String.to_existing_atom(event),
      Map.get(params, "payload", nil)
    )

    {:noreply, socket}
  end

  def handle_info({:component_changed, id, new_state}, socket) do
    {:noreply, socket |> stage_component_state(atom(id), new_state) |> flush_component_states()}
  end

  def handle_info(:flush_component_states, socket) do
    {:noreply, socket |> put_private(@flush_timer, nil) |> flush_component_states()}
  end

  def handle_info({:component_registered, _id}, socket) do
    {:noreply, reload(socket)}
  end

  def handle_info(:layout_moved, socket) do
    {:noreply, reload(socket)}
  end

  def handle_info({:sticker_preview, _entry}, socket) do
    {:noreply, update(socket, :sticker_version, &(&1 + 1))}
  end

  defp reload(socket) do
    socket
    |> assign(:components, Layout.list_components())
    |> assign(:component_state_cache, build_component_state_cache())
    |> derive()
  end

  defp put_selection(socket, selected), do: socket |> assign(:selected, selected) |> derive()

  defp derive(socket) do
    %{components: components, selected: selected, filter: filter} = socket.assigns

    socket
    |> assign(:inspected, selected_one(components, selected))
    |> assign(:selected_count, MapSet.size(selected))
    |> assign(:listed, visible_components(components, filter))
  end

  defp stage_component_state(socket, id, new_state) do
    put_private(socket, @staged_states, Map.put(socket.private[@staged_states], id, new_state))
  end

  defp flush_component_states(
         %{private: %{@flush_timer => nil, @staged_states => staged}} = socket
       )
       when map_size(staged) > 0 do
    socket
    |> assign(
      :component_state_cache,
      Map.merge(socket.assigns.component_state_cache, staged)
    )
    |> put_private(@staged_states, %{})
    |> put_private(
      @flush_timer,
      Process.send_after(self(), :flush_component_states, @state_flush_ms)
    )
  end

  defp flush_component_states(socket), do: socket

  defp move_targets(socket, id) do
    if MapSet.member?(socket.assigns.selected, id),
      do: socket.assigns.selected,
      else: MapSet.new([id])
  end

  defp boxes_for(socket, ids) do
    socket.assigns.components
    |> Enum.filter(fn c -> MapSet.member?(ids, to_string(c.component_id)) end)
    |> Map.new(fn c -> {to_string(c.component_id), box(c)} end)
  end

  defp boxes_for_group(socket, gid) do
    socket.assigns.components
    |> Enum.filter(fn c -> c.group_id == gid end)
    |> Map.new(fn c -> {to_string(c.component_id), box(c)} end)
  end

  defp box(component) do
    {w, h} = px_dimensions(component)
    %{x: component.position["x"], y: component.position["y"], w: w, h: h}
  end

  defp px_dimensions(component) do
    {w_mm, h_mm} = Hardware.Component.dimensions(component.module)
    {Hardware.Component.mm_to_px(w_mm), Hardware.Component.mm_to_px(h_mm)}
  end

  defp groups(components) do
    components
    |> Enum.reject(fn c -> is_nil(c.group_id) end)
    |> Enum.group_by(fn c -> c.group_id end)
    |> Enum.map(fn {gid, members} -> {gid, group_box(members)} end)
  end

  defp group_box(members) do
    pad = 6
    boxes = Enum.map(members, &box/1)
    minx = boxes |> Enum.map(& &1.x) |> Enum.min()
    miny = boxes |> Enum.map(& &1.y) |> Enum.min()
    maxx = boxes |> Enum.map(&(&1.x + &1.w)) |> Enum.max()
    maxy = boxes |> Enum.map(&(&1.y + &1.h)) |> Enum.max()

    %{x: minx - pad, y: miny - pad, w: maxx - minx + 2 * pad, h: maxy - miny + 2 * pad}
  end

  defp persist_positions(boxes) do
    Enum.each(boxes, fn {id, b} ->
      Layout.move_component(id, %{"x" => round(b.x), "y" => round(b.y)})
    end)
  end

  defp new_group_id(), do: to_string(System.unique_integer([:positive]))

  defp parse_module(mod), do: String.to_existing_atom(mod)

  defp short_name(mod), do: String.replace("#{mod}", "Elixir.Hardware.Components.", "")

  defp selected?(socket_selected, component),
    do: to_string(component.component_id) in socket_selected

  defp selected_one(components, selected) do
    case MapSet.to_list(selected) do
      [id] -> Enum.find(components, fn c -> to_string(c.component_id) == id end)
      _ -> nil
    end
  end

  defp component_style(component) do
    {w, h} = px_dimensions(component)

    "left: #{component.position["x"]}px; top: #{component.position["y"]}px; " <>
      "width: #{round(w)}px; height: #{round(h)}px"
  end

  attr :field, :atom, required: true
  attr :type, :atom, required: true
  attr :value, :any, default: nil

  defp attr_field(%{type: :boolean} = assigns) do
    ~H"""
    <label class="flex items-center gap-2 text-xs">
      <input type="hidden" name={"attrs[#{@field}]"} value="false" />
      <input
        type="checkbox"
        name={"attrs[#{@field}]"}
        value="true"
        checked={@value == true}
        class="size-3.5 appearance-none rounded-none border border-black bg-white checked:bg-black focus:ring-0 focus:ring-offset-0"
      />
      {@field}
    </label>
    """
  end

  defp attr_field(assigns) do
    ~H"""
    <label class="block text-xs">
      {@field}
      <input
        type="text"
        name={"attrs[#{@field}]"}
        value={@value}
        list={datalist_for(@field)}
        class={["mt-0.5", input_class()]}
      />
    </label>
    """
  end

  defp input_class(),
    do:
      "w-full rounded-none border border-black bg-white px-2 py-1 text-xs text-black " <>
        "placeholder:text-black/40 focus:border-black focus:outline-2 focus:outline-black focus:ring-0"

  defp primary_button_class(),
    do:
      "w-full rounded-none border border-black bg-black px-2 py-1 text-xs font-medium text-white " <>
        "hover:bg-white hover:text-black"

  defp secondary_button_class(),
    do:
      "rounded-none border border-black bg-white px-2 py-1 text-xs text-black " <>
        "hover:bg-black hover:text-white"

  defp box_class(true), do: "bg-white ring-2 ring-black ring-offset-2 ring-offset-white z-10"
  defp box_class(false), do: "bg-white ring-1 ring-black"

  attr :module, :atom, required: true
  attr :id, :any, required: true
  attr :attrs, :any, required: true
  attr :data, :any, required: true
  attr :revision, :integer, required: true

  defp display(assigns) do
    {module, assigns} = Map.pop(assigns, :module)

    case assigns.data do
      nil -> orphan(assigns)
      _data -> apply(:"#{module}.Display", :render, [assigns])
    end
  end

  defp orphan(assigns) do
    ~H"""
    <div
      title="no running process"
      class="flex h-full w-full items-center justify-center text-center text-[9px] leading-tight font-medium text-black"
      style="background: repeating-linear-gradient(45deg, #000 0 1px, #fff 1px 6px)"
    >
      <span class="bg-white px-0.5">no process</span>
    </div>
    """
  end

  defp rename_error(:referenced_by_graph),
    do: "that id is wired into the render graph by name — renaming it would break its projection"

  defp rename_error(:not_found), do: "no such component"
  defp rename_error(%Ecto.Changeset{}), do: "that id is already taken"

  defp atom(a) when is_atom(a), do: a
  defp atom(b), do: String.to_existing_atom(b)

  defp grid_px(), do: Hardware.Component.mm_to_px(@grid_mm)

  defp align_edges(:horizontal),
    do: [
      {:left, "L", "align left edges"},
      {:hcenter, "C", "align horizontal centres"},
      {:right, "R", "align right edges"}
    ]

  defp align_edges(:vertical),
    do: [
      {:top, "T", "align top edges"},
      {:vcenter, "M", "align vertical centres"},
      {:bottom, "B", "align bottom edges"}
    ]

  attr :rest, :global, include: ~w(disabled)
  slot :inner_block, required: true

  defp tool_button(assigns) do
    ~H"""
    <button
      type="button"
      class="shrink-0 rounded-none border border-black bg-white px-2 py-1 text-xs whitespace-nowrap text-black hover:bg-black hover:text-white disabled:pointer-events-none disabled:opacity-30"
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :rest, :global, include: ~w(disabled)
  slot :inner_block, required: true

  defp segment_button(assigns) do
    ~H"""
    <button
      type="button"
      class="w-7 shrink-0 bg-white py-1 text-xs text-black hover:bg-black hover:text-white disabled:pointer-events-none disabled:opacity-30"
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :title, :string, default: nil
  attr :count, :any, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  defp panel(assigns) do
    ~H"""
    <section class="border-b border-black p-3" {@rest}>
      <h2 :if={@title} class="mb-2 flex items-baseline justify-between text-sm font-semibold">
        {@title}
        <span :if={@count} class="text-xs font-normal tabular-nums">{@count}</span>
      </h2>
      {render_slot(@inner_block)}
    </section>
    """
  end

  def render(assigns) do
    ~H"""
    <div
      class="flex h-screen flex-col bg-white text-black"
      phx-window-keyup="clear_selection"
      phx-key="Escape"
    >
      <div class="flex min-h-0 flex-1">
        <aside class="flex w-64 shrink-0 flex-col overflow-y-auto border-r border-black bg-white">
          <.panel title="Components" count={length(@components)}>
            <form phx-change="filter" class="mb-2">
              <input
                type="text"
                name="q"
                value={@filter}
                placeholder="filter…"
                phx-debounce="150"
                class={input_class()}
              />
            </form>
            <p :if={@listed == []} class="text-xs">
              {if @components == [], do: "nothing placed yet", else: "no match"}
            </p>
            <ul class="-mx-1 max-h-[480px] overflow-y-scroll">
              <li
                :for={component <- @listed}
                class={[
                  "group flex items-center px-1 text-xs",
                  selected?(@selected, component) && "bg-black text-white"
                ]}
              >
                <button
                  type="button"
                  phx-click="select_only"
                  phx-value-id={component.component_id}
                  class="flex min-w-0 flex-1 items-baseline gap-1 py-1 text-left hover:underline"
                >
                  <span class="truncate font-medium">{component.component_id}</span>
                  <span class="truncate text-[10px] opacity-60">
                    {short_name(component.module)}
                  </span>
                </button>
                <span :if={component.group_id} class="ml-1 border border-current px-1 text-[10px]">
                  {component.group_id}
                </span>
                <button
                  type="button"
                  title="add to / remove from selection"
                  phx-click="toggle_select"
                  phx-value-id={component.component_id}
                  class="ml-1 px-1 opacity-0 group-hover:opacity-100 hover:underline"
                >
                  ±
                </button>
                <button
                  type="button"
                  title="delete"
                  phx-click="delete_component"
                  phx-value-id={component.component_id}
                  class="px-1 opacity-0 group-hover:opacity-100 hover:underline"
                >
                  ×
                </button>
              </li>
            </ul>
          </.panel>

          <.panel title="Add component">
            <form phx-change="select_add_module" class="mb-2">
              <select name="module" class={input_class()}>
                <option
                  :for={mod <- Enum.sort_by(Map.keys(@available_modules), &short_name/1)}
                  value={mod}
                  selected={mod == @add_module}
                >
                  {short_name(mod)}
                </option>
              </select>
            </form>

            <form phx-submit="add_component" id="add-form" class="space-y-2">
              <input type="hidden" name="module" value={@add_module} />
              <input
                type="text"
                name="component_id"
                placeholder="component_id"
                class={["font-mono", input_class()]}
              />
              <label :for={{field, _type} <- @available_modules[@add_module]} class="block text-xs">
                {field}
                <input type="text" name={"attrs[#{field}]"} class={["mt-0.5", input_class()]} />
              </label>
              <button type="submit" class={primary_button_class()}>add</button>
            </form>
          </.panel>
        </aside>

        <main class="flex min-w-0 flex-1 flex-col">
          <div
            :if={@selected_count > 1}
            id="selection-toolbar"
            class="flex h-10 shrink-0 items-center gap-2 overflow-x-auto border-b border-black bg-white px-3"
          >
            <div class="flex shrink-0 divide-x divide-black border border-black">
              <.segment_button
                :for={{edge, label, tip} <- align_edges(:horizontal)}
                title={tip}
                phx-click="align"
                phx-value-edge={edge}
              >
                {label}
              </.segment_button>
            </div>
            <div class="flex shrink-0 divide-x divide-black border border-black">
              <.segment_button
                :for={{edge, label, tip} <- align_edges(:vertical)}
                title={tip}
                phx-click="align"
                phx-value-edge={edge}
              >
                {label}
              </.segment_button>
            </div>

            <.tool_button
              :for={{axis, label} <- [horizontal: "distribute H", vertical: "distribute V"]}
              title="equalise gaps (needs 3+)"
              disabled={@selected_count < 3}
              phx-click="distribute"
              phx-value-axis={axis}
            >
              {label}
            </.tool_button>

            <span class="mx-1 h-5 w-px bg-black"></span>

            <.tool_button phx-click="group">group</.tool_button>
            <.tool_button phx-click="ungroup">ungroup</.tool_button>
            <.tool_button phx-click="clear_selection">
              clear
            </.tool_button>
          </div>

          <div
            id="canvas"
            phx-hook=".PanZoom"
            data-grid={grid_px()}
            class="relative flex-1 cursor-grab overflow-hidden bg-white active:cursor-grabbing"
            style="background-image:
              linear-gradient(to right, rgba(0,0,0,.06) 1px, transparent 1px),
              linear-gradient(to bottom, rgba(0,0,0,.06) 1px, transparent 1px),
              linear-gradient(to right, rgba(0,0,0,.16) 1px, transparent 1px),
              linear-gradient(to bottom, rgba(0,0,0,.16) 1px, transparent 1px)"
          >
            <div id="world" class="absolute top-0 left-0 origin-top-left select-none">
              <div class="pointer-events-none absolute -top-2 -left-2 size-4 border border-black">
              </div>

              <div
                :for={component <- @components}
                :key={component.component_id}
                id={"component-#{component.component_id}"}
                phx-hook=".Component"
                data-id={component.component_id}
                data-selected={selected?(@selected, component)}
                data-group-member={component.group_id}
                class={["group absolute", box_class(selected?(@selected, component))]}
                style={component_style(component)}
              >
                <div class="absolute -top-4 left-0 flex">
                  <span
                    class="drag-handle cursor-move bg-black px-1 text-[10px] leading-4 text-white"
                    title="drag to move"
                  >
                    ⠿
                  </span>
                  <button
                    type="button"
                    phx-click="select_only"
                    phx-value-id={component.component_id}
                    title="inspect (shift: add to / remove from selection)"
                    class="inspect-button border border-black bg-white px-1 text-[10px] leading-[14px] text-black hover:bg-black hover:text-white"
                  >
                    i
                  </button>
                </div>
                <button
                  type="button"
                  phx-click="delete_component"
                  phx-value-id={component.component_id}
                  title="delete"
                  class="absolute -top-4 right-0 border border-black bg-white px-1 text-[10px] leading-[14px] text-black opacity-0 group-hover:opacity-100 hover:bg-black hover:text-white"
                >
                  ×
                </button>
                <.display
                  module={component.module}
                  id={component.component_id}
                  attrs={component.attrs}
                  data={@component_state_cache[component.component_id]}
                  revision={@sticker_version}
                />
                <div class="pointer-events-none absolute top-full left-0 mt-1 flex items-baseline gap-1 border border-black bg-white px-1 text-[9px] leading-tight whitespace-nowrap text-black">
                  <span class="font-semibold">{component.component_id}</span>
                  <span>{short_name(component.module)}</span>
                  <span :if={component.group_id} class="italic">{component.group_id}</span>
                </div>
              </div>

              <div
                :for={{gid, gb} <- groups(@components)}
                id={"group-#{gid}"}
                class="pointer-events-none absolute border border-dashed border-black"
                style={"left: #{gb.x}px; top: #{gb.y}px; width: #{gb.w}px; height: #{gb.h}px"}
              >
                <span
                  class="group-handle pointer-events-auto absolute -top-4 left-0 cursor-move bg-black px-1 text-[10px] leading-4 text-white"
                  id={"group-handle-#{gid}"}
                  phx-hook=".GroupDrag"
                  data-group={gid}
                >
                  ⠿ {gid}
                </span>
              </div>
            </div>

            <div class="hidden canvas-ui absolute bottom-3 left-3 flex items-stretch divide-x divide-black border border-black bg-white text-xs">
              <button type="button" id="zoom-out" class="w-7 py-1 hover:bg-black hover:text-white">
                −
              </button>
              <span id="zoom-level" class="w-12 py-1 text-center tabular-nums">100%</span>
              <button type="button" id="zoom-in" class="w-7 py-1 hover:bg-black hover:text-white">
                +
              </button>
              <button type="button" id="zoom-fit" class="px-2 py-1 hover:bg-black hover:text-white">
                fit
              </button>
              <button type="button" id="zoom-reset" class="px-2 py-1 hover:bg-black hover:text-white">
                1:1
              </button>
            </div>
          </div>
        </main>

        <aside
          :if={@selected_count > 0}
          id="selection-panel"
          class="w-72 shrink-0 overflow-y-auto border-l border-black bg-white"
        >
          <p :if={is_nil(@inspected)} id="selection-hint" class="p-3 text-xs">
            {@selected_count} selected.
          </p>

          <div :if={@inspected} id="inspector">
            <.panel>
              <form phx-submit="rename_component" id="rename-form" class="flex gap-2">
                <input type="hidden" name="component_id" value={@inspected.component_id} />
                <input
                  type="text"
                  name="new_id"
                  value={@inspected.component_id}
                  aria-label="component id"
                  class={["font-mono font-semibold", input_class()]}
                />
                <button type="submit" class={["shrink-0", secondary_button_class()]}>
                  rename
                </button>
              </form>
              <p class="mt-1 font-mono text-[11px]">{short_name(@inspected.module)}</p>
              <p :if={@rename_error} class="mt-2 bg-black p-2 text-[11px] leading-snug text-white">
                {@rename_error}
              </p>
            </.panel>

            <.panel>
              <form phx-submit="set_position" id="position-form" class="flex items-end gap-2">
                <input type="hidden" name="component_id" value={@inspected.component_id} />
                <label class="flex-1 text-xs">
                  x
                  <input
                    type="number"
                    name="x"
                    value={@inspected.position["x"]}
                    class={["mt-0.5", input_class()]}
                  />
                </label>
                <label class="flex-1 text-xs">
                  y
                  <input
                    type="number"
                    name="y"
                    value={@inspected.position["y"]}
                    class={["mt-0.5", input_class()]}
                  />
                </label>
                <button type="submit" class={["shrink-0", secondary_button_class()]}>place</button>
              </form>
            </.panel>

            <.panel :if={@available_modules[@inspected.module] != []}>
              <form phx-submit="update_component" id="inspector-form" class="space-y-2">
                <input type="hidden" name="component_id" value={@inspected.component_id} />
                <.attr_field
                  :for={{field, type} <- @available_modules[@inspected.module]}
                  field={field}
                  type={type}
                  value={@inspected.attrs[field]}
                />
                <datalist id="keyboard-actions">
                  <option :for={action <- Bbparty.Keyboard.Action.all()} value={action}></option>
                </datalist>
                <datalist id="font-features">
                  <option :for={feature <- Bbparty.FontMap.all_features()} value={feature}></option>
                </datalist>
                <datalist id="switch-modes">
                  <option
                    :for={mode <- Hardware.Components.SwitchWithTwoLeds.modes()}
                    value={mode}
                  >
                  </option>
                </datalist>
                <button type="submit" class={primary_button_class()}>save</button>
              </form>
            </.panel>
          </div>
        </aside>
      </div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Component">
      export default {
        mounted() {
          const box = this.el
          const id = box.dataset.id
          const handle = box.querySelector(".drag-handle")
          const inspect = box.querySelector(".inspect-button")
          const world = box.closest("#world")
          const scaleNow = () => (world ? new DOMMatrixReadOnly(getComputedStyle(world).transform).a || 1 : 1)

          inspect.addEventListener("click", (e) => {
            if (!e.shiftKey) return
            e.preventDefault()
            e.stopPropagation()
            this.pushEvent("toggle_select", {id: id})
          })

          handle.addEventListener("mousedown", (e) => {
            if (e.shiftKey) return
            e.preventDefault()
            const selected = box.hasAttribute("data-selected")
            const targets = selected ? Array.from(document.querySelectorAll("[data-selected]")) : [box]
            const startX = e.clientX, startY = e.clientY
            const origins = targets.map((t) => ({el: t, x: parseInt(t.style.left) || 0, y: parseInt(t.style.top) || 0}))
            const onMove = (ev) => {
              const s = scaleNow()
              const dx = (ev.clientX - startX) / s, dy = (ev.clientY - startY) / s
              origins.forEach((o) => { o.el.style.left = (o.x + dx) + "px"; o.el.style.top = (o.y + dy) + "px" })
              this._delta = {dx: dx, dy: dy}
            }
            const onUp = () => {
              document.removeEventListener("mousemove", onMove)
              document.removeEventListener("mouseup", onUp)
              if (this._delta) {
                this.pushEvent("move_component", {id: id, dx: this._delta.dx, dy: this._delta.dy})
                this._delta = null
              }
            }
            document.addEventListener("mousemove", onMove)
            document.addEventListener("mouseup", onUp)
          })
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".GroupDrag">
      export default {
        mounted() {
          const handle = this.el
          const gid = handle.dataset.group
          const world = handle.closest("#world")
          const scaleNow = () => (world ? new DOMMatrixReadOnly(getComputedStyle(world).transform).a || 1 : 1)
          handle.addEventListener("mousedown", (e) => {
            e.preventDefault()
            const members = Array.from(document.querySelectorAll(`[data-group-member="${gid}"]`))
            const groupBox = document.getElementById("group-" + gid)
            const movers = groupBox ? members.concat([groupBox]) : members
            const startX = e.clientX, startY = e.clientY
            const origins = movers.map((t) => ({el: t, x: parseInt(t.style.left) || 0, y: parseInt(t.style.top) || 0}))
            const onMove = (ev) => {
              const s = scaleNow()
              const dx = (ev.clientX - startX) / s, dy = (ev.clientY - startY) / s
              origins.forEach((o) => { o.el.style.left = (o.x + dx) + "px"; o.el.style.top = (o.y + dy) + "px" })
              this._delta = {dx: dx, dy: dy}
            }
            const onUp = () => {
              document.removeEventListener("mousemove", onMove)
              document.removeEventListener("mouseup", onUp)
              if (this._delta) {
                this.pushEvent("move_group", {group_id: gid, dx: this._delta.dx, dy: this._delta.dy})
                this._delta = null
              }
            }
            document.addEventListener("mousemove", onMove)
            document.addEventListener("mouseup", onUp)
          })
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".PanZoom">
      export default {
        mounted() {
          const MARGIN = 32
          this.x = MARGIN
          this.y = MARGIN
          this.z = 1
          const canvas = this.el
          const grid = parseFloat(canvas.dataset.grid) || 32
          const label = canvas.querySelector("#zoom-level")
          const clampZoom = (z) => Math.min(4, Math.max(0.2, z))

          this.apply = () => {
            const world = canvas.querySelector("#world")
            if (world) world.style.transform = `translate(${this.x}px, ${this.y}px) scale(${this.z})`
            const g = grid * this.z
            canvas.style.backgroundSize = `${g}px ${g}px, ${g}px ${g}px, ${g * 5}px ${g * 5}px, ${g * 5}px ${g * 5}px`
            canvas.style.backgroundPosition = `${this.x}px ${this.y}px`
            if (label) label.textContent = Math.round(this.z * 100) + "%"
          }
          this.apply()

          this.zoomAt = (z2, cx, cy) => {
            z2 = clampZoom(z2)
            this.x = cx - (cx - this.x) * (z2 / this.z)
            this.y = cy - (cy - this.y) * (z2 / this.z)
            this.z = z2
            this.apply()
          }

          this.reset = () => { this.x = MARGIN; this.y = MARGIN; this.z = 1; this.apply() }

          this.fit = () => {
            const boxes = Array.from(canvas.querySelectorAll("[data-id]"))
            if (!boxes.length) return this.reset()
            const minX = Math.min(...boxes.map((b) => b.offsetLeft))
            const minY = Math.min(...boxes.map((b) => b.offsetTop))
            const maxX = Math.max(...boxes.map((b) => b.offsetLeft + b.offsetWidth))
            const maxY = Math.max(...boxes.map((b) => b.offsetTop + b.offsetHeight))
            const pad = 48
            const rect = canvas.getBoundingClientRect()
            const w = Math.max(1, maxX - minX), h = Math.max(1, maxY - minY)
            this.z = clampZoom(Math.min((rect.width - 2 * pad) / w, (rect.height - 2 * pad) / h))
            this.x = (rect.width - w * this.z) / 2 - minX * this.z
            this.y = (rect.height - h * this.z) / 2 - minY * this.z
            this.apply()
          }

          const centre = () => {
            const rect = canvas.getBoundingClientRect()
            return [rect.width / 2, rect.height / 2]
          }

          canvas.querySelector("#zoom-in").addEventListener("click", () => this.zoomAt(this.z * 1.25, ...centre()))
          canvas.querySelector("#zoom-out").addEventListener("click", () => this.zoomAt(this.z / 1.25, ...centre()))
          canvas.querySelector("#zoom-reset").addEventListener("click", () => this.reset())
          canvas.querySelector("#zoom-fit").addEventListener("click", () => this.fit())

          canvas.addEventListener("wheel", (e) => {
            e.preventDefault()
            const rect = canvas.getBoundingClientRect()
            this.zoomAt(this.z * Math.exp(-e.deltaY * 0.0015), e.clientX - rect.left, e.clientY - rect.top)
          }, {passive: false})

          const onBackground = (e) => !e.target.closest("[data-id], .group-handle, .canvas-ui")

          canvas.addEventListener("mousedown", (e) => {
            if (!onBackground(e)) return
            e.preventDefault()
            this._panned = false
            const sx = e.clientX, sy = e.clientY, ox = this.x, oy = this.y
            const onMove = (ev) => {
              this._panned = true
              this.x = ox + (ev.clientX - sx)
              this.y = oy + (ev.clientY - sy)
              this.apply()
            }
            const onUp = () => {
              document.removeEventListener("mousemove", onMove)
              document.removeEventListener("mouseup", onUp)
            }
            document.addEventListener("mousemove", onMove)
            document.addEventListener("mouseup", onUp)
          })

          canvas.addEventListener("click", (e) => {
            if (onBackground(e) && !this._panned) this.pushEvent("clear_selection", {})
          })

          canvas.addEventListener("dblclick", (e) => {
            if (onBackground(e)) this.reset()
          })
        },
        updated() {
          this.apply && this.apply()
        }
      }
    </script>
    """
  end
end
