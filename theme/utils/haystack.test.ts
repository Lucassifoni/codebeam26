import { test } from 'node:test'
import assert from 'node:assert/strict'
import { haystackLayout, haystackStep, seededRandom } from './haystack.ts'

test('seededRandom yields the same sequence for the same seed', () => {
  const a = seededRandom('stickers')
  const b = seededRandom('stickers')
  assert.deepEqual(Array.from({ length: 20 }, a), Array.from({ length: 20 }, b))
})

test('seededRandom yields different sequences for different seeds', () => {
  const a = Array.from({ length: 5 }, seededRandom('a'))
  const b = Array.from({ length: 5 }, seededRandom('b'))
  assert.notDeepEqual(a, b)
})

test('seededRandom stays within [0, 1) and is not degenerate', () => {
  const values = Array.from({ length: 2000 }, seededRandom(''))
  assert.ok(values.every(v => v >= 0 && v < 1))
  const mean = values.reduce((sum, v) => sum + v, 0) / values.length
  assert.ok(mean > 0.45 && mean < 0.55)
  assert.ok(new Set(values).size > 1990)
})

test('haystackLayout returns one placement per item', () => {
  assert.equal(haystackLayout(323).length, 323)
  assert.equal(haystackLayout(2.9).length, 2)
})

test('haystackLayout of nothing is empty', () => {
  assert.deepEqual(haystackLayout(0), [])
  assert.deepEqual(haystackLayout(-3), [])
  assert.deepEqual(haystackLayout(Number.NaN), [])
})

test('haystackLayout is deterministic for a seed and varies across seeds', () => {
  assert.deepEqual(haystackLayout(50, { seed: 'x' }), haystackLayout(50, { seed: 'x' }))
  assert.notDeepEqual(haystackLayout(50, { seed: 'x' }), haystackLayout(50, { seed: 'y' }))
})

test('haystackLayout keeps existing placements when the count grows', () => {
  assert.deepEqual(haystackLayout(60, { seed: 'x' }).slice(0, 50), haystackLayout(50, { seed: 'x' }))
})

test('haystackLayout keeps centers inside the container and rotations within bounds', () => {
  const placements = haystackLayout(1000, { maxRotation: 30 })
  assert.ok(placements.every(p => p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1))
  assert.ok(placements.every(p => Math.abs(p.rotation) <= 30))
  assert.ok(placements.some(p => p.rotation < -15))
  assert.ok(placements.some(p => p.rotation > 15))
})

test('haystackLayout spreads centers over the four quadrants', () => {
  const placements = haystackLayout(400)
  const quadrants = new Set(placements.map(p => `${p.x < 0.5}:${p.y < 0.5}`))
  assert.equal(quadrants.size, 4)
})

test('haystackLayout treats maxRotation as a magnitude', () => {
  assert.deepEqual(haystackLayout(10, { maxRotation: -20 }), haystackLayout(10, { maxRotation: 20 }))
  assert.ok(haystackLayout(10, { maxRotation: 0 }).every(p => p.rotation === 0))
})

test('haystackStep spreads the items over the duration', () => {
  assert.equal(haystackStep(11, 2), 200)
  assert.equal(haystackStep(323, 8), 24.8447)
})

test('haystackStep is zero without a positive duration or enough items', () => {
  assert.equal(haystackStep(323, 0), 0)
  assert.equal(haystackStep(323, -1), 0)
  assert.equal(haystackStep(323, Number.NaN), 0)
  assert.equal(haystackStep(1, 8), 0)
  assert.equal(haystackStep(0, 8), 0)
})
