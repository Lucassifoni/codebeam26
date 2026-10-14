#pragma once

#include <stddef.h>
#include <stdint.h>

/// @file
/// Consistent Overhead Byte Stuffing (COBS) codec.
///
/// Pure, dependency-free logic so it can be unit-tested on the host. The
/// encoder removes every 0x00 byte from the payload, which lets a single 0x00
/// serve as an unambiguous frame delimiter on the wire (see framing.h).

/// @brief Worst-case number of bytes produced when encoding `length` payload
///        bytes, excluding any frame delimiter.
constexpr size_t cobs_encode_bounds(size_t length) {
  return length + length / 254 + 1;
}

/// @brief Worst-case number of bytes produced when decoding `length` encoded
///        bytes. Decoding never expands, so an output buffer this large always
///        suffices.
constexpr size_t cobs_decode_bounds(size_t length) {
  return length == 0 ? 0 : length - 1;
}

/// @brief COBS-encode `length` bytes from `src` into `dst`.
/// @param src     payload to encode (may contain 0x00 bytes).
/// @param length  number of payload bytes.
/// @param dst     output buffer, must hold at least cobs_encode_bounds(length) bytes.
/// @return number of bytes written to `dst`.
size_t cobs_encode(const uint8_t *src, size_t length, uint8_t *dst);

/// @brief COBS-decode `length` bytes from `src` into `dst`.
/// @param src     encoded bytes (must not contain the 0x00 frame delimiter).
/// @param length  number of encoded bytes.
/// @param dst     output buffer, must hold at least cobs_decode_bounds(length) bytes.
/// @return number of bytes written to `dst`, or 0 if the input is malformed.
size_t cobs_decode(const uint8_t *src, size_t length, uint8_t *dst);
