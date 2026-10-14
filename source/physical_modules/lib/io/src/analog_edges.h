#pragma once

#include <stdint.h>

/// @file
/// Pure edge counter for a logic line that does not reach the rails. The
/// trackball's encoder wheels only partially occlude their IR source, so each
/// wheel's output swings between the high rail and *some* lower level rather
/// than between the rails — a level a digital input reads as a constant HIGH, so
/// there is no edge to interrupt on. Sampling the line with the ADC and finding
/// the crossings here recovers the pulse train the interrupt could not see.
///
/// The low level is unknown, differs per wheel, and drifts with the source LED,
/// the wheel's alignment and the ball's contact, so no fixed threshold works.
/// Instead a decaying peak/trough envelope tracks the signal's own extremes and
/// the thresholds are derived from that envelope: the line is compared against
/// its own recent swing, whatever absolute levels that swing happens to sit
/// between. A hysteresis band around the midpoint keeps noise on a slow crossing
/// from counting several times.
///
/// Only one direction is counted — a pulse is one falling crossing, not two
/// crossings — so the count matches what the interrupt backend used to produce
/// and `PulseActivity` is fed exactly the same numbers as before.
///
/// The envelope also answers "is this line moving at all": when the ball stops,
/// both extremes decay toward the resting level, the span collapses below
/// `min_span`, and counting stops. That is what keeps ADC noise on a still ball
/// from reading as a slow spin.
///
/// No Arduino dependency: the `analogRead` is the app's call, this is fed
/// synthetic samples in the host tests.

class AnalogEdges {
 public:
  /// @brief Detection parameters, in raw ADC counts.
  /// @var Config::min_span       peak-to-peak swing below which the line counts
  ///                             as unmodulated and no edges are reported. Set
  ///                             above the ADC's own noise and below the
  ///                             smallest real swing the wheels produce.
  /// @var Config::decay          counts each envelope extreme leaks toward the
  ///                             current sample per sample. Small enough not to
  ///                             collapse the span within one pulse period,
  ///                             large enough to collapse it soon after motion
  ///                             stops.
  /// @var Config::hysteresis_pct half-width of the dead band around the
  ///                             envelope's midpoint, as a percentage of the
  ///                             span. Clamped to 1..50; 50 means a crossing
  ///                             must reach the far extreme.
  struct Config {
    uint16_t min_span;
    uint16_t decay;
    uint8_t hysteresis_pct;
  };

  explicit AnalogEdges(const Config &config);

  /// @brief Feed one raw ADC sample. Returns true when the line just crossed
  ///        downward through its hysteresis band — one pulse. Returns false
  ///        while the tracked span is below `min_span`, whatever the sample.
  bool update(uint16_t sample);

  /// @brief Current peak-to-peak envelope, in counts. Zero before the first
  ///        sample. Useful on the bench: it is the number the divider and
  ///        `min_span` have to be chosen against.
  uint16_t span() const;

  /// @brief Envelope trough and peak, in counts.
  uint16_t low() const { return low_; }
  uint16_t high() const { return high_; }

  /// @brief Whether the line is currently held above the band.
  bool level() const { return level_; }

 private:
  uint16_t min_span_;
  uint16_t decay_;
  uint8_t hysteresis_pct_;
  uint16_t low_;
  uint16_t high_;
  bool level_;
  bool seeded_;
};
