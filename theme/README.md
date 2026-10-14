# slidev-theme-turing-express

Local Slidev theme with the Turing-Express identity. The identity itself is documented in `design.md` in the turing-express.fr repository.

Use it from a deck's headmatter with a relative path:

```yaml
theme: ../theme
```

- `layouts/cover.vue`: title slide with the loco ribbon under the `h1`. The `ribbon` frontmatter key seeds the bits.
- `layouts/end.vue`: closing slide with the ribbon below the content.
- `layouts/media.vue`: full-bleed photos/videos from frontmatter, see below.
- `components/MediaGrid.vue` / `components/Media.vue`: the same rendering, usable inside any layout.
- `components/Haystack.vue`: images piled at seeded random positions and rotations, see below.
- `components/Loco.vue`: `<Loco text="..." :count="n" :animate="false" />`, usable on any slide.
- `pages/kitchen-sink.md`: style reference, imported with `src: ../theme/pages/kitchen-sink.md`.
- Utility classes: `.te-lead`, `.te-muted`, `.te-small`, `.te-panel`, `.te-ref`.

## Media slides

```yaml
---
layout: media
split: 1/3 2/3          # optional: 1/2 1/2, 1/3 1/3 1/3, 2/3 1/3, "2 1"... default is equal columns
fit: cover              # optional default for all items: cover | contain
filter: grayscale(1)    # optional CSS filter for all items
gap: 0                  # optional, defaults to 6px
loop: false             # optional default for all videos: play once and hold the last frame
media:
  - img_5233.webp       # bare names resolve to the shared media/ directory
  - src: img_4973.mp4   # videos (mp4/webm/mov/m4v/ogv) play muted and looped while the slide is shown
    loop: true          # per-item override
    fit: contain
    position: center top
    filter: none        # per-item override, e.g. brightness(1.2) saturate(0.8)
    caption: First prototype
---
```

Shorthand: `media: img_5233.webp` (1/1) or `media: [a.webp, b.mp4]` (1/2 1/2). Items beyond the number of `split` columns wrap onto new rows, so `split: 1/2 1/2` with four items gives a 2×2 grid. Markdown content on the slide (a title, for instance) shows above the grid, and the slide keeps its usual padding. Inside other layouts, use `<Media src="img_4973.mp4" />` or `<MediaGrid :media="['a.webp', 'b.mp4']" split="1/3 2/3" />`.

## Haystack slides

```md
---
layout: none
---

<Haystack :items="['stickers/a.png', 'stickers/b.png']" width="360px" :max-rotation="45" seed="haystack" background="#000" :duration="8" />
```

`items` resolve against the shared `media/` directory and later items land on top. The pile fills the slide and is clipped at its edges. `width` is in slide canvas pixels (the canvas is 980px wide by default). The arrangement only depends on `seed` and the number of items, so it is the same in every window and export. `duration` is the time in seconds over which the pile builds up from the bare background each time the slide is shown, each item popping in place without a transition, once every image is loaded and decoded; `0` shows it complete at once.

Tests for the pure helpers (ribbon bits, media parsing, haystack placement) run with `npm test` (Node 24 as pinned in `.tool-versions`, no dependencies).
