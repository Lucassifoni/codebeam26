#pragma once

#include <stddef.h>
#include <stdint.h>

#include "key_matrix.h"

/// @file
/// Packs a KeyMatrix's committed table into the flat bitmap a Snapshot carries.
///
/// A panel of latching switches sits with most of its contacts closed, so the
/// state a board comes up in is not a sequence of presses — it is a picture.
/// KeyMatrix already holds that picture; this is the one place that turns it
/// into bytes, kept out of the sketch so the layout can be tested against the
/// host codec's vectors without an Arduino.
///
/// Bit index is `drive * senses + sense`, matching KeyMatrix's own indexing and
/// the host's decode. Channel 0 is the low bit of the first byte.

namespace key_snapshot {

/// @brief Bytes a snapshot of this matrix occupies.
constexpr size_t bytes(size_t drives, size_t senses) {
  return (drives * senses + 7) / 8;
}

/// @brief Write the committed table into `out`, which must be at least
///        bytes(drives, senses) long. A shorter buffer is filled as far as it
///        goes and the rest of the table is dropped, rather than overrunning.
void pack(const KeyMatrix &keys, uint8_t *out, size_t out_bytes);

}  // namespace key_snapshot
