defmodule BbpartyWeb.StickerLiveTest do
  use BbpartyWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Bbparty.Printouts
  alias Bbparty.RenderState
  alias BbpartyWeb.StickerLive

  defp print!(fields) do
    {:ok, printout} =
      Printouts.record(struct(RenderState.new(), fields), ~U[2026-09-21 20:00:00.000000Z])

    printout
  end

  test "draws the one printout, from its stored state", %{conn: conn} do
    printout = print!(text: "centré", alignment: :center)
    other = print!(text: "autre")

    {:ok, view, _html} = live(conn, "/stickers/#{printout.id}")

    assert has_element?(view, "#sticker-#{printout.id}-text", "centré")
    refute has_element?(view, "#sticker-#{other.id}-text")

    [style] =
      view
      |> element("#sticker-#{printout.id}-text")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.attribute("style")

    assert style =~ "text-align: center"
  end

  test "the sticker is sized in the browser and sits where root_id/1 says", %{conn: conn} do
    printout = print!(text: "x")

    {:ok, view, _html} = live(conn, "/stickers/#{printout.id}")

    assert has_element?(view, ~s(##{StickerLive.root_id(printout.id)}[data-fit-locally="true"]))
    refute has_element?(view, "#sticker-#{printout.id}-caret")
  end

  test "an unknown printout is not found", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn -> live(conn, "/stickers/0") end
  end
end
