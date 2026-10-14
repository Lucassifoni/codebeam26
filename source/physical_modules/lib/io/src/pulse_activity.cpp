#include "pulse_activity.h"

PulseActivity::PulseActivity(const Config &config)
    : fire_threshold_(config.fire_threshold == 0 ? 1 : config.fire_threshold),
      idle_decay_(config.idle_decay),
      accum_(0),
      report_(0) {}

bool PulseActivity::update(uint16_t pulses_this_tick) {
  if (pulses_this_tick == 0) {
    accum_ = accum_ > idle_decay_ ? static_cast<uint16_t>(accum_ - idle_decay_)
                                  : 0;
    return false;
  }

  const uint32_t summed = static_cast<uint32_t>(accum_) + pulses_this_tick;
  accum_ = summed > 0xFFFF ? 0xFFFF : static_cast<uint16_t>(summed);

  if (accum_ < fire_threshold_) {
    return false;
  }

  report_ = accum_ > 255 ? 255 : static_cast<uint8_t>(accum_);
  accum_ = 0;
  return true;
}
