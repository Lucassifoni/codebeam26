#pragma once

#include <stddef.h>
#include <stdint.h>

/// @file
/// Pure conditioning for a single analog joystick axis. Raw 12-bit ADC samples
/// are fed in from the app — the `analogRead` itself is the app's Arduino call —
/// so this whole pipeline is host-testable with synthetic samples. Each sample
/// is smoothed by an integer exponential moving average, then mapped through a
/// center/min/max calibration with a deadzone to a signed, centered output. No
/// Arduino dependency.

class AnalogAxis {
 public:
  /// @brief Per-axis calibration.
  /// @var Config::center   raw reading at rest.
  /// @var Config::min      raw reading at one mechanical extreme (min < max).
  /// @var Config::max      raw reading at the other extreme.
  /// @var Config::deadzone half-width in raw counts around center mapped to 0.
  /// @var Config::out_range output magnitude at each extreme; output spans
  ///                        [-out_range, +out_range].
  /// @var Config::ema_shift EMA smoothing factor; alpha = 1 / 2^ema_shift. 0
  ///                        disables smoothing (output tracks the raw sample).
  struct Config {
    uint16_t center;
    uint16_t min;
    uint16_t max;
    uint16_t deadzone;
    int16_t out_range;
    uint8_t ema_shift;
  };

  explicit AnalogAxis(const Config &config);

  /// @brief Seed the EMA to `raw` so the first update() has no ramp-in.
  void reset(uint16_t raw);

  /// @brief Feed one raw sample; returns the new signed centered output.
  int16_t update(uint16_t raw);

  /// @brief Last computed signed centered output.
  int16_t value() const { return value_; }

  /// @brief Current EMA-filtered raw estimate.
  uint16_t filtered() const {
    return static_cast<uint16_t>(accum_ >> cfg_.ema_shift);
  }

 private:
  int16_t calibrate(uint16_t filtered) const;

  Config cfg_;
  uint32_t accum_;  // EMA accumulator; filtered() = accum_ >> ema_shift
  int16_t value_;
  bool seeded_;
};
