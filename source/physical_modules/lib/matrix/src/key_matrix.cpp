#include "key_matrix.h"

#include <string.h>

KeyMatrix::KeyMatrix(OutputBus &drive, InputBus &sense, uint8_t release_scans,
                     uint8_t *stable_bits, uint8_t *counters,
                     uint8_t press_scans)
    : drive_(drive),
      sense_(sense),
      release_scans_(release_scans),
      press_scans_(press_scans < 1 ? 1 : press_scans),
      stable_(stable_bits),
      counters_(counters) {}

void KeyMatrix::scan(KeyEventHandler on_event, void *ctx) {
  const size_t drive_count = drive_.width();
  const size_t sense_count = sense_.width();
  const size_t drive_bytes = (drive_count + 7) / 8;
  if (drive_bytes > kMaxAxisBytes || (sense_count + 7) / 8 > kMaxAxisBytes) {
    return;
  }

  uint8_t one_hot[kMaxAxisBytes];
  uint8_t reading[kMaxAxisBytes];

  for (size_t d = 0; d < drive_count; d++) {
    memset(one_hot, 0, drive_bytes);
    one_hot[d >> 3] = static_cast<uint8_t>(1u << (d & 7));
    drive_.write(one_hot);

    if (settle_ != nullptr) {
      settle_();
    }
    sense_.read(reading);

    for (size_t s = 0; s < sense_count; s++) {
      const bool raw = (reading[s >> 3] >> (s & 7)) & 1u;
      const size_t k = d * sense_count + s;

      const uint8_t mask = static_cast<uint8_t>(1u << (k & 7));
      const bool stable = (stable_[k >> 3] & mask) != 0;

      if (!stable) {
        // Press: `press_scans` consecutive closed readings, 1 by default so the
        // first one commits. Above 1 this rejects a smear narrower than the run.
        if (!raw) {
          counters_[k] = 0;
          continue;
        }

        if (++counters_[k] < press_scans_) {
          continue;
        }

        stable_[k >> 3] |= mask;
        counters_[k] = 0;
      } else {
        // Held: a single open reading proves nothing, because a marginal
        // contact re-opens repeatedly while the key is genuinely down. Only an
        // uninterrupted run of them is a release, and any closed reading in
        // between restarts the run.
        if (raw) {
          counters_[k] = 0;
          continue;
        }

        if (++counters_[k] < release_scans_) {
          continue;
        }

        stable_[k >> 3] &= static_cast<uint8_t>(~mask);
        counters_[k] = 0;
      }

      if (on_event != nullptr) {
        const KeyEvent event{static_cast<uint16_t>(d), static_cast<uint16_t>(s),
                             raw};
        on_event(event, ctx);
      }
    }
  }
}

bool KeyMatrix::pressed(size_t drive, size_t sense) const {
  const size_t k = key_index(drive, sense);
  return (stable_[k >> 3] >> (k & 7)) & 1u;
}
