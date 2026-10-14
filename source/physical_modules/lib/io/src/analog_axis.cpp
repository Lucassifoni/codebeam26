#include "analog_axis.h"

AnalogAxis::AnalogAxis(const Config &config)
    : cfg_(config), accum_(0), value_(0), seeded_(false) {}

void AnalogAxis::reset(uint16_t raw) {
  accum_ = static_cast<uint32_t>(raw) << cfg_.ema_shift;
  seeded_ = true;
  value_ = calibrate(filtered());
}

int16_t AnalogAxis::update(uint16_t raw) {
  if (!seeded_) {
    accum_ = static_cast<uint32_t>(raw) << cfg_.ema_shift;
    seeded_ = true;
  } else {
    accum_ = accum_ - (accum_ >> cfg_.ema_shift) + raw;
  }
  value_ = calibrate(filtered());
  return value_;
}

int16_t AnalogAxis::calibrate(uint16_t filtered) const {
  const int32_t center = cfg_.center;
  const int32_t dz = cfg_.deadzone;
  const int32_t range = cfg_.out_range;
  const int32_t x = filtered;

  if (x >= center - dz && x <= center + dz) {
    return 0;
  }

  if (x > center) {
    const int32_t span = static_cast<int32_t>(cfg_.max) - center - dz;
    if (span <= 0) {
      return static_cast<int16_t>(range);
    }
    const int32_t out = (x - center - dz) * range / span;
    return static_cast<int16_t>(out > range ? range : out);
  }

  const int32_t span = center - static_cast<int32_t>(cfg_.min) - dz;
  if (span <= 0) {
    return static_cast<int16_t>(-range);
  }
  const int32_t out = (center - dz - x) * range / span;
  return static_cast<int16_t>(-(out > range ? range : out));
}
