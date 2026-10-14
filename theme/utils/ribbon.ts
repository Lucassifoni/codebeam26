/**
 * Pure helpers producing the 0/1 ribbon trailing the Turing-Express locomotive.
 *
 * The website draws random bits; slides need the same sequence in every window
 * (presenter, audience, export), so bits are derived from text instead.
 */

export type Bit = 0 | 1

const FALLBACK: Bit[] = [0, 1]

/**
 * Encodes `text` as UTF-8 and returns its bits, most significant bit first.
 */
export function textToBits(text: string): Bit[] {
  return Array.from(new TextEncoder().encode(text)).flatMap(byte =>
    Array.from({ length: 8 }, (_, i) => ((byte >> (7 - i)) & 1) as Bit),
  )
}

/**
 * Returns exactly `count` bits, cycling over the bits of `text`.
 * An empty text yields an alternating 0/1 pattern.
 */
export function ribbonBits(text: string, count: number): Bit[] {
  const source = textToBits(text)
  const pattern = source.length > 0 ? source : FALLBACK
  return Array.from({ length: Math.max(0, Math.floor(count)) }, (_, i) => pattern[i % pattern.length])
}
