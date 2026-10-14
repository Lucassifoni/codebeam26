#pragma once

#include <stddef.h>
#include <stdint.h>

/// @file
/// Incremental frame reassembly: the receive counterpart of framing.h. Bytes
/// arrive one at a time off the wire; FrameReader accumulates the COBS body
/// until a 0x00 delimiter, then decodes a complete frame. Pure logic, no
/// hardware dependency, so it is unit-testable on the host. Buffers are
/// caller-owned to keep allocation out of the library.

class FrameReader {
 public:
  /// @param encoded   scratch for the accumulating COBS body.
  /// @param encoded_capacity  size of `encoded`; frames whose body exceeds this
  ///        are dropped (resynchronised at the next delimiter).
  /// @param decoded   buffer receiving the decoded frame.
  /// @param decoded_capacity  size of `decoded`; must be >= encoded_capacity.
  FrameReader(uint8_t *encoded, size_t encoded_capacity, uint8_t *decoded,
              size_t decoded_capacity);

  /// @brief Feed one byte from the wire.
  /// @return decoded frame length (> 0) when `byte` is a delimiter that
  ///         completes a valid, non-empty frame; 0 otherwise. When > 0 is
  ///         returned, the decoded bytes are available via frame().
  size_t push(uint8_t byte);

  /// @brief Decoded frame bytes; valid only immediately after push() returns > 0.
  const uint8_t *frame() const { return decoded_; }

 private:
  uint8_t *encoded_;
  size_t encoded_capacity_;
  size_t encoded_length_;
  uint8_t *decoded_;
  size_t decoded_capacity_;
  bool overflow_;
};
