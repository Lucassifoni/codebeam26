/**
 * Pure helpers turning the terse `media` / `split` frontmatter of the `media`
 * layout (and the `MediaGrid` / `Media` components) into render-ready data.
 */

export type MediaKind = 'image' | 'video'

export type MediaFit = 'cover' | 'contain'

/**
 * A media entry as written in slides: either a bare string or an object.
 */
export type MediaInput = string | {
  src: string
  fit?: MediaFit
  position?: string
  filter?: string
  caption?: string
  loop?: boolean
}

export interface MediaItem {
  src: string
  kind: MediaKind
  fit: MediaFit
  position: string
  loop: boolean
  filter?: string
  caption?: string
}

const VIDEO_EXTENSIONS = new Set(['mp4', 'webm', 'mov', 'm4v', 'ogv'])

const EXTERNAL = /^(?:[a-z][a-z\d+.-]*:|\/\/)/i

/**
 * Detects a video from the file extension, ignoring query strings and fragments.
 * Anything else is treated as an image.
 */
export function mediaKind(src: string): MediaKind {
  const path = src.split(/[?#]/, 1)[0]
  const dot = path.lastIndexOf('.')
  const ext = dot === -1 ? '' : path.slice(dot + 1).toLowerCase()
  return VIDEO_EXTENSIONS.has(ext) ? 'video' : 'image'
}

/**
 * Resolves a slide-level `src` to a URL.
 *
 * - URLs (`https:`, `data:`, `//host`) are returned untouched.
 * - Absolute paths (`/media/a.webp`) are prefixed with `base`.
 * - Anything else is a path relative to the shared `media/` directory.
 */
export function resolveMediaSrc(src: string, base = '/'): string {
  const root = base.endsWith('/') ? base : `${base}/`
  if (EXTERNAL.test(src))
    return src
  if (src.startsWith('/'))
    return root + src.slice(1)
  return `${root}media/${src}`
}

/**
 * Normalizes one entry or a list of entries into `MediaItem`s.
 * `options` apply when an entry does not specify `fit`, `position`, `filter` or `loop`.
 * `filter` is any CSS `filter` value, e.g. `grayscale(1) contrast(1.2)`.
 * `loop` only matters for videos and defaults to `true`; a video that does not
 * loop holds its last frame.
 */
export function normalizeMedia(
  input: MediaInput | MediaInput[] | undefined | null,
  options: { base?: string, fit?: MediaFit, position?: string, filter?: string, loop?: boolean } = {},
): MediaItem[] {
  const list = input == null ? [] : Array.isArray(input) ? input : [input]
  const fit = options.fit ?? 'cover'
  const position = options.position ?? 'center'
  const loop = options.loop ?? true

  return list.map((entry) => {
    const item: Exclude<MediaInput, string> = typeof entry === 'string' ? { src: entry } : entry
    const filter = item.filter ?? options.filter
    return {
      src: resolveMediaSrc(item.src, options.base),
      kind: mediaKind(item.src),
      fit: item.fit ?? fit,
      position: item.position ?? position,
      loop: item.loop ?? loop,
      ...(filter ? { filter } : {}),
      ...(item.caption ? { caption: item.caption } : {}),
    }
  })
}

/**
 * Parses a column split such as `"1/3 2/3"`, `"1/2 1/2"` or `"2 1"` into weights.
 * Tokens are separated by spaces, commas or `|`. Returns `null` when a token is
 * not a positive number or fraction, so callers can fall back to equal columns.
 */
export function parseSplit(split: string | number[] | undefined | null): number[] | null {
  if (split == null)
    return null
  const tokens = Array.isArray(split) ? split.map(String) : split.split(/[\s,|]+/).filter(Boolean)
  if (tokens.length === 0)
    return null

  const weights = tokens.map(parseWeight)
  return weights.every(w => w !== null) ? weights as number[] : null
}

function parseWeight(token: string): number | null {
  const match = /^(\d+(?:\.\d+)?)(?:\/(\d+(?:\.\d+)?))?$/.exec(token.trim())
  if (!match)
    return null
  const value = Number(match[1]) / (match[2] === undefined ? 1 : Number(match[2]))
  return Number.isFinite(value) && value > 0 ? value : null
}

/**
 * Returns the CSS `grid-template-columns` value for `count` items.
 * Without a valid split, items share the width equally on a single row.
 * With a split, extra items wrap onto new rows following the same columns.
 */
export function gridColumns(split: number[] | null, count: number): string {
  const weights = split ?? Array.from({ length: Math.max(1, count) }, () => 1)
  return weights.map(w => `minmax(0, ${round(w)}fr)`).join(' ')
}

function round(value: number): number {
  return Math.round(value * 10000) / 10000
}
