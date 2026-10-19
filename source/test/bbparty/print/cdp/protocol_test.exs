defmodule Bbparty.Print.Cdp.ProtocolTest do
  use ExUnit.Case, async: true

  alias Bbparty.Print.Cdp.Protocol

  defp page(url, ws \\ "ws://localhost:9222/devtools/page/ABC") do
    %{"type" => "page", "url" => url, "webSocketDebuggerUrl" => ws}
  end

  describe "select_target/2" do
    test "finds the page serving the route" do
      targets = [
        page("http://localhost:4000/"),
        page("http://localhost:4000/print_render", "ws://x")
      ]

      assert Protocol.select_target(targets, "/print_render") == {:ok, "ws://x"}
    end

    test "matches on the path, so host and port are the browser's business" do
      targets = [page("http://192.168.1.40:4000/print_render?debug=1", "ws://y")]

      assert Protocol.select_target(targets, "/print_render") == {:ok, "ws://y"}
    end

    test "ignores targets that are not pages" do
      targets = [
        %{
          "type" => "service_worker",
          "url" => "http://localhost:4000/print_render",
          "webSocketDebuggerUrl" => "ws://sw"
        }
      ]

      assert Protocol.select_target(targets, "/print_render") == {:error, :no_such_page}
    end

    test "no such page" do
      assert Protocol.select_target([page("http://localhost:4000/")], "/print_render") ==
               {:error, :no_such_page}
    end

    test "an empty listing" do
      assert Protocol.select_target([], "/print_render") == {:error, :no_such_page}
    end
  end

  describe "rect_command/2" do
    setup do
      %{command: Protocol.rect_command(7, "#render-root")}
    end

    test "carries its id, so the reply can be matched", %{command: command} do
      assert command.id == 7
    end

    test "waits for webfonts before measuring", %{command: command} do
      assert command.params.expression =~ "document.fonts.ready"
      assert command.params.awaitPromise
    end

    test "reports page-absolute coordinates", %{command: command} do
      assert command.params.expression =~ "window.scrollX"
      assert command.params.expression =~ "window.scrollY"
    end

    test "waits until the page shows a size fitted for its current text",
         %{command: command} do
      assert command.params.expression =~ "el.dataset.fittedFor === el.dataset.fingerprint"
      assert command.params.expression =~ "unfitted: true"
    end

    test "returns a value rather than a remote object handle", %{command: command} do
      assert command.params.returnByValue
    end

    test "measures the window's device pixel ratio alongside the rectangle",
         %{command: command} do
      assert command.params.expression =~ "window.devicePixelRatio"
    end

    test "the selector is quoted into the expression safely" do
      selector = "#a\"b"
      command = Protocol.rect_command(1, selector)

      assert command.params.expression =~ "querySelector(" <> inspect(selector)
    end
  end

  describe "rect_command/3 for a sticker sized in the browser" do
    setup do
      %{command: Protocol.rect_command(7, "#sticker-3-root", :local)}
    end

    test "waits for the page to have sized and shown the text", %{command: command} do
      assert command.params.expression =~ ~s(text.style.visibility === "visible")
      assert command.params.expression =~ "unfitted: true"
      assert command.params.awaitPromise
    end

    test "waits for webfonts, which change the size once loaded", %{command: command} do
      assert command.params.expression =~ ~s(document.fonts.status === "loaded")
    end

    test "does not wait on a fit from the server, which never comes", %{command: command} do
      refute command.params.expression =~ "fittedFor"
    end

    test "reports the same rectangle as the server-fitted one", %{command: command} do
      assert command.params.expression =~ "window.scrollX"
      assert command.params.expression =~ "window.devicePixelRatio"
      assert command.params.returnByValue
    end

    test "the selector is quoted into the expression safely" do
      selector = "#a\"b"
      command = Protocol.rect_command(1, selector, :local)

      assert command.params.expression =~ "querySelector(" <> inspect(selector)
    end
  end

  describe "navigate_command/2" do
    test "points the tab at the url" do
      assert Protocol.navigate_command(4, "http://localhost:4000/stickers/3") == %{
               id: 4,
               method: "Page.navigate",
               params: %{url: "http://localhost:4000/stickers/3"}
             }
    end
  end

  describe "navigated/1" do
    test "a navigation the browser committed to" do
      assert Protocol.navigated(%{"frameId" => "F", "loaderId" => "L"}) == :ok
    end

    test "a navigation that went nowhere carries the browser's reason" do
      assert Protocol.navigated(%{"frameId" => "F", "errorText" => "net::ERR_CONNECTION_REFUSED"}) ==
               {:error, {:navigation_failed, "net::ERR_CONNECTION_REFUSED"}}
    end
  end

  describe "screenshot_command/3" do
    setup do
      rect = %{x: 10, y: 20, width: 800, height: 400}
      %{command: Protocol.screenshot_command(2, rect, 1.47625)}
    end

    test "clips to the measured rectangle", %{command: command} do
      assert command.params.clip.x == 10
      assert command.params.clip.y == 20
      assert command.params.clip.width == 800
      assert command.params.clip.height == 400
    end

    test "carries the capture scale", %{command: command} do
      assert command.params.clip.scale == 1.47625
    end

    test "captures beyond the viewport, so page coordinates mean what they say", %{
      command: command
    } do
      assert command.params.captureBeyondViewport
    end

    test "asks for png, not a lossy format", %{command: command} do
      assert command.params.format == "png"
    end
  end

  describe "classify/1" do
    test "a result carries its id" do
      assert Protocol.classify(%{"id" => 3, "result" => %{"data" => "x"}}) ==
               {:result, 3, %{"data" => "x"}}
    end

    test "an error carries its message" do
      frame = %{"id" => 3, "error" => %{"message" => "Cannot find context"}}

      assert Protocol.classify(frame) == {:error, 3, "Cannot find context"}
    end

    test "an event has no id" do
      assert Protocol.classify(%{"method" => "Page.frameNavigated"}) == :event
    end
  end

  describe "rect/1" do
    test "reads the rectangle out of an evaluate result" do
      result = %{
        "result" => %{
          "value" => %{"x" => 1, "y" => 2, "width" => 3, "height" => 4, "dpr" => 1}
        }
      }

      assert Protocol.rect(result) == {:ok, %{x: 1, y: 2, width: 3, height: 4, dpr: 1}}
    end

    test "carries the window's device pixel ratio" do
      result = %{
        "result" => %{
          "value" => %{"x" => 0, "y" => 0, "width" => 800, "height" => 400, "dpr" => 2}
        }
      }

      assert {:ok, %{dpr: 2}} = Protocol.rect(result)
    end

    test "a result without a ratio reads as 1.0" do
      result = %{"result" => %{"value" => %{"x" => 1, "y" => 2, "width" => 3, "height" => 4}}}

      assert {:ok, %{dpr: 1.0}} = Protocol.rect(result)
    end

    test "a missing element is named rather than crashing" do
      assert Protocol.rect(%{"result" => %{"value" => nil}}) == {:error, :no_element}
    end

    test "an unfitted page is refused rather than captured" do
      assert Protocol.rect(%{"result" => %{"value" => %{"unfitted" => true}}}) ==
               {:error, :not_fitted}
    end

    test "anything else is unexpected" do
      assert Protocol.rect(%{"result" => %{"value" => "nope"}}) == {:error, :unexpected_result}
    end
  end

  describe "png/1" do
    test "decodes the base64 payload" do
      assert Protocol.png(%{"data" => Base.encode64("PNGDATA")}) == {:ok, "PNGDATA"}
    end

    test "invalid base64 is unexpected, not a crash" do
      assert Protocol.png(%{"data" => "!!!"}) == {:error, :unexpected_result}
    end

    test "a result with no data at all" do
      assert Protocol.png(%{}) == {:error, :unexpected_result}
    end
  end
end
