defmodule Bbparty.Print.LabelTest do
  use ExUnit.Case, async: false

  alias Bbparty.Print.Label

  defp configure(opts) do
    previous = Application.get_env(:bbparty, :label)
    Application.put_env(:bbparty, :label, opts)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:bbparty, :label)
        value -> Application.put_env(:bbparty, :label, value)
      end
    end)
  end

  describe "to_dots/2" do
    test "millimetres to dots, checkable by hand" do
      assert Label.to_dots(25.4, 300) == 300
      assert Label.to_dots(25.4, 203) == 203
      assert Label.to_dots(100, 300) == 1181
      assert Label.to_dots(50, 300) == 591
    end

    test "the same label at 203 dpi" do
      assert Label.to_dots(100, 203) == 799
      assert Label.to_dots(50, 203) == 400
    end
  end

  describe "the installed defaults" do
    test "100x50 mm at 300 dpi" do
      assert Label.mm() == {100, 50}
      assert Label.dpi() == 300
      assert Label.dots() == {1181, 591}
    end
  end

  describe "aspect_ratio/0" do
    test "is the stock's proportions, as CSS wants them" do
      configure(mm: {100, 50})

      assert Label.aspect_ratio() == "100 / 50"
    end

    test "follows the stock" do
      configure(mm: {60, 40})

      assert Label.aspect_ratio() == "60 / 40"
    end
  end

  describe "capture_scale/1" do
    test "takes a measured layout to the head's dot count" do
      configure(mm: {100, 50}, dpi: 300)

      assert_in_delta Label.capture_scale(800), 1181 / 800, 0.0001
    end

    test "a different measured width gives a different scale, same dot count" do
      configure(mm: {100, 50}, dpi: 300)

      assert Label.dots() == {1181, 591}
      assert_in_delta Label.capture_scale(400), 1181 / 400, 0.0001
      assert_in_delta Label.capture_scale(1920), 1181 / 1920, 0.0001
    end

    test "a capture already at the head's width needs no scaling" do
      configure(mm: {100, 50}, dpi: 300)

      assert_in_delta Label.capture_scale(1181), 1.0, 0.0001
    end
  end

  describe "capture_scale/2 with a device pixel ratio" do
    test "halves the scale on a 2x window, for the same dot count" do
      configure(mm: {100, 50}, dpi: 300)

      assert_in_delta Label.capture_scale(800, 2), 1181 / 800 / 2, 0.0001
    end

    test "measured width x scale x ratio is always the head's dot count" do
      configure(mm: {100, 50}, dpi: 300)

      for css_width <- [400, 800, 1181, 1920], dpr <- [1, 2, 3] do
        assert_in_delta css_width * Label.capture_scale(css_width, dpr) * dpr, 1181, 0.0001
      end
    end

    test "a ratio of 1 is the same as not passing one" do
      configure(mm: {100, 50}, dpi: 300)

      assert Label.capture_scale(800, 1) == Label.capture_scale(800)
    end
  end

  describe "points_across/0" do
    test "the stock's width in points, checkable by hand" do
      configure(mm: {100, 50}, dpi: 300)

      assert_in_delta Label.points_across(), 283.4646, 0.001
    end

    test "an inch of stock is 72 points" do
      configure(mm: {25.4, 25.4}, dpi: 300)

      assert_in_delta Label.points_across(), 72.0, 0.0001
    end

    test "does not depend on the head's resolution" do
      configure(mm: {100, 50}, dpi: 300)
      at_300 = Label.points_across()

      configure(mm: {100, 50}, dpi: 203)

      assert Label.points_across() == at_300
    end

    test "wider stock is more points across" do
      configure(mm: {200, 50}, dpi: 300)

      assert_in_delta Label.points_across(), 566.9291, 0.001
    end
  end

  describe "points_to_cqw/2" do
    setup do
      configure(mm: {100, 50}, dpi: 300)
    end

    test "a size as wide as the stock is 100cqw when nothing is padded" do
      assert_in_delta Label.points_to_cqw(Label.points_across(), 0.0), 100.0, 0.0001
    end

    test "half the stock's width is 50cqw" do
      assert_in_delta Label.points_to_cqw(Label.points_across() / 2, 0.0), 50.0, 0.0001
    end

    test "padding makes the same physical size a larger share of the text area" do
      unpadded = Label.points_to_cqw(24, 0.0)
      padded = Label.points_to_cqw(24, 0.03)

      assert padded > unpadded
      assert_in_delta padded, unpadded / 0.94, 0.0001
    end

    test "24pt on 100mm stock with 3% padding" do
      assert_in_delta Label.points_to_cqw(24, 0.03), 9.0068, 0.001
    end

    test "scales linearly with the size" do
      assert_in_delta Label.points_to_cqw(48, 0.03), 2 * Label.points_to_cqw(24, 0.03), 0.0001
    end

    test "does not depend on the head's resolution" do
      at_300 = Label.points_to_cqw(24, 0.03)

      configure(mm: {100, 50}, dpi: 203)

      assert Label.points_to_cqw(24, 0.03) == at_300
    end

    test "wider stock makes the same points a smaller share of it" do
      narrow = Label.points_to_cqw(24, 0.03)

      configure(mm: {200, 50}, dpi: 300)

      assert_in_delta Label.points_to_cqw(24, 0.03), narrow / 2, 0.0001
    end
  end

  describe "content_aspect/1" do
    setup do
      configure(mm: {100, 50}, dpi: 300)
    end

    test "with no padding it is the stock's own proportions" do
      assert_in_delta Label.content_aspect(0.0), 0.5, 0.0001
    end

    test "100x50 stock at 3% a side" do
      assert_in_delta Label.content_aspect(0.03), (0.5 - 0.06) / 0.94, 0.0001
      assert_in_delta Label.content_aspect(0.03), 0.4681, 0.0001
    end

    test "padding flattens landscape stock rather than squaring it up" do
      assert Label.content_aspect(0.03) < 0.5
    end

    test "and stretches portrait stock, for the same reason" do
      configure(mm: {50, 100}, dpi: 300)

      assert Label.content_aspect(0.03) > 2.0
      assert_in_delta Label.content_aspect(0.03), (2.0 - 0.06) / 0.94, 0.0001
    end

    test "more padding moves it further from the stock's ratio" do
      stock = 0.5

      assert abs(Label.content_aspect(0.10) - stock) > abs(Label.content_aspect(0.03) - stock)
    end

    test "square stock stays square at any padding" do
      configure(mm: {80, 80}, dpi: 300)

      for padding <- [0.0, 0.03, 0.2, 0.4] do
        assert_in_delta Label.content_aspect(padding), 1.0, 0.0001
      end
    end

    test "follows the stock" do
      configure(mm: {200, 50}, dpi: 300)

      assert_in_delta Label.content_aspect(0.0), 0.25, 0.0001
    end

    test "refuses a padding that would leave no content box" do
      assert_raise FunctionClauseError, fn -> Label.content_aspect(0.5) end
    end
  end
end
