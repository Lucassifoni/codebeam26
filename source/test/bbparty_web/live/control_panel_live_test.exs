defmodule BbpartyWeb.ControlPanelLiveTest do
  use BbpartyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bbparty.Layout
  alias Bbparty.RenderState
  alias BbpartyWeb.ControlPanelLive
  alias Hardware.Components.NeedleGauge
  alias Hardware.Components.PushButton
  alias Hardware.Components.Renderer
  alias Hardware.PhysicalComponent

  setup do
    on_exit(fn ->
      Enum.each([:key_1_2, :key_3_4, :screen], &PhysicalComponent.stop/1)
    end)

    :ok
  end

  defp select(view, id) do
    render_click(view, "toggle_select", %{"id" => id})
    view
  end

  defp selected_count(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#canvas [data-selected]")
    |> Enum.count()
  end

  defp reassign(view, id, new_id) do
    render_submit(element(view, "form[phx-submit=rename_component]"), %{
      "component_id" => id,
      "new_id" => new_id
    })
  end

  describe "GET /" do
    test "serves the control panel's disconnected render", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ "Add component"
      assert html =~ "Components"
    end
  end

  describe "get_modules/0" do
    test "offers every module declaring Hardware.Component" do
      modules = ControlPanelLive.get_modules()

      assert Map.has_key?(modules, PushButton)
      assert modules[PushButton] == PushButton.editable_fields()
    end

    test "a second @behaviour does not hide a component" do
      behaviours =
        NeedleGauge.__info__(:attributes) |> Keyword.get_values(:behaviour) |> List.flatten()

      assert length(behaviours) > 1
      assert Map.has_key?(ControlPanelLive.get_modules(), NeedleGauge)
    end

    test "offers nothing that is not a component" do
      assert Enum.all?(Map.keys(ControlPanelLive.get_modules()), fn module ->
               module.__info__(:attributes)
               |> Keyword.get_values(:behaviour)
               |> List.flatten()
               |> Enum.member?(Hardware.Component)
             end)
    end
  end

  describe "a persisted component with no running process" do
    test "does not stop the panel from loading", %{conn: conn} do
      {:ok, _} = Layout.create_component(:key_1_2, PushButton, %{char: "a"})
      {:ok, _} = PhysicalComponent.start(:key_1_2, Layout.get_component(:key_1_2))
      {:ok, _} = Layout.create_component(:key_3_4, PushButton, %{char: "b"})

      {:ok, view, _html} = live(conn, "/")
      html = render(view)

      assert html =~ "key_1_2"
      assert html =~ "key_3_4", "the orphan row must stay visible to be deletable"
      assert html =~ "no process"
    end
  end

  describe "a key registering itself while the panel is open" do
    test "appears without a reload", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      refute render(view) =~ "key_1_2"

      {:ok, _} = Layout.create_component(:key_1_2, PushButton, %{char: "a"})
      {:ok, _} = PhysicalComponent.start(:key_1_2, Layout.get_component(:key_1_2))
      send(view.pid, {:component_registered, :key_1_2})

      assert render(view) =~ "key_1_2"
    end
  end

  describe "reassigning a component id" do
    setup do
      {:ok, _} = Layout.create_component(:key_1_2, PushButton, %{char: "a"})
      {:ok, _} = PhysicalComponent.start(:key_1_2, Layout.get_component(:key_1_2))
      :ok
    end

    test "moves the component and its running process", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view |> select("key_1_2") |> reassign("key_1_2", "key_3_4")

      assert [%{component_id: :key_3_4}] = Layout.list_components()
      assert PhysicalComponent.query_state(:key_3_4).char == "a"
      assert GenServer.whereis(PhysicalComponent.via(:key_1_2)) == nil
    end

    test "refuses an id the render graph names literally", %{conn: conn} do
      referenced = RenderState.referenced_ids() |> Enum.at(0)

      {:ok, view, _html} = live(conn, "/")
      html = view |> select("key_1_2") |> reassign("key_1_2", referenced)

      assert html =~ "wired into the render graph"
      assert [%{component_id: :key_1_2}] = Layout.list_components()
    end

    test "refuses an id that is already taken", %{conn: conn} do
      {:ok, _} = Layout.create_component(:key_3_4, PushButton)
      {:ok, _} = PhysicalComponent.start(:key_3_4, Layout.get_component(:key_3_4))

      {:ok, view, _html} = live(conn, "/")
      html = view |> select("key_1_2") |> reassign("key_1_2", "key_3_4")

      assert html =~ "already taken"

      assert Enum.map(Layout.list_components(), & &1.component_id) |> Enum.sort() ==
               [:key_1_2, :key_3_4]
    end
  end

  describe "int_or/2" do
    test "parses a typed coordinate" do
      assert ControlPanelLive.int_or("120", 7) == 120
      assert ControlPanelLive.int_or(" -40 ", 7) == -40
    end

    test "keeps the current coordinate when the field is blank or unparseable" do
      assert ControlPanelLive.int_or("", 7) == 7
      assert ControlPanelLive.int_or("abc", 7) == 7
    end
  end

  describe "selecting from the component list" do
    setup do
      for id <- [:key_1_2, :key_3_4] do
        {:ok, _} = Layout.create_component(id, PushButton, %{char: "a"})
        {:ok, _} = PhysicalComponent.start(id, Layout.get_component(id))
      end

      :ok
    end

    test "a plain click replaces the selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      refute has_element?(view, "#selection-panel")
      refute has_element?(view, "#selection-toolbar")

      view |> select("key_1_2") |> select("key_3_4")
      assert selected_count(view) == 2
      assert has_element?(view, "#selection-panel")
      assert has_element?(view, "#selection-toolbar")
      refute has_element?(view, "#inspector")

      render_click(view, "select_only", %{"id" => "key_1_2"})

      refute has_element?(view, "#selection-toolbar")

      assert selected_count(view) == 1
      assert has_element?(view, "#component-key_1_2[data-selected]")
      assert has_element?(view, "#inspector")
    end
  end

  describe "opening the inspector from the canvas" do
    setup do
      {:ok, _} = Layout.create_component(:key_1_2, PushButton, %{char: "a"})
      {:ok, _} = PhysicalComponent.start(:key_1_2, Layout.get_component(:key_1_2))
      :ok
    end

    test "is bound to the button beside the drag handle only", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      refute has_element?(view, "#component-key_1_2[phx-click]")
      refute has_element?(view, "#inspector")

      view
      |> element("#component-key_1_2 .inspect-button")
      |> render_click()

      assert has_element?(view, "#component-key_1_2[data-selected]")
      assert has_element?(view, "#inspector")
    end
  end

  describe "placing a component from the inspector" do
    setup do
      {:ok, _} = Layout.create_component(:key_1_2, PushButton, %{char: "a"})
      {:ok, _} = PhysicalComponent.start(:key_1_2, Layout.get_component(:key_1_2))
      :ok
    end

    defp place(view, params) do
      render_submit(element(view, "form[phx-submit=set_position]"), params)
    end

    test "moves it to the typed coordinates", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view
      |> select("key_1_2")
      |> place(%{"component_id" => "key_1_2", "x" => "120", "y" => "-40"})

      assert Layout.get_component(:key_1_2).position == %{"x" => 120, "y" => -40}
    end

    test "leaves an axis alone when its field is blank", %{conn: conn} do
      {:ok, _} = Layout.move_component("key_1_2", %{"x" => 10, "y" => 20})

      {:ok, view, _html} = live(conn, "/")

      view
      |> select("key_1_2")
      |> place(%{"component_id" => "key_1_2", "x" => "", "y" => "55"})

      assert Layout.get_component(:key_1_2).position == %{"x" => 10, "y" => 55}
    end
  end

  describe "a boolean attr in the inspector" do
    setup do
      {:ok, _} = Layout.create_component(:key_1_2, PushButton, %{char: "a"})
      {:ok, _} = PhysicalComponent.start(:key_1_2, Layout.get_component(:key_1_2))
      :ok
    end

    defp save(view, attrs) do
      render_submit(element(view, "#inspector-form"), %{
        "component_id" => "key_1_2",
        "attrs" => attrs
      })
    end

    test "renders as a checkbox rather than a text box", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      html = view |> select("key_1_2") |> render()

      assert html =~ ~s(type="checkbox")
      assert html =~ ~s(name="attrs[red]")
    end

    test "ticking it sets the attr, and the component sees it", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> select("key_1_2") |> save(%{"red" => "true", "char" => "a"})

      assert Layout.get_component(:key_1_2).attrs[:red] == true
      assert PhysicalComponent.query_state(:key_1_2).red == true
    end

    test "unticking it clears the attr", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      view |> select("key_1_2") |> save(%{"red" => "true", "char" => "a"})
      view |> save(%{"red" => "false", "char" => "a"})

      assert Layout.get_component(:key_1_2).attrs[:red] == false
      assert PhysicalComponent.query_state(:key_1_2).red == false
    end

    test "a text attr is still a text box", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      html = view |> select("key_1_2") |> render()

      assert html =~ ~s(name="attrs[char]")
      refute html =~ ~s(name="attrs[char]" value="a" type="checkbox")
    end
  end

  describe "visible_components/2" do
    setup do
      for {id, mod} <- [key_1_2: PushButton, key_3_4: PushButton, main_gauge: NeedleGauge] do
        {:ok, _} = Layout.create_component(id, mod)
      end

      %{components: Layout.list_components()}
    end

    test "orders by id and keeps everything when unfiltered", %{components: components} do
      assert Enum.map(ControlPanelLive.visible_components(components, ""), & &1.component_id) ==
               [:key_1_2, :key_3_4, :main_gauge]
    end

    test "matches on id, case-insensitively", %{components: components} do
      assert Enum.map(
               ControlPanelLive.visible_components(components, " KEY_3 "),
               & &1.component_id
             ) ==
               [:key_3_4]
    end

    test "matches on module name", %{components: components} do
      assert Enum.map(
               ControlPanelLive.visible_components(components, "needle"),
               & &1.component_id
             ) ==
               [:main_gauge]
    end

    test "returns nothing when no component matches", %{components: components} do
      assert ControlPanelLive.visible_components(components, "zzz") == []
    end
  end

  describe "a burst of hardware state updates" do
    setup do
      {:ok, _} = Layout.create_component(:main_gauge, NeedleGauge)
      {:ok, _} = PhysicalComponent.start(:main_gauge, Layout.get_component(:main_gauge))
      on_exit(fn -> PhysicalComponent.stop(:main_gauge) end)
      :ok
    end

    defp gauge_at(progress),
      do: {:component_changed, :main_gauge, %NeedleGauge{progress: progress}}

    test "the first change is applied at once", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      send(view.pid, gauge_at(100))

      assert render(view) =~ "rotate(60.0deg)"
    end

    test "the ones behind it wait for the window to close", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      send(view.pid, gauge_at(100))
      send(view.pid, gauge_at(50))
      send(view.pid, gauge_at(0))

      html = render(view)
      assert html =~ "rotate(60.0deg)", "the leading edge must land immediately"
      refute html =~ "rotate(-60.0deg)"

      Process.sleep(200)

      assert render(view) =~ "rotate(-60.0deg)", "the last staged state must land on flush"
    end

    test "only the last state per component survives the window", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      send(view.pid, gauge_at(100))
      for progress <- [10, 20, 30, 40, 50], do: send(view.pid, gauge_at(progress))
      _ = render(view)

      Process.sleep(200)
      html = render(view)

      assert html =~ "rotate(0.0deg)"
      refute html =~ "rotate(-48.0deg)", "an intermediate sample must not be rendered"
    end
  end

  describe "the inspector's assigns" do
    setup do
      {:ok, _} = Layout.create_component(:key_1_2, PushButton, %{char: "a"})
      {:ok, _} = PhysicalComponent.start(:key_1_2, Layout.get_component(:key_1_2))
      :ok
    end

    defp socket_assigns(view), do: :sys.get_state(view.pid).socket.assigns

    test "are derived when the selection changes, not while rendering", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert socket_assigns(view).inspected == nil
      assert socket_assigns(view).selected_count == 0

      select(view, "key_1_2")

      assert socket_assigns(view).inspected.component_id == :key_1_2
      assert socket_assigns(view).selected_count == 1
    end

    test "are left alone by hardware traffic", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      select(view, "key_1_2")
      inspected = socket_assigns(view).inspected

      send(view.pid, {:component_changed, :key_1_2, %PushButton{char: "a", pushed: true}})
      html = render(view)

      assert socket_assigns(view).inspected == inspected
      assert html =~ ~s(value="a"), "the form must still offer the stored attrs"
    end
  end

  describe "dropping the selection" do
    setup do
      for id <- [:key_1_2, :key_3_4] do
        {:ok, _} = Layout.create_component(id, PushButton, %{char: "a"})
        {:ok, _} = PhysicalComponent.start(id, Layout.get_component(id))
      end

      :ok
    end

    test "escape is bound to it at the window", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ ~s(phx-window-keyup="clear_selection")
      assert html =~ ~s(phx-key="Escape")
    end

    test "clears every selected component", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")
      view |> select("key_1_2") |> select("key_3_4")
      assert selected_count(view) == 2

      render_keyup(view, "clear_selection", %{"key" => "Escape"})
      assert selected_count(view) == 0
      refute has_element?(view, "#selection-panel")
    end
  end

  describe "a renderer component" do
    test "embeds the render page in mirror mode", %{conn: conn} do
      {:ok, _} = Layout.create_component(:screen, Renderer, %{})
      {:ok, _} = PhysicalComponent.start(:screen, Layout.get_component(:screen))

      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, ~s(#renderer-screen iframe[src="/render?mirror"]))
    end
  end
end
