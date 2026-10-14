import { test } from 'node:test'
import assert from 'node:assert/strict'
import { ribbonBits, textToBits } from './ribbon.ts'

test('textToBits encodes ASCII MSB first', () => {
  assert.deepEqual(textToBits('A'), [0, 1, 0, 0, 0, 0, 0, 1])
})

test('textToBits encodes multi-byte UTF-8', () => {
  assert.equal(textToBits('é').length, 16)
  assert.deepEqual(textToBits('é').slice(0, 8), [1, 1, 0, 0, 0, 0, 1, 1])
})

test('textToBits of empty text is empty', () => {
  assert.deepEqual(textToBits(''), [])
})

test('ribbonBits cycles to the requested length', () => {
  const bits = ribbonBits('A', 20)
  assert.equal(bits.length, 20)
  assert.deepEqual(bits.slice(8, 16), textToBits('A'))
  assert.deepEqual(bits.slice(16), [0, 1, 0, 0])
})

test('ribbonBits truncates when text is longer than count', () => {
  assert.deepEqual(ribbonBits('A', 3), [0, 1, 0])
})

test('ribbonBits falls back to alternating bits on empty text', () => {
  assert.deepEqual(ribbonBits('', 5), [0, 1, 0, 1, 0])
})

test('ribbonBits returns nothing for non-positive counts', () => {
  assert.deepEqual(ribbonBits('A', 0), [])
  assert.deepEqual(ribbonBits('A', -3), [])
})
