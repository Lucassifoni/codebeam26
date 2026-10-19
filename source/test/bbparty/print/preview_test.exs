defmodule Bbparty.Print.PreviewTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  alias Bbparty.Print.Preview

  setup do
    Preview.clear()
    on_exit(&Preview.clear/0)
    :ok
  end

  describe "put/2 and last/0" do
    test "nothing before the first sticker" do
      assert Preview.last() == nil
      assert Preview.last_data_uri() == nil
    end

    test "keeps the image and its dimensions" do
      Preview.put("PNGBYTES", width: 1181, height: 591, printed?: true)

      assert %{png: "PNGBYTES", width: 1181, height: 591, printed?: true} = Preview.last()
    end

    test "records whether it actually reached the printer" do
      Preview.put("A", printed?: false)
      refute Preview.last().printed?

      Preview.put("B", printed?: true)
      assert Preview.last().printed?
    end

    test "the newest replaces the last" do
      Preview.put("first")
      Preview.put("second")

      assert Preview.last().png == "second"
    end

    test "as a data URI, ready for an img tag" do
      Preview.put("PNGBYTES")

      assert Preview.last_data_uri() == "data:image/png;base64," <> Base.encode64("PNGBYTES")
    end
  end

  describe "announcements" do
    test "a new sticker is broadcast, so an open panel updates without a reload" do
      Preview.subscribe()

      Preview.put("PNGBYTES", width: 8, height: 4)

      assert_receive {:sticker_preview, %{png: "PNGBYTES", width: 8}}
    end

    test "clearing is broadcast too" do
      Preview.subscribe()
      Preview.put("PNGBYTES")
      assert_receive {:sticker_preview, %{}}

      Preview.clear()

      assert_receive {:sticker_preview, nil}
    end
  end

  describe "the printer's display" do
    test "says so when there is nothing to show" do
      html = render_printer()

      assert html =~ "no sticker yet"
    end

    test "shows the sticker and its size once there is one" do
      Preview.put(png_fixture(), width: 1181, height: 591, printed?: true)

      html = render_printer()

      assert html =~ "data:image/png;base64,"
      assert html =~ "1181"
      assert html =~ "591"
      assert html =~ "printed"
    end

    test "distinguishes a dry run from a real print" do
      Preview.put(png_fixture(), width: 8, height: 4, printed?: false)

      assert render_printer() =~ "preview"
    end
  end

  defp png_fixture do
    {:ok, image} =
      Vix.Vips.Image.new_from_binary(
        :binary.copy(<<255, 255, 255>>, 8),
        4,
        2,
        3,
        :VIPS_FORMAT_UCHAR
      )

    {:ok, png} = Vix.Vips.Image.write_to_buffer(image, ".png")
    png
  end

  defp render_printer do
    render_component(&Hardware.Components.Printer.Display.render/1,
      id: :printer,
      attrs: %{},
      data: Hardware.Components.Printer.new([]),
      revision: 0
    )
  end
end
