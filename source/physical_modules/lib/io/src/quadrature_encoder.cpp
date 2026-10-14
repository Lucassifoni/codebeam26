#include "quadrature_encoder.h"

namespace {

/// Indexed by (prev << 2 | cur), where prev/cur = (A << 1 | B). +1 for a valid
/// CW step, -1 for CCW, 0 for no-change and for invalid (both channels flipped
/// at once) transitions. CW is the Gray sequence 00 -> 01 -> 11 -> 10 -> 00.
constexpr int8_t kStep[16] = {
    0, +1, -1, 0,   // prev 00
    -1, 0, 0, +1,   // prev 01
    +1, 0, 0, -1,   // prev 10
    0, -1, +1, 0,   // prev 11
};

}  // namespace

QuadratureEncoder::QuadratureEncoder(uint8_t steps_per_detent)
    : steps_per_detent_(steps_per_detent == 0 ? 1 : steps_per_detent),
      prev_(0),
      have_prev_(false),
      sub_(0),
      detents_(0) {}

void QuadratureEncoder::update(bool a, bool b) {
  const uint8_t cur = static_cast<uint8_t>((a ? 2 : 0) | (b ? 1 : 0));
  if (!have_prev_) {
    prev_ = cur;
    have_prev_ = true;
    return;
  }

  const int8_t step = kStep[(prev_ << 2) | cur];
  prev_ = cur;
  if (step == 0) {
    return;
  }

  sub_ = static_cast<int16_t>(sub_ + step);
  const int16_t per = steps_per_detent_;
  while (sub_ >= per) {
    sub_ = static_cast<int16_t>(sub_ - per);
    detents_++;
  }
  while (sub_ <= -per) {
    sub_ = static_cast<int16_t>(sub_ + per);
    detents_--;
  }
}

int16_t QuadratureEncoder::flush() {
  const int16_t delta = detents_;
  detents_ = 0;
  return delta;
}
