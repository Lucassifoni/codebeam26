import { test } from 'node:test'
import assert from 'node:assert/strict'
import { gridColumns, mediaKind, normalizeMedia, parseSplit, resolveMediaSrc } from './media.ts'

test('mediaKind detects videos by extension, case-insensitively', () => {
  assert.equal(mediaKind('img_4973.mp4'), 'video')
  assert.equal(mediaKind('clip.MOV'), 'video')
  assert.equal(mediaKind('/media/a.webm?v=2#t=3'), 'video')
})

test('mediaKind defaults to image', () => {
  assert.equal(mediaKind('img_5233.webp'), 'image')
  assert.equal(mediaKind('noext'), 'image')
  assert.equal(mediaKind('https://host/a.mp4.png'), 'image')
})

test('resolveMediaSrc maps bare names to the media directory', () => {
  assert.equal(resolveMediaSrc('img_5233.webp'), '/media/img_5233.webp')
  assert.equal(resolveMediaSrc('sub/a.webp'), '/media/sub/a.webp')
})

test('resolveMediaSrc prefixes absolute paths with the base', () => {
  assert.equal(resolveMediaSrc('/favicon.png'), '/favicon.png')
  assert.equal(resolveMediaSrc('/favicon.png', '/talk/'), '/talk/favicon.png')
  assert.equal(resolveMediaSrc('a.webp', '/talk'), '/talk/media/a.webp')
})

test('resolveMediaSrc keeps URLs untouched', () => {
  assert.equal(resolveMediaSrc('https://example.com/a.png', '/talk/'), 'https://example.com/a.png')
  assert.equal(resolveMediaSrc('//cdn.example.com/a.png'), '//cdn.example.com/a.png')
  assert.equal(resolveMediaSrc('data:image/png;base64,AA'), 'data:image/png;base64,AA')
})

test('normalizeMedia accepts a single string', () => {
  assert.deepEqual(normalizeMedia('a.mp4'), [
    { src: '/media/a.mp4', kind: 'video', fit: 'cover', position: 'center', loop: true },
  ])
})

test('normalizeMedia mixes strings and objects and applies defaults', () => {
  const items = normalizeMedia(
    ['a.webp', { src: 'b.mp4', fit: 'cover', position: 'top', caption: 'B' }],
    { fit: 'contain' },
  )
  assert.deepEqual(items, [
    { src: '/media/a.webp', kind: 'image', fit: 'contain', position: 'center', loop: true },
    { src: '/media/b.mp4', kind: 'video', fit: 'cover', position: 'top', loop: true, caption: 'B' },
  ])
})

test('normalizeMedia applies the slide filter unless an item overrides it', () => {
  const items = normalizeMedia(['a.webp', { src: 'b.mp4', filter: 'none' }], { filter: 'grayscale(1)' })
  assert.equal(items[0].filter, 'grayscale(1)')
  assert.equal(items[1].filter, 'none')
})

test('normalizeMedia loops by default and lets the slide or an item turn it off', () => {
  assert.equal(normalizeMedia('a.mp4')[0].loop, true)
  assert.equal(normalizeMedia('a.mp4', { loop: false })[0].loop, false)
  const items = normalizeMedia(['a.mp4', { src: 'b.mp4', loop: true }, { src: 'c.mp4', loop: false }], { loop: false })
  assert.deepEqual(items.map(item => item.loop), [false, true, false])
  assert.equal(normalizeMedia({ src: 'a.mp4', loop: false })[0].loop, false)
})

test('normalizeMedia omits filter when none is given', () => {
  assert.equal('filter' in normalizeMedia('a.webp')[0], false)
})

test('normalizeMedia of nothing is empty', () => {
  assert.deepEqual(normalizeMedia(undefined), [])
  assert.deepEqual(normalizeMedia(null), [])
  assert.deepEqual(normalizeMedia([]), [])
})

test('parseSplit reads fractions, integers and decimals', () => {
  assert.deepEqual(parseSplit('1/2 1/2'), [0.5, 0.5])
  assert.deepEqual(parseSplit('1/3, 2/3'), [1 / 3, 2 / 3])
  assert.deepEqual(parseSplit('2 | 1'), [2, 1])
  assert.deepEqual(parseSplit('1.5 1'), [1.5, 1])
  assert.deepEqual(parseSplit([1, 2]), [1, 2])
})

test('parseSplit rejects invalid or empty input', () => {
  assert.equal(parseSplit(undefined), null)
  assert.equal(parseSplit(''), null)
  assert.equal(parseSplit('1/3 abc'), null)
  assert.equal(parseSplit('0 1'), null)
  assert.equal(parseSplit('1/0 1'), null)
  assert.equal(parseSplit('-1 1'), null)
})

test('gridColumns uses equal columns without a split', () => {
  assert.equal(gridColumns(null, 1), 'minmax(0, 1fr)')
  assert.equal(gridColumns(null, 3), 'minmax(0, 1fr) minmax(0, 1fr) minmax(0, 1fr)')
  assert.equal(gridColumns(null, 0), 'minmax(0, 1fr)')
})

test('gridColumns follows the split regardless of item count', () => {
  assert.equal(gridColumns([1 / 3, 2 / 3], 2), 'minmax(0, 0.3333fr) minmax(0, 0.6667fr)')
  assert.equal(gridColumns([1, 1], 4), 'minmax(0, 1fr) minmax(0, 1fr)')
})
