#include "analog_edges.h"

namespace {

constexpr uint8_t kMinHysteresisPct = 1;
constexpr uint8_t kMaxHysteresisPct = 50;

uint8_t clamp_pct(uint8_t pct) {
  if (pct < kMinHysteresisPct) {
    return kMinHysteresisPct;
  }
  return pct > kMaxHysteresisPct ? kMaxHysteresisPct : pct;
}

}  // namespace

AnalogEdges::AnalogEdges(const Config &config)
    : min_span_(config.min_span),
      decay_(config.decay),
      hysteresis_pct_(clamp_pct(config.hysteresis_pct)),
      low_(0),
      high_(0),
      // A line at rest sits at its high level, so starting high means the first
      // real pulse of a spin is counted rather than swallowed. If a spin happens
      // to start from the low level, the state resynchronises on the first
      // crossing and the count is short by one — which the activity threshold
      // absorbs.
      level_(true),
      seeded_(false) {}

uint16_t AnalogEdges::span() const {
  return seeded_ ? static_cast<uint16_t>(high_ - low_) : 0;
}

bool AnalogEdges::update(uint16_t sample) {
  if (!seeded_) {
    low_ = sample;
    high_ = sample;
    seeded_ = true;
    return false;
  }

  // Each extreme jumps to meet a sample beyond it and leaks toward one inside
  // it, never past it — so the envelope tracks the swing without a sample ever
  // landing outside the band it defines.
  if (sample > high_) {
    high_ = sample;
  } else {
    high_ = (high_ - sample) > decay_ ? static_cast<uint16_t>(high_ - decay_)
                                      : sample;
  }

  if (sample < low_) {
    low_ = sample;
  } else {
    low_ = (sample - low_) > decay_ ? static_cast<uint16_t>(low_ + decay_)
                                    : sample;
  }

  const uint16_t swing = static_cast<uint16_t>(high_ - low_);
  if (swing < min_span_) {
    return false;
  }

  const uint16_t mid = static_cast<uint16_t>(low_ + swing / 2);
  const uint16_t band = static_cast<uint16_t>(
      (static_cast<uint32_t>(swing) * hysteresis_pct_) / 100);

  if (level_ && sample < static_cast<uint16_t>(mid - band)) {
    level_ = false;
    return true;
  }

  if (!level_ && sample > static_cast<uint16_t>(mid + band)) {
    level_ = true;
  }

  return false;
}
