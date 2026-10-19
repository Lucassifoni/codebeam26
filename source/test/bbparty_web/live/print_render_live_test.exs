defmodule BbpartyWeb.PrintRenderLiveTest do
  use BbpartyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Bbparty.RenderState
  alias Bbparty.RenderState.Fit
  alias Bbparty.RenderState.TextLayout
  alias Bbparty.RenderStateServer

  setup do
    reset = fn ->
      :sys.replace_state(RenderStateServer, fn _ ->
        %{render: RenderState.new(), layout: TextLayout.empty(), fit: Fit.empty()}
      end)
    end

    reset.()
    on_exit(reset)
    :ok
  end

  defp set_render_state(fields) do
    :sys.replace_state(RenderStateServer, fn s ->
      %{s | render: Map.merge(s.render, Map.new(fields))}
    end)
  end

  describe "the printable page" do
    test "never announces caps lock", %{conn: conn} do
      set_render_state(caps_lock: true)

      {:ok, view, _html} = live(conn, "/print_render")

      refute has_element?(view, "#render-caps-lock")
    end

    test "never prints the placeholder", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/print_render")

      refute has_element?(view, "#render-placeholder")
    end

    test "shows the text the panel is showing", %{conn: conn} do
      set_render_state(text: "hello sticker")

      {:ok, _view, html} = live(conn, "/print_render")

      assert html =~ "hello sticker"
    end

    test "follows the render state live", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/print_render")

      set_render_state(text: "typed after mount")
      state = RenderStateServer.get_state()
      Phoenix.PubSub.broadcast(Bbparty.PubSub, "render", {:new_state, state})

      assert render(view) =~ "typed after mount"
    end

    test "draws no caret", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/print_render")

      refute html =~ "render-caret"
    end

    test "is told not to measure", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/print_render")

      assert html =~ ~s(data-measure="false")
    end

    test "renders pure black on pure white, whatever the screen does", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/print_render")

      assert html =~ "color: #000"
      assert html =~ "background: #fff"
    end

    test "the sticker area holds the stock's aspect ratio", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/print_render")

      assert html =~ "aspect-ratio: #{Bbparty.Print.Label.aspect_ratio()}"
    end

    test "clips overflow rather than letting text run past the sticker", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/print_render")

      assert html =~ "overflow: hidden"
    end

    test "carries no rounded corners", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/print_render")

      refute html =~ "border-radius"
    end
  end

  describe "against the screen renderer" do
    test "the screen renderer still measures and draws its caret", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/render")

      assert html =~ "render-caret"
      assert html =~ ~s(data-measure="true")
    end

    test "the hook name is expanded, not left as a bare dot", %{conn: conn} do
      for path <- ["/render", "/print_render"] do
        {:ok, _view, html} = live(conn, path)

        assert html =~ ~s(phx-hook="BbpartyWeb.RenderCanvas.TextLayout")
        refute html =~ ~s(phx-hook=".TextLayout")
      end
    end

    test "both are black on white" do
      for path <- ["/render", "/print_render"] do
        {:ok, _view, html} = live(Phoenix.ConnTest.build_conn(), path)

        assert root_style(html) =~ "background: #fff"
        assert root_style(html) =~ "color: #000"
      end
    end

    test "the screen surrounds it with black, the print page with white", %{conn: conn} do
      {:ok, _view, screen} = live(conn, "/render")
      {:ok, _view, print} = live(conn, "/print_render")

      assert screen =~ ~s(id="render-page" style="background: #000;")
      assert print =~ ~s(id="render-page" style="background: #fff;")
    end

    test "both hold the same sticker proportions", %{conn: conn} do
      {:ok, _view, screen} = live(conn, "/render")
      {:ok, _view, print} = live(conn, "/print_render")

      ratio = "aspect-ratio: #{Bbparty.Print.Label.aspect_ratio()}"
      assert root_style(screen) =~ ratio
      assert root_style(print) =~ ratio
    end

    test "neither page inherits the app's themed background", %{conn: conn} do
      {:ok, _view, screen} = live(conn, "/render")
      {:ok, _view, print} = live(conn, "/print_render")

      assert root_style(screen) =~ "background:"
      assert root_style(print) =~ "background:"
    end

    test "both lay the text out identically", %{conn: conn} do
      set_render_state(zoom: 1.5, kerning: 3, leading: 1.7, alignment: :center)

      {:ok, _view, screen} = live(conn, "/render")
      {:ok, _view, print} = live(conn, "/print_render")

      assert text_style(screen) == text_style(print)

      assert text_style(print) =~ ~r/font-size: [\d.]+cqw/
      assert text_style(print) =~ "letter-spacing: 3em"
      assert text_style(print) =~ "text-align: center"
      assert text_style(print) =~ ~r/white-space:\s*pre\s*;/
    end
  end

  defp text_style(html), do: style_of(html, "render-text")
  defp root_style(html), do: style_of(html, "render-root")

  defp style_of(html, id) do
    [_, style] = Regex.run(~r/id="#{id}"[^>]*style="([^"]*)"/, html)
    style
  end
end
