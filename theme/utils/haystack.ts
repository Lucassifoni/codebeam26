/**
 * Pure helpers scattering items into a pile for the `Haystack` component.
 *
 * Placements are derived from a seed rather than `Math.random`, so the pile is
 * identical in every window (presenter, audience, export) and across reloads.
 */

export interface HaystackPlacement {
  /** Horizontal position of the item center, as a fraction of the container width. */
  x: number
  /** Vertical position of the item center, as a fraction of the container height. */
  y: number
  /** Rotation in degrees, within `[-maxRotation, maxRotation]`. */
  rotation: number
}

export interface HaystackOptions {
  seed?: string
  maxRotation?: number
}

/**
 * Returns a deterministic generator of numbers in `[0, 1)` for `seed`
 * (xmur3 string hash feeding a mulberry32 generator).
 */
export function seededRandom(seed: string): () => number {
  let h = 1779033703 ^ seed.length
  for (const char of seed) {
    h = Math.imul(h ^ char.codePointAt(0)!, 3432918353)
    h = (h << 13) | (h >>> 19)
  }
  h = Math.imul(h ^ (h >>> 16), 2246822507)
  h = Math.imul(h ^ (h >>> 13), 3266489909)
  let state = (h ^ (h >>> 16)) >>> 0

  return () => {
    state = (state + 0x6D2B79F5) >>> 0
    let t = state
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

/**
 * Returns `count` placements with centers spread uniformly over the container
 * and rotations spread uniformly over `[-maxRotation, maxRotation]` degrees.
 * Growing `count` keeps the placements of the previous items unchanged.
 */
export function haystackLayout(count: number, options: HaystackOptions = {}): HaystackPlacement[] {
  const random = seededRandom(options.seed ?? 'haystack')
  const maxRotation = Math.abs(options.maxRotation ?? 45)
  const length = Number.isFinite(count) ? Math.max(0, Math.floor(count)) : 0

  return Array.from({ length }, () => ({
    x: round(random()),
    y: round(random()),
    rotation: round((random() * 2 - 1) * maxRotation),
  }))
}

/**
 * Returns the delay in milliseconds between two items so that `count` items
 * finish appearing over `duration` seconds. Zero means no staggering.
 */
export function haystackStep(count: number, duration: number): number {
  const valid = Number.isFinite(duration) && duration > 0 && count > 1
  return valid ? round((duration * 1000) / (count - 1)) : 0
}

function round(value: number): number {
  return Math.round(value * 10000) / 10000
}
