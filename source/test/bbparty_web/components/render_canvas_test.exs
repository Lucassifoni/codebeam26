defmodule BbpartyWeb.RenderCanvasTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias Bbparty.FontBundle
  alias Bbparty.Print.Label
  alias Bbparty.RenderState
  alias BbpartyWeb.RenderCanvas

  defp canvas_html(state) do
    render_component(&RenderCanvas.canvas/1,
      state: state,
      fingerprint: "fingerprint",
      palette: :print,
      measure: false
    )
  end

  defp style_of(html, id) do
    case Regex.run(~r/id="#{id}"[^>]*?style="([^"]*)"/s, html) do
      [_, style] -> style
      nil -> flunk("no element with id #{id}, or it carries no style")
    end
  end

  defp text_style(state \\ RenderState.new()),
    do: state |> canvas_html() |> style_of("render-text")

  defp root_style(state \\ RenderState.new()),
    do: state |> canvas_html() |> style_of("render-root")

  defp at_zoom(zoom), do: %{RenderState.new() | zoom: zoom}

  defp aligned(alignment), do: %{RenderState.new() | alignment: alignment}

  defp attr(state, name) do
    [_, value] = Regex.run(~r/#{name}="([\d.e-]+)"/, canvas_html(state))
    String.to_float(value)
  end

  defp scale(state) do
    [_, value] = Regex.run(~r/transform:\s*scale\(([\d.e-]+)\)/, text_style(state))
    String.to_float(value)
  end

  defp font_size_cqw(state) do
    [_, value] = Regex.run(~r/font-size:\s*([\d.e-]+)cqw/, text_style(state))
    String.to_float(value)
  end

  defp padding_fraction(state) do
    [_, value] = Regex.run(~r/padding:\s*([\d.]+)%/, root_style(state))
    String.to_float(value) / 100
  end

  describe "the text element carries no absolute length" do
    test "no pt" do
      refute text_style() =~ ~r/[\d.]\s*pt\b/
    end

    test "no px" do
      refute text_style() =~ ~r/[\d.]\s*px\b/
    end

    test "no other absolute unit" do
      for unit <- ~w(cm mm in pc q) do
        refute text_style() =~ ~r/[\d.]\s*#{unit}\b/i,
               "#{unit} is an absolute length and must not reach the text element"
      end
    end
  end

  describe "the lengths that are there" do
    test "font-size is a share of the render area" do
      assert text_style() =~ ~r/font-size:\s*[\d.e-]+cqw/
    end

    test "letter-spacing is relative to the type size" do
      assert text_style() =~ ~r/letter-spacing:\s*[-\d.e]+em/
    end

    test "line-height stays a unitless multiple" do
      assert text_style() =~ ~r/line-height:\s*[\d.]+\s*;/
    end

    test "the render area is a query container" do
      assert root_style() =~ "container-type: inline-size"
    end
  end

  describe "the feature switches reach the type" do
    defp with_features(features), do: %{RenderState.new() | cumulative_features: features}

    defp feature_settings(state), do: state |> text_style() |> unescape()

    defp unescape(style), do: String.replace(style, "&quot;", "\"")

    test "an active feature is declared on" do
      assert feature_settings(with_features(["ss01"])) =~ ~s(font-feature-settings:)
      assert feature_settings(with_features(["ss01"])) =~ ~s("ss01" 1)
    end

    test "a feature nobody threw is declared off, not left out" do
      assert feature_settings(with_features([])) =~ ~s("ss01" 0)
      assert feature_settings(with_features([])) =~ ~s("liga" 0)
    end

    test "the composite switch declares both of its tags" do
      value = feature_settings(with_features(["smcp+c2sc"]))

      assert value =~ ~s("smcp" 1)
      assert value =~ ~s("c2sc" 1)
    end

    test "the plain small-caps switch declares only its own" do
      value = feature_settings(with_features(["smcp"]))

      assert value =~ ~s("smcp" 1)
      assert value =~ ~s("c2sc" 0)
    end

    test "throwing a switch invalidates the measurement" do
      refute RenderState.layout_fingerprint(with_features(["ss01"])) ==
               RenderState.layout_fingerprint(with_features([]))
    end
  end

  describe "the text does not soft-wrap" do
    test "whitespace is preserved but lines are not broken for the typist" do
      assert text_style() =~ ~r/white-space:\s*pre\s*;/
    end

    test "it is pre and not pre-wrap" do
      refute text_style() =~ "pre-wrap"
    end

    test "no rule breaks a long word either" do
      refute text_style() =~ "overflow-wrap"
      refute text_style() =~ "word-break"
    end

    test "a line too long for the stock is cropped rather than folded" do
      assert root_style() =~ "overflow: hidden"
    end
  end

  describe "the composition holds no whitespace the typist did not type" do
    defp composition_html(state) do
      html = canvas_html(state)

      case Regex.run(~r/<div id="render-text"[^>]*>(.*?)<\/div>/s, html) do
        [_, inner] -> inner
        nil -> flunk("no #render-text element")
      end
    end

    test "an empty text renders an empty element" do
      assert composition_html(%{RenderState.new() | text: ""}) == ""
    end

    test "the text is the whole content, with nothing around it" do
      assert composition_html(%{RenderState.new() | text: "ab"}) == "ab"
    end

    test "a pending diacritic adds its span and no whitespace" do
      state = %{RenderState.new() | text: "ab", cursor: 1, pending_diacritic: "´"}

      inner = composition_html(state)

      assert inner =~ ~r/^a<span [^>]*>´<\/span>b$/
    end

    test "typed spaces and newlines are still preserved" do
      assert composition_html(%{RenderState.new() | text: "a  b\nc"}) == "a  b\nc"
    end
  end

  describe "the pinned faces lead whatever the selection" do
    defp families(state) do
      style = String.replace(text_style(state), "&quot;", ~s("))
      [_, list] = Regex.run(~r/font-family:\s*([^;]*);/, style)
      list |> String.split(",") |> Enum.map(&String.trim/1)
    end

    defp pinned, do: Enum.map(FontBundle.pinned_families(), &~s("#{&1}"))

    test "the pins lead the stack, ahead of the selected font" do
      state = %{RenderState.new() | selected_font: "Boogy Brut Bold"}

      assert families(state) == pinned() ++ [~s("Boogy Brut Bold"), "sans-serif"]
    end

    test "the pins lead even when no font is selected" do
      assert families(RenderState.new()) == pinned() ++ ["sans-serif"]
    end

    test "an id the manifest does not carry is the same as none" do
      state = %{RenderState.new() | selected_font: "Not A Font"}

      assert families(state) == families(RenderState.new())
    end
  end

  describe "the fitted size comes from the server" do
    alias Bbparty.RenderState.Fit

    defp with_fit(fit) do
      render_component(&RenderCanvas.canvas/1,
        state: RenderState.new(),
        fingerprint: "now",
        fit: fit,
        palette: :print,
        measure: false
      )
    end

    test "the accepted size is rendered as the font-size" do
      assert style_of(with_fit(%Fit{fingerprint: "now", size: 17.5}), "render-text") =~
               "font-size: 17.5cqw"
    end

    test "the page says which fingerprint its size was fitted for" do
      html = with_fit(%Fit{fingerprint: "before", size: 17.5})

      assert html =~ ~s(data-fitted-for="before")
      assert html =~ ~s(data-fingerprint="now")
    end
  end

  describe "the fit's floor is what gets painted first" do
    test "the rendered size is the floor, converted by the label's own arithmetic" do
      {floor, _ceiling} = RenderState.fit_bounds()
      state = RenderState.new()

      assert_in_delta font_size_cqw(state),
                      Label.points_to_cqw(floor, padding_fraction(state)),
                      0.0001
    end

    test "the padding used for the conversion is the padding actually rendered" do
      {floor, _ceiling} = RenderState.fit_bounds()
      state = RenderState.new()
      usable = 1 - 2 * padding_fraction(state)

      assert_in_delta font_size_cqw(state),
                      floor / Label.points_across() * 100 / usable,
                      0.0001
    end

    test "the painted size does not vary with the state" do
      long = %{RenderState.new() | text: String.duplicate("wide ", 200)}

      assert_in_delta font_size_cqw(long), font_size_cqw(RenderState.new()), 0.0001
    end
  end

  describe "what the renderer is told about the fit" do
    test "the bounds travel as shares of the render area, not as points" do
      {floor, ceiling} = RenderState.fit_bounds()
      state = RenderState.new()

      assert_in_delta attr(state, "data-fit-min"),
                      Label.points_to_cqw(floor, padding_fraction(state)),
                      0.0001

      assert_in_delta attr(state, "data-fit-max"),
                      Label.points_to_cqw(ceiling, padding_fraction(state)),
                      0.0001
    end

    test "the floor is below the ceiling once converted, too" do
      state = RenderState.new()
      assert attr(state, "data-fit-min") < attr(state, "data-fit-max")
    end

    test "the reference box carries the content box's proportions" do
      state = RenderState.new()

      assert_in_delta attr(state, "data-content-aspect"),
                      Label.content_aspect(padding_fraction(state)),
                      0.0001
    end

    test "the reference box is flatter than the stock, not just smaller" do
      state = RenderState.new()
      {w, h} = Label.mm()
      p = padding_fraction(state)

      assert_in_delta attr(state, "data-content-aspect"), (h / w - 2 * p) / (1 - 2 * p), 0.0001
      assert h < w, "this stock is landscape; the direction below follows from that"
      assert attr(state, "data-content-aspect") < h / w
    end

    test "the fingerprint the fit is cached on is the layout fingerprint" do
      state = %{RenderState.new() | text: "hello"}

      html =
        render_component(&RenderCanvas.canvas/1,
          state: state,
          fingerprint: RenderState.layout_fingerprint(state),
          palette: :print,
          measure: false
        )

      assert [_, value] = Regex.run(~r/data-fingerprint="([^"]*)"/, html)
      assert value == RenderState.layout_fingerprint(state)
    end
  end

  describe "the zoom frames the composition without re-composing it" do
    test "neutral leaves the fitted composition at life size" do
      assert scale(RenderState.new()) == 1.0
    end

    test "zooming out shrinks it, zooming in magnifies it" do
      assert scale(at_zoom(-1.0)) < 1.0
      assert scale(at_zoom(1.0)) > 1.0
    end

    test "no zoom touches the size the text is set at" do
      neutral = font_size_cqw(at_zoom(0.0))

      for zoom <- [-2.0, -1.0, 1.0, 2.0] do
        assert_in_delta font_size_cqw(at_zoom(zoom)), neutral, 0.0001
      end
    end

    test "the composition is centred vertically in the stock" do
      assert root_style() =~ "align-items: center"
    end

    test "centred text zooms about the centre, so the crop closes in evenly" do
      assert text_style(aligned(:center)) =~ "transform-origin: 50% 50%"
    end

    test "left-aligned text zooms about the left edge, so it keeps its start" do
      assert text_style(aligned(:left)) =~ "transform-origin: 0% 50%"
    end

    test "the text spans the render area and does not shrink to its content" do
      assert text_style() =~ ~r/width:\s*100%/
      assert text_style() =~ ~r/flex:\s*0 0 auto/
    end

    test "an over-long line cannot widen the box it is centred in" do
      assert text_style() =~ ~r/min-width:\s*0\s*;/
    end

    test "the magnification is on the text, never on the render root" do
      refute root_style(at_zoom(2.0)) =~ "transform:"
    end

    test "the crop is the render area's existing overflow clip" do
      assert root_style(at_zoom(2.0)) =~ "overflow: hidden"
    end
  end

  describe "sticker/1" do
    defp sticker_html(assigns) do
      render_component(
        &RenderCanvas.sticker/1,
        Keyword.merge([state: RenderState.new(), fingerprint: "fp", palette: :print], assigns)
      )
    end

    test "prefixes every id with its own, so many can share a page" do
      html =
        sticker_html(
          id: "sticker-7",
          state: %{RenderState.new() | text: "à", pending_diacritic: "´"}
        )

      assert html =~ ~s(id="sticker-7-root")
      assert html =~ ~s(id="sticker-7-text")
      assert html =~ ~s(id="sticker-7-pending")
      refute html =~ ~s(id="render-)
    end

    test "carries no page wrapper" do
      refute sticker_html([]) =~ "render-page"
    end

    test "hides the text until the browser has fitted it" do
      html = sticker_html(fit_locally: true)

      assert html =~ ~s(data-fit-locally="true")
      assert style_of(html, "render-text") =~ "visibility: hidden"
    end

    test "shows the text straight away when a fit is known or none is computed" do
      fitted =
        sticker_html(
          fit_locally: true,
          fit: %Bbparty.RenderState.Fit{fingerprint: "fp", size: 12}
        )

      refute style_of(fitted, "render-text") =~ "visibility"
      refute style_of(sticker_html([]), "render-text") =~ "visibility"
    end
  end
end
