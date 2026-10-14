#pragma once

#include <stddef.h>
#include <stdint.h>

/// @file
/// Thin ledc PWM output for an analog panel gauge. The firmware emits a 0..255
/// duty and is unaware of the actual voltage: an external op-amp gain stage
/// scales the 0–3.3 V PWM average up to the gauge's true 0–5 V range. This unit
/// only touches the ESP32 ledc peripheral, so it is exercised on hardware, not
/// under host test (the 0..255 → duty scaling is a trivial passthrough).

class GaugeOut {
 public:
  /// @param pin              GPIO carrying the PWM.
  /// @param freq_hz          PWM frequency; pick with the RC/op-amp filter.
  /// @param resolution_bits  ledc timer resolution.
  GaugeOut(uint8_t pin, uint32_t freq_hz, uint8_t resolution_bits);

  /// @brief Attach the ledc channel. Call from setup(), after the runtime is up.
  bool begin();

  /// @brief Set the output from a 0..255 duty, scaled to the timer resolution.
  void set(uint8_t duty);

 private:
  uint8_t pin_;
  uint32_t freq_;
  uint8_t resolution_;
};
