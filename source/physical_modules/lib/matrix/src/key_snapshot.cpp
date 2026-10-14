#include "key_snapshot.h"

#include <string.h>

namespace key_snapshot {

void pack(const KeyMatrix &keys, uint8_t *out, size_t out_bytes) {
  memset(out, 0, out_bytes);

  const size_t drives = keys.drives();
  const size_t senses = keys.senses();

  for (size_t drive = 0; drive < drives; drive++) {
    for (size_t sense = 0; sense < senses; sense++) {
      if (!keys.pressed(drive, sense)) {
        continue;
      }
      const size_t index = drive * senses + sense;
      const size_t byte = index >> 3;
      if (byte >= out_bytes) {
        continue;
      }
      out[byte] |= static_cast<uint8_t>(1u << (index & 7));
    }
  }
}

}  // namespace key_snapshot
