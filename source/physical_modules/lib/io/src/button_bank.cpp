#include "button_bank.h"

#include <string.h>

ButtonBank::ButtonBank(InputBus &bus, uint8_t debounce_scans,
                       uint8_t *stable_bits, uint8_t *counters)
    : bus_(bus),
      debounce_scans_(debounce_scans),
      stable_(stable_bits),
      counters_(counters) {}

bool ButtonBank::step(ButtonEventHandler on_event, void *ctx) {
  const size_t count = bus_.width();
  if ((count + 7) / 8 > kMaxBytes) {
    return false;
  }

  uint8_t reading[kMaxBytes];
  bus_.read(reading);

  bool changed = false;
  for (size_t i = 0; i < count; i++) {
    const uint8_t mask = static_cast<uint8_t>(1u << (i & 7));
    const bool raw = (reading[i >> 3] & mask) != 0;
    const bool stable = (stable_[i >> 3] & mask) != 0;

    if (raw == stable) {
      counters_[i] = 0;
      continue;
    }

    if (++counters_[i] >= debounce_scans_) {
      counters_[i] = 0;
      if (raw) {
        stable_[i >> 3] |= mask;
      } else {
        stable_[i >> 3] &= static_cast<uint8_t>(~mask);
      }
      changed = true;
      if (on_event != nullptr) {
        const ButtonEvent event{static_cast<uint16_t>(i), raw};
        on_event(event, ctx);
      }
    }
  }
  return changed;
}

bool ButtonBank::pressed(size_t index) const {
  const uint8_t mask = static_cast<uint8_t>(1u << (index & 7));
  return (stable_[index >> 3] & mask) != 0;
}
