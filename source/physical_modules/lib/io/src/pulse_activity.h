#pragma once

#include <stdint.h>

/// @file
/// Pure "activity on the ball" detector for the trackball trigger. It consumes a
/// per-tick pulse count (edges counted by an interrupt backend from the encoder
/// wheels' squared comparator outputs) and decides when the ball has been spun
/// enough to fire one Activity report. No direction, axis, or position — just
/// presence of motion. An accumulator sums incoming pulses and fires once it
/// crosses a threshold, then resets; ticks that see no motion shed `idle_decay`
/// pulses so stray single pulses (vibration) decay away instead of eventually
/// summing to a false trigger. No Arduino dependency; fully host-testable.

class PulseActivity {
 public:
  /// @var Config::fire_threshold accumulated pulses before one Activity fires.
  /// @var Config::idle_decay      pulses shed on each tick that sees no motion.
  struct Config {
    uint16_t fire_threshold;
    uint16_t idle_decay;
  };

  explicit PulseActivity(const Config &config);

  /// @brief Feed the pulse count since the last tick. Returns true when the
  ///        accumulator crosses the threshold this tick and fires, resetting it;
  ///        the fired count is then available from report(). A tick with zero
  ///        pulses only decays and never fires.
  bool update(uint16_t pulses_this_tick);

  /// @brief Saturated (0..255) accumulated pulse count captured at the last fire.
  uint8_t report() const { return report_; }

 private:
  uint16_t fire_threshold_;
  uint16_t idle_decay_;
  uint16_t accum_;
  uint8_t report_;
};
