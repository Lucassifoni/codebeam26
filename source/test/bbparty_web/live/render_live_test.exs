defmodule BbpartyWeb.RenderLiveTest do
  use BbpartyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bbparty.FontBundle
  alias Bbparty.Layout
  alias Bbparty.RenderState
  alias Bbparty.RenderState.Fit
  alias Bbparty.RenderState.TextLayout
  alias Bbparty.RenderStateServer
  alias Hardware.Components.{FontSelector, PushButton}
  alias Hardware.PhysicalComponent

  @keys [:render_live_test_char, :render_live_test_up]
  @reader :render_live_test_reader

  setup do
    reset = fn ->
      :sys.replace_state(RenderStateServer, fn _ ->
        %{render: RenderState.new(), layout: TextLayout.empty(), fit: Fit.empty()}
      end)
    end

    reset.()
    on_exit(fn -> Enum.each([@reader | @keys], &PhysicalComponent.stop/1) end)
    on_exit(reset)

    :ok
  end

  defp press(id, attrs) do
    {:ok, _} = Layout.create_component(id, PushButton, attrs)
    {:ok, _} = PhysicalComponent.start(id, Layout.get_component(id))
    PhysicalComponent.handle_event(id, :key_down, nil)

    PhysicalComponent.query_state(id)
    RenderStateServer.get_state()
  end

  defp present_tag(id) do
    {:ok, _} = Layout.create_component(@reader, FontSelector, %{module: 2})
    {:ok, _} = PhysicalComponent.start(@reader, Layout.get_component(@reader))
    PhysicalComponent.feed_input(@reader, :tag, id)

    PhysicalComponent.query_state(@reader)
    RenderStateServer.get_state()
  end

  defp stack(families),
    do:
      "font-family: " <>
        Enum.map_join(FontBundle.pinned_families() ++ families, ", ", &"&quot;#{&1}&quot;") <>
        ", sans-serif"

  defp unselected, do: stack([])

  describe "the font a tag chose" do
    test "is the family the page draws in", %{conn: conn} do
      {:ok, live, html} = live(conn, ~p"/render")
      assert html =~ unselected()

      present_tag("Chalkboard")

      assert render(live) =~ stack(["Chalkboard"])
    end

    test "an id nobody knows leaves the page as it was", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/render")

      present_tag("some-stranger's-transit-card")

      assert render(live) =~ unselected()
    end
  end

  describe "mirror mode" do
    test "the plain page is the measuring renderer", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/render")

      assert has_element?(live, ~s(#render-root[data-measure="true"]))
    end

    test "?mirror renders the same state without measuring", %{conn: conn} do
      {:ok, live, _html} = live(conn, "/render?mirror")

      assert has_element?(live, ~s(#render-root[data-measure="false"]))
    end

    test "only the mirror param opts out" do
      refute BbpartyWeb.RenderLive.measure?(%{"mirror" => ""})
      assert BbpartyWeb.RenderLive.measure?(%{})
      assert BbpartyWeb.RenderLive.measure?(%{"other" => "1"})
    end
  end

  describe "mount" do
    test "carries the cursor and the fingerprint the renderer must echo", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/render")
      state = RenderStateServer.get_state()

      assert html =~ ~s(data-cursor="#{state.cursor}")
      assert html =~ ~s(data-fingerprint="#{RenderState.layout_fingerprint(state)}")
    end

    test "the caret is an overlay, not a split in the text", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/render")

      send(live.pid, {:new_state, %{RenderState.new() | text: "ab", cursor: 1}})
      html = render(live)

      assert has_element?(live, "#render-root > #render-caret")
      refute has_element?(live, "#render-text #render-caret")
      assert html =~ "bbparty-caret-blink"
    end

    test "caps lock is announced only while latched", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/render")
      refute has_element?(live, "#render-caps-lock")

      send(live.pid, {:new_state, %{RenderState.new() | caps_lock: true}})
      assert has_element?(live, "#render-caps-lock", "caps lock on")

      send(live.pid, {:new_state, RenderState.new()})
      refute has_element?(live, "#render-caps-lock")
    end

    test "an empty stock invites typing, and the invitation leaves once typed into",
         %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/render")
      assert has_element?(live, "#render-root #render-placeholder", "écrivez ici")

      send(live.pid, {:new_state, %{RenderState.new() | text: "a"}})
      refute has_element?(live, "#render-placeholder")
    end

    test "while the placeholder shows, its own caret stands in for the real one",
         %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/render")
      assert has_element?(live, "#render-placeholder #render-placeholder-caret")
      refute has_element?(live, "#render-caret")

      send(live.pid, {:new_state, %{RenderState.new() | text: "a", cursor: 1}})
      refute has_element?(live, "#render-placeholder-caret")
      assert has_element?(live, "#render-caret")
    end

    test "the placeholder is never part of the measured text", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/render")

      refute has_element?(live, "#render-text #render-placeholder")
      refute has_element?(live, "#render-text", "écrivez ici")
    end

    test "a pending diacritic on an empty stock is not empty", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/render")

      send(live.pid, {:new_state, %{RenderState.new() | pending_diacritic: "´"}})
      refute has_element?(live, "#render-placeholder")
    end

    test "module 2's uppercase transform is not caps lock", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/render")

      send(live.pid, {:new_state, %{RenderState.new() | transform_toupper: true}})
      refute has_element?(live, "#render-caps-lock")
    end

    test "whitespace is preserved, or ENTER and SPACE would render nowhere", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/render")

      assert html =~ ~r/white-space:\s*pre\s*;/
    end
  end

  describe "text_layout" do
    test "a pushed measurement reaches the server and drives vertical movement",
         %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/render")

      state =
        :render_live_test_char
        |> press(%{char: "a"})
        |> then(&%{&1 | text: "abcd", cursor: 3})

      :sys.replace_state(RenderStateServer, fn server -> %{server | render: state} end)

      render_hook(live, "text_layout", %{
        "fingerprint" => RenderState.layout_fingerprint(state),
        "line_starts" => [0, 2],
        "xs" => %{"0" => [0, 10, 20], "1" => [0, 10, 20]}
      })

      assert RenderStateServer.get_layout().line_starts == [0, 2]

      press(:render_live_test_up, %{action: "up"})
      assert RenderStateServer.get_state().cursor == 1
    end

    test "a malformed push is absorbed rather than taking the renderer down",
         %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/render")

      render_hook(live, "text_layout", %{"line_starts" => "nonsense", "xs" => "nonsense"})

      assert RenderStateServer.get_layout() == %TextLayout{
               fingerprint: nil,
               line_starts: [0],
               xs: %{}
             }
    end
  end

  describe "fit" do
    defp push_fit(live, size) do
      fingerprint = RenderState.layout_fingerprint(RenderStateServer.get_state())
      render_hook(live, "fit", %{"fingerprint" => fingerprint, "size" => size})
      _ = :sys.get_state(RenderStateServer)
      fingerprint
    end

    defp listen_for_fits do
      test = self()

      spawn_link(fn ->
        Phoenix.PubSub.subscribe(Bbparty.PubSub, "render")
        send(test, :listening)
        forward_to(test)
      end)

      assert_receive :listening
    end

    defp forward_to(pid) do
      receive do
        message -> send(pid, {:heard, message})
      end

      forward_to(pid)
    end

    defp font_size(live) do
      [_, size] = Regex.run(~r/id="render-text"[^>]*font-size:\s*([\d.]+)cqw/s, render(live))
      String.to_float(size)
    end

    test "a pushed size is what both pages render", %{conn: conn} do
      {:ok, screen, _html} = live(conn, ~p"/render")
      {:ok, print, _html} = live(conn, ~p"/print_render")

      fingerprint = push_fit(screen, 12.5)

      assert RenderStateServer.get_fit() == %Fit{fingerprint: fingerprint, size: 12.5}
      assert font_size(screen) == 12.5
      assert font_size(print) == 12.5
      assert has_element?(print, ~s(#render-root[data-fitted-for="#{fingerprint}"]))
    end

    test "a cursor move keeps the fitted size", %{conn: conn} do
      {:ok, screen, _html} = live(conn, ~p"/render")

      :sys.replace_state(RenderStateServer, fn s ->
        %{s | render: %{s.render | text: "abc", cursor: 3}}
      end)

      push_fit(screen, 20.0)

      moved = %{RenderStateServer.get_state() | cursor: 1}
      :sys.replace_state(RenderStateServer, fn s -> %{s | render: moved} end)
      send(screen.pid, {:new_state, moved})

      assert font_size(screen) == 20.0
    end

    test "an accepted size is broadcast, a stale one is not", %{conn: conn} do
      {:ok, screen, _html} = live(conn, ~p"/render")
      listen_for_fits()

      fingerprint = push_fit(screen, 9.0)
      assert_receive {:heard, {:fit, %Fit{fingerprint: ^fingerprint, size: 9.0}}}

      render_hook(screen, "fit", %{"fingerprint" => "superseded", "size" => 30.0})
      _ = :sys.get_state(RenderStateServer)

      refute_receive {:heard, {:fit, _}}
      assert RenderStateServer.get_fit().size == 9.0
    end

    test "a malformed push changes nothing", %{conn: conn} do
      {:ok, screen, _html} = live(conn, ~p"/render")

      render_hook(screen, "fit", %{"fingerprint" => 3, "size" => "big"})
      _ = :sys.get_state(RenderStateServer)

      assert RenderStateServer.get_fit() == Fit.empty()
    end
  end

  describe "the typed text reaches the display" do
    test "a press renders and moves the cursor with it", %{conn: conn} do
      {:ok, live, _html} = live(conn, ~p"/render")

      press(:render_live_test_char, %{char: "Z"})

      html = render(live)
      assert html =~ "Z"
      assert html =~ ~s(data-cursor="1")
    end
  end
end
