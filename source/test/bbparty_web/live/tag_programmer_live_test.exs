defmodule BbpartyWeb.TagProgrammerLiveTest do
  use BbpartyWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders the connect and paste sections without hardware", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/tags")

    assert html =~ "NFC tags"
    assert html =~ "waiting for board 2"
    assert html =~ "one target string per line"
  end

  test "rejects an over-length line", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/tags")

    too_long = String.duplicate("x", 47)
    html = render_submit(element(view, "form[phx-submit=load]"), %{"lines" => too_long})

    assert html =~ "exceeds the 46-byte limit"
  end

  test "read mode displays the last tag read", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/tags")

    render_click(element(view, "button[phx-value-mode=read]"))
    send(view.pid, {:module2, {:tag_read, %{uid: <<0x04, 0x9F>>, sak: 0, text: "hello-tag"}}})
    html = render(view)

    assert html =~ "hello-tag"
    assert html =~ "049F"
  end
end
