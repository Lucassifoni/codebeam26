#pragma once

#include <stddef.h>
#include <stdint.h>

/// @file
/// A packed 1-D bool table over a caller-owned byte buffer. Bit `i` lives in
/// byte `i / 8`, position `i % 8` (little-endian within the byte). Pure and
/// dependency-free: this is the app-independent "arbitrary-width bool table"
/// that the shift-register buses move in and out, and the storage matrices use.

class BitView {
 public:
  /// @param bytes      caller-owned buffer of at least byte_count() bytes.
  /// @param bit_count  number of addressable bits.
  BitView(uint8_t *bytes, size_t bit_count);

  bool get(size_t index) const;
  void set(size_t index, bool on);
  void clear();

  size_t size() const { return bit_count_; }
  size_t byte_count() const { return (bit_count_ + 7) / 8; }
  uint8_t *bytes() { return bytes_; }
  const uint8_t *bytes() const { return bytes_; }

  /// @brief Number of bytes needed to hold `bit_count` bits.
  static constexpr size_t bytes_for(size_t bit_count) {
    return (bit_count + 7) / 8;
  }

 private:
  uint8_t *bytes_;
  size_t bit_count_;
};
