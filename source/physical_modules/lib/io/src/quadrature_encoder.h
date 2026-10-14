#pragma once

#include <stdint.h>

/// @file
/// Pure quadrature (Gray-code) decoder for one rotary encoder. The app samples
/// the two channel pins each poll and feeds their levels in; this unit tracks
/// the phase, rejects invalid and bounce transitions, and accumulates completed
/// detents. flush() returns the signed detent delta since the last flush and
/// resets the accumulator (partial, mid-detent motion is retained). No Arduino
/// dependency; fully host-testable.

class QuadratureEncoder {
 public:
  /// @param steps_per_detent valid quadrature transitions per mechanical detent
  ///        (4 for a typical full-cycle detented encoder).
  explicit QuadratureEncoder(uint8_t steps_per_detent = 4);

  /// @brief Feed the current levels of channels A and B.
  void update(bool a, bool b);

  /// @brief Signed detents accumulated since the last flush; resets to 0.
  int16_t flush();

 private:
  uint8_t steps_per_detent_;
  uint8_t prev_;  // last (A << 1 | B)
  bool have_prev_;
  int16_t sub_;      // sub-detent transition accumulator
  int16_t detents_;  // completed detents pending flush
};
