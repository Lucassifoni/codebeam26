---
class: te-sink
---

# Kitchen sink: type

<div class="grid grid-cols-2 gap-x-12">
<div>

<p class="te-ref"># h1 · Droulers Clarendon 2.3em</p>
<h1 class="!mb-3">Title h1</h1>

<p class="te-ref">## h2 · 1.6em</p>
<h2 class="!mt-0">Section h2</h2>

<p class="te-ref">### h3 · 1.25em · ink</p>
<h3 class="!mt-0">Subsection h3</h3>

<p class="te-ref">Loco ribbon · Droulers</p>
<Loco text="BEAM" :count="12" :animate="false" />

</div>
<div>

<p class="te-ref">.te-lead · 1.35em</p>
<p class="te-lead !mt-0">A lead paragraph that sets the tone.</p>

<p class="te-ref">body · Brut Grotesque 1.1rem · **strong** · [link] · `code`</p>
<p class="!mt-0">Body text with <strong>strong</strong> as accent, <a href="#">a link</a> and <code>inline code</code>.</p>

<p class="te-ref">.te-muted / .te-small</p>
<p class="te-muted !mt-0">Muted secondary text.</p>
<p class="te-small !mt-0">Small print, captions, sources.</p>

<p class="te-ref">.te-panel</p>
<div class="te-panel">Highlighted panel, like the website contact block.</div>

</div>
</div>

---
class: te-sink
---

# Kitchen sink: blocks

<div class="grid grid-cols-2 gap-x-12">
<div>

<p class="te-ref">```elixir</p>

```elixir
defmodule Panel.Knob do
  use GenServer

  def handle_info({:turn, d}, s) do
    {:noreply, %{s | value: s.value + d}}
  end
end
```

<p class="te-ref">- list / 1. ordered</p>

- Pure core
- Physical edge
  - nested item

1. First step
2. Second step

</div>
<div>

<p class="te-ref">> blockquote</p>

> Make it work, make it right, make it fast.

<p class="te-ref">| table |</p>

| Layer    | Tool   |
| -------- | ------ |
| Logic    | Elixir |
| Firmware | Nerves |

<p class="te-ref">layouts</p>

<p class="te-small !mt-0">cover · section · end · statement · fact · quote · media · default</p>

</div>
</div>

---
layout: media
media: img_5233.webp
---

---
layout: media
media: [img_4636.webp, img_4973.mp4]
---

---
layout: media
split: 1/3 2/3
media:
  - img_4643.webp
  - src: img_4668.mp4
    caption: Muted, looped, plays only while the slide is shown
---

# Kitchen sink: media with a title

---
layout: media
fit: contain
filter: grayscale(1) contrast(1.2)
media: [img_4644.webp, img_4645.webp, {src: img_4646.webp, filter: none}]
---
