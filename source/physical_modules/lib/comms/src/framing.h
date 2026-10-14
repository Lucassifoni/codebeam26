#pragma once

#include <stddef.h>
#include <stdint.h>

#include "cobs.h"

/// @file
/// Frame construction on top of COBS. A frame is the COBS-encoded payload
/// followed by a single 0x00 delimiter byte. Because COBS guarantees the
/// encoded body contains no 0x00, the delimiter unambiguously marks the end of
/// a frame for the receiver. Pure logic, host-testable.

/// @brief Worst-case number of bytes for a complete frame (encoded payload plus
///        the trailing 0x00 delimiter).
constexpr size_t frame_encoded_bounds(size_t length) {
  return cobs_encode_bounds(length) + 1;
}

/// @brief Build a complete delimited COBS frame for `payload` into `dst`.
/// @param payload  bytes to send (may contain 0x00).
/// @param length   number of payload bytes.
/// @param dst      output buffer, must hold at least frame_encoded_bounds(length) bytes.
/// @return total number of bytes written, including the trailing delimiter.
size_t frame_encode(const uint8_t *payload, size_t length, uint8_t *dst);
