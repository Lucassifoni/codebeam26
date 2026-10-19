defmodule BbpartyWeb.RenderCanvas do
  use Phoenix.Component

  alias Bbparty.FontBundle
  alias Bbparty.Print.Label
  alias Bbparty.RenderState
  alias Bbparty.RenderState.Fit

  @placeholder "écrivez ici"
  @placeholder_size_cqw 10

  attr :state, Bbparty.RenderState, required: true
  attr :fingerprint, :string, required: true

  attr :measure, :boolean,
    default: false,
    doc: "attach the layout-measuring hook and draw the caret. One renderer only."

  attr :palette, :atom, values: [:screen, :print], default: :screen

  attr :fit, Fit,
    default: %Fit{},
    doc: "the fitted type size, as accepted by the server. Rendered by both pages."

  @doc """
  A full page holding one sticker, as `/render` and `/print_render` show it.
  """
  def canvas(assigns) do
    ~H"""
    <style>
      body { margin: 0; }
      #render-page {
        min-height: 100vh;
        display: flex;
        align-items: center;
      }
    </style>
    <div id="render-page" style={page_style(@palette)}>
      <.sticker
        state={@state}
        fingerprint={@fingerprint}
        measure={@measure}
        palette={@palette}
        fit={@fit}
      />
    </div>
    """
  end

  attr :id, :string,
    default: "render",
    doc: "prefix of every DOM id inside the sticker. Must be unique on the page."

  attr :state, Bbparty.RenderState, required: true
  attr :fingerprint, :string, required: true

  attr :measure, :boolean,
    default: false,
    doc: "attach the layout-measuring hook and draw the caret. One renderer only."

  attr :fit_locally, :boolean,
    default: false,
    doc: """
    size the text in the browser, as the measuring renderer would, without telling
    the server. For stickers whose fit was never kept, such as archived printouts.
    """

  attr :palette, :atom, values: [:screen, :print], default: :screen

  attr :fit, Fit,
    default: %Fit{},
    doc: "the fitted type size, as accepted by the server."

  @doc """
  The sticker alone: its aspect ratio, padding and text, filling the width it is given.
  """
  def sticker(assigns) do
    {before, pending, rest} = RenderState.composition(assigns.state)

    assigns =
      assign(assigns,
        before: before,
        pending: pending,
        rest: rest,
        placeholder: @placeholder,
        show_placeholder: placeholder?(assigns.measure, before, pending, rest),
        caret: assigns.measure and not RenderState.overridden?(assigns.state),
        hidden_until_fitted: assigns.fit_locally and is_nil(assigns.fit.size)
      )

    ~H"""
    <style :if={@measure}>
      [data-render-caret] {
        position: absolute;
        background: currentColor;
        pointer-events: none;
        animation: bbparty-caret-blink 1.06s steps(1, end) infinite;
      }
      @keyframes bbparty-caret-blink { 0%, 50% { opacity: 1 } 50.01%, 100% { opacity: 0 } }
    </style>
    <div
      id={"#{@id}-root"}
      style={root_style(@palette)}
      phx-hook=".TextLayout"
      data-measure={to_string(@measure)}
      data-fit-locally={to_string(@fit_locally)}
      data-cursor={@state.cursor}
      data-fingerprint={@fingerprint}
      data-fitted-for={@fit.fingerprint}
      data-fit-min={fit_min_cqw()}
      data-fit-max={fit_max_cqw()}
      data-content-aspect={content_aspect()}
    >
      <div
        id={"#{@id}-text"}
        data-render-text
        style={text_style(@state, @fit, @hidden_until_fitted)}
        phx-no-format
      >{@before}<span :if={@pending} id={"#{@id}-pending"} style={pending_style(@palette)}>{@pending}</span>{@rest}</div>
      <div :if={@show_placeholder} id={"#{@id}-placeholder"} style={placeholder_style(@state)}>
        <span style="color: #808080;">{@placeholder}</span>
        <span :if={@caret} id={"#{@id}-placeholder-caret"} style={placeholder_caret_style()}></span>
      </div>
      <div :if={@caret and not @show_placeholder} id={"#{@id}-caret"} data-render-caret></div>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".TextLayout">
      const segmenter = new Intl.Segmenter(undefined, {granularity: "grapheme"})

      const boundaries = (text) => {
        const out = []
        for (const {index} of segmenter.segment(text)) out.push(index)
        out.push(text.length)
        return out
      }

      const glyphBoxes = (root) => {
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT)
        const range = document.createRange()
        const out = []
        let last = null
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          const bounds = boundaries(node.nodeValue)
          for (let i = 0; i < bounds.length - 1; i++) {
            range.setStart(node, bounds[i])
            range.setEnd(node, bounds[i + 1])
            const rects = range.getClientRects()
            const r = rects[rects.length - 1]
            if (r && r.height > 0) {
              last = {left: r.left, right: r.right, top: r.top, height: r.height}
              out.push(last)
            } else if (last) {
              out.push({left: last.right, right: last.right, top: last.top, height: last.height})
            } else {
              out.push({left: 0, right: 0, top: 0, height: 0})
            }
          }
        }
        return out
      }

      const linesOf = (boxes) => {
        const starts = [], grouped = []
        let top = null
        boxes.forEach((b, i) => {
          if (top === null || b.top - top > Math.max(1, b.height * 0.5)) {
            starts.push(i); grouped.push([]); top = b.top
          }
          grouped[grouped.length - 1].push(b)
        })
        if (starts.length === 0) { starts.push(0); grouped.push([]) }
        return {starts, grouped}
      }

      const xsOf = (boxes) => {
        if (boxes.length === 0) return [0]
        return boxes.map((b) => b.left).concat([boxes[boxes.length - 1].right])
      }

      const scaleOf = (style) => {
        const t = style.transform
        return t && t !== "none" ? new DOMMatrix(t).a : 1
      }

      const REFERENCE_WIDTH_PX = 1000

      const PROBE_PX = 200

      const fitRatio = (rect, box) =>
        Math.min(box.width / rect.width, box.height / rect.height)

      const inkRect = (block, lineHeight, contentHeight) =>
        contentHeight > 0
          ? {width: block.width, height: block.height - lineHeight + contentHeight}
          : block

      const contentHeightOf = (el) => {
        const range = document.createRange()
        range.selectNodeContents(el)
        let tallest = 0
        for (const r of range.getClientRects()) tallest = Math.max(tallest, r.height)
        return tallest
      }

      const clamp = (value, min, max) => Math.min(Math.max(value, min), max)

      const lineOf = (starts, offset) => {
        let line = 0
        for (let i = 0; i < starts.length; i++) if (starts[i] <= offset) line = i
        return line
      }

      export default {
        mounted() {
          this.measuring = this.el.dataset.measure === "true"
          this.fittingLocally = !this.measuring && this.el.dataset.fitLocally === "true"
          if (!this.measuring && !this.fittingLocally) return

          this.textEl = this.el.querySelector("[data-render-text]")
          this.lastPush = null
          this.lastFitPush = null
          this.fitted = null

          this.onFonts = () => { this.fitted = null; this.schedule() }
          document.fonts.addEventListener("loadingdone", this.onFonts)

          if (this.fittingLocally) return this.schedule()

          this.observer = new ResizeObserver(() => this.schedule())
          this.observer.observe(this.el)

          this.predictFit()
          this.schedule()
        },

        updated() {
          if (this.fittingLocally) return this.applyFit()
          if (!this.measuring) return
          this.predictFit()
          this.schedule()
        },

        reconnected() {
          if (!this.measuring) return
          this.fitted = null
          this.lastFitPush = null
          this.schedule()
        },

        destroyed() {
          if (!this.measuring && !this.fittingLocally) return
          if (this.observer) this.observer.disconnect()
          document.fonts.removeEventListener("loadingdone", this.onFonts)
          if (this.frame) cancelAnimationFrame(this.frame)
        },

        schedule() {
          if (this.frame) cancelAnimationFrame(this.frame)
          this.frame = requestAnimationFrame(() => {
            this.frame = null
            document.fonts.ready.then(() => {
              if (this.fittingLocally) return this.applyFit()
              this.pushFit()
              this.measure()
            })
          })
        },

        applyFit() {
          this.textEl.style.fontSize = this.currentFit().size + "cqw"
          this.textEl.style.visibility = "visible"
        },

        currentFit() {
          const fingerprint = this.el.dataset.fingerprint
          if (!this.fitted || this.fitted.fingerprint !== fingerprint) {
            const px = this.fitFontSize()
            this.fitted = {fingerprint, size: px / REFERENCE_WIDTH_PX * 100}
          }
          return this.fitted
        },

        predictFit() {
          if (this.el.dataset.fittedFor === this.el.dataset.fingerprint) return
          this.textEl.style.fontSize = this.currentFit().size + "cqw"
        },

        pushFit() {
          const fingerprint = this.el.dataset.fingerprint
          this.currentFit()

          const key = JSON.stringify(this.fitted)
          if (key === this.lastFitPush && this.el.dataset.fittedFor === fingerprint) return

          this.lastFitPush = key
          this.pushEvent("fit", this.fitted)
        },

        fitFontSize() {
          const box = {
            width: REFERENCE_WIDTH_PX,
            height: REFERENCE_WIDTH_PX * parseFloat(this.el.dataset.contentAspect),
          }
          const min = this.boundPx("fitMin")
          const max = this.boundPx("fitMax")
          const clone = this.cloneForMeasuring()

          document.body.appendChild(clone)
          try {
            const fitFrom = (px) => {
              clone.style.fontSize = px + "px"
              const lineHeight = parseFloat(clone.style.lineHeight) * px
              const ink = inkRect(clone.getBoundingClientRect(), lineHeight, contentHeightOf(clone))
              return px * fitRatio(ink, box)
            }
            const once = clamp(fitFrom(PROBE_PX), min, max)
            return clamp(Math.min(once, fitFrom(once)), min, max)
          } finally {
            document.body.removeChild(clone)
          }
        },

        boundPx(name) {
          return parseFloat(this.el.dataset[name]) / 100 * REFERENCE_WIDTH_PX
        },

        cloneForMeasuring() {
          const clone = this.textEl.cloneNode(true)
          clone.removeAttribute("id")
          Object.assign(clone.style, {
            position: "absolute",
            left: "-99999px",
            top: "0",
            width: "max-content",
            height: "auto",
            visibility: "hidden",
            transform: "none",
          })
          return clone
        },

        measure() {
          const cursor = parseInt(this.el.dataset.cursor, 10) || 0
          const boxes = glyphBoxes(this.textEl)

          this.drawCaret(boxes, cursor)

          const origin = this.textEl.getBoundingClientRect()
          const scale = scaleOf(getComputedStyle(this.textEl))
          const composed = boxes.map((b) => ({
            left: (b.left - origin.left) / scale,
            right: (b.right - origin.left) / scale,
            top: (b.top - origin.top) / scale,
            height: b.height / scale,
          }))

          const {starts, grouped} = linesOf(composed)
          this.report(starts, grouped, lineOf(starts, cursor))
        },

        drawCaret(boxes, cursor) {
          const caret = this.el.querySelector("[data-render-caret]")
          if (!caret) return

          const at = boxes[cursor]
          const last = boxes[boxes.length - 1]
          const spot = at
            ? {left: at.left, top: at.top, height: at.height}
            : last
              ? {left: last.right, top: last.top, height: last.height}
              : this.emptySpot()

          const origin = this.el.getBoundingClientRect()
          caret.style.left = (spot.left - origin.left) + "px"
          caret.style.top = (spot.top - origin.top) + "px"
          caret.style.height = spot.height + "px"
          caret.style.width = Math.max(1, spot.height * 0.05) + "px"

          caret.style.animation = "none"
          void caret.offsetWidth
          caret.style.animation = ""
        },

        emptySpot() {
          const style = getComputedStyle(this.textEl)
          const box = this.textEl.getBoundingClientRect()
          const height = parseFloat(style.lineHeight) || parseFloat(style.fontSize) || 16
          return {left: box.left, top: box.top, height: height * scaleOf(style)}
        },

        report(starts, grouped, cursorLine) {
          const xs = {}
          for (let l = cursorLine - 1; l <= cursorLine + 1; l++) {
            if (grouped[l]) xs[l] = xsOf(grouped[l])
          }

          const payload = {
            fingerprint: this.el.dataset.fingerprint,
            line_starts: starts,
            xs: xs,
          }

          const key = JSON.stringify(payload)
          if (key === this.lastPush) return
          this.lastPush = key
          this.pushEvent("text_layout", payload)
        },
      }
    </script>
    """
  end

  @padding_fraction 0.03

  defp root_style(palette) do
    """
    position: relative;
    box-sizing: border-box;
    width: 100%;
    aspect-ratio: #{Label.aspect_ratio()};
    padding: #{@padding_fraction * 100}%;
    overflow: hidden;
    container-type: inline-size;
    display: flex;
    align-items: center;
    #{ink(palette)}
    """
  end

  defp fit_min_cqw, do: Label.points_to_cqw(elem(RenderState.fit_bounds(), 0), @padding_fraction)
  defp fit_max_cqw, do: Label.points_to_cqw(elem(RenderState.fit_bounds(), 1), @padding_fraction)

  defp content_aspect, do: Label.content_aspect(@padding_fraction)

  defp transform(true), do: "uppercase"
  defp transform(_false), do: "none"

  defp font_family(selected) do
    families =
      FontBundle.pinned_families() ++
        List.wrap(Bbparty.FontMap.family_for_font(selected))

    quoted = Enum.map_join(families, ", ", &~s("#{&1}"))

    ~s(font-family: #{quoted}, sans-serif;)
  end

  defp pending_style(:screen), do: "background: #000; color: #fff;"
  defp pending_style(:print), do: "background: #000; color: #fff;"

  defp ink(:screen), do: "background: #fff; color: #000; border-radius: 12px;"
  defp ink(:print), do: "background: #fff; color: #000;"

  defp page_style(:screen), do: "background: #000;"
  defp page_style(:print), do: "background: #fff;"

  defp text_style(state, fit, hidden?) do
    """
    #{visibility(hidden?)}
    #{font_family(state.selected_font)}
    font-size: #{Fit.size_cqw(fit, fit_min_cqw())}cqw;
    line-height: #{state.leading};
    letter-spacing: #{state.kerning}em;
    font-feature-settings: #{Bbparty.FontMap.feature_settings(state.cumulative_features)};
    text-align: #{state.alignment};
    text-transform: #{transform(state.transform_toupper)};
    white-space: pre;
    width: 100%;
    flex: 0 0 auto;
    min-width: 0;
    transform: scale(#{RenderState.magnification(state)});
    transform-origin: #{transform_origin(state.alignment)};
    """
  end

  defp visibility(true), do: "visibility: hidden;"
  defp visibility(false), do: ""

  defp placeholder?(true, "", nil, ""), do: true
  defp placeholder?(_measure, _before, _pending, _rest), do: false

  defp placeholder_style(state) do
    """
    position: absolute;
    inset: 0;
    box-sizing: border-box;
    padding: 0 #{@padding_fraction * 100}%;
    display: flex;
    align-items: center;
    justify-content: #{placeholder_justify(state.alignment)};
    font-family: "Brut Grotesque Medium", sans-serif;
    font-size: #{@placeholder_size_cqw}cqw;
    line-height: 1;
    white-space: nowrap;
    pointer-events: none;
    """
  end

  defp placeholder_caret_style do
    """
    display: inline-block;
    width: 0.06em;
    height: 1.15em;
    background: currentColor;
    animation: bbparty-caret-blink 1.06s steps(1, end) infinite;
    """
  end

  defp placeholder_justify(:left), do: "flex-start"
  defp placeholder_justify(:center), do: "center"

  defp transform_origin(:left), do: "0% 50%"
  defp transform_origin(:center), do: "50% 50%"
end
