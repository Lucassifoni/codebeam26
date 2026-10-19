defmodule BbpartyWeb.StickersLiveTest do
  use BbpartyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Bbparty.Printouts
  alias Bbparty.RenderState

  defp print!(fields, second) do
    at = DateTime.add(~U[2026-09-21 20:00:00.000000Z], second)
    {:ok, printout} = Printouts.record(struct(RenderState.new(), fields), at)
    printout
  end

  defp print_many!(n), do: for(i <- 1..n, do: print!([text: "sticker #{i}"], i))

  describe "an empty archive" do
    test "draws no sticker and asks for nothing more", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/stickers")

      assert has_element?(view, "#stickers")
      refute has_element?(view, "#stickers > li")
      refute has_element?(view, "#stickers[phx-viewport-bottom]")
    end
  end

  describe "the archive" do
    test "draws each printout as a sticker, newest first", %{conn: conn} do
      old = print!([text: "premier"], 1)
      new = print!([text: "dernier"], 2)

      {:ok, view, _html} = live(conn, "/stickers")

      assert has_element?(view, "#sticker-#{old.id}-text", "premier")
      assert has_element?(view, "#sticker-#{new.id}-text", "dernier")

      ids =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#stickers > li")
        |> LazyHTML.attribute("id")

      assert ids == ["stickers-#{new.id}", "stickers-#{old.id}"]
    end

    test "re-renders the stored state, not the live one", %{conn: conn} do
      printout = print!([text: "centré", alignment: :center, transform_toupper: true], 1)

      {:ok, view, _html} = live(conn, "/stickers")

      [style] =
        view
        |> element("#sticker-#{printout.id}-text")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.attribute("style")

      assert style =~ "text-align: center"
      assert style =~ "text-transform: uppercase"
    end

    test "sizes each sticker in the browser, silently", %{conn: conn} do
      printout = print!([text: "x"], 1)

      {:ok, view, _html} = live(conn, "/stickers")

      root = "#sticker-#{printout.id}-root"
      assert has_element?(view, ~s(#{root}[data-fit-locally="true"][data-measure="false"]))
      refute has_element?(view, "#sticker-#{printout.id}-caret")
      refute has_element?(view, "#sticker-#{printout.id}-placeholder")
    end
  end

  describe "scrolling" do
    test "loads the first page, then the rest on reaching the bottom", %{conn: conn} do
      printouts = print_many!(30)
      oldest = hd(printouts)
      newest = List.last(printouts)

      {:ok, view, _html} = live(conn, "/stickers")

      assert has_element?(view, "#stickers-#{newest.id}")
      refute has_element?(view, "#stickers-#{oldest.id}")
      assert has_element?(view, ~s(#stickers[phx-viewport-bottom="load_more"]))

      render_hook(view, "load_more", %{})

      assert has_element?(view, "#stickers-#{oldest.id}")
      refute has_element?(view, "#stickers[phx-viewport-bottom]")
    end

    test "stops asking once everything is shown", %{conn: conn} do
      print_many!(3)

      {:ok, view, _html} = live(conn, "/stickers")

      assert view
             |> element("#stickers")
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("li")
             |> Enum.count() == 3

      refute has_element?(view, "#stickers[phx-viewport-bottom]")
    end
  end
end
