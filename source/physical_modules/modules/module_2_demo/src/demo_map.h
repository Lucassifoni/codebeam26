#pragma once

#include <stddef.h>
#include <stdint.h>

/// @file
/// The whole difference between module_2 and its two-key demo stand-in: which
/// of module_2's wire indices the demo's local lines answer to. Pure and
/// header-only, so the host tests include it without the Arduino runtime.
///
/// Local line i is paired: button kKeyWire[i] and LED kLedWire[i] sit on the
/// same physical key. Everything else on module_2's wire (the other six keys
/// and LEDs, gauges, joysticks, encoder, NFC) has no line here and is dropped.

namespace demo_map {

constexpr size_t kLines = 2;

/// @brief module_2 key index reported for each local button.
constexpr uint8_t kKeyWire[kLines] = {6, 5};

/// @brief module_2 LED index driving each local LED.
constexpr uint8_t kLedWire[kLines] = {2, 7};

/// @brief Local LED bits (bit i = local LED i) from a module_2 SetLeds byte.
constexpr uint8_t local_leds(uint8_t wire_bits) {
  return static_cast<uint8_t>(((wire_bits >> kLedWire[0]) & 1u) |
                              (((wire_bits >> kLedWire[1]) & 1u) << 1));
}

/// @brief module_2 Snapshot byte from local pressed bits (bit i = button i).
constexpr uint8_t wire_snapshot(uint8_t local_pressed) {
  return static_cast<uint8_t>(((local_pressed & 1u) << kKeyWire[0]) |
                              (((local_pressed >> 1) & 1u) << kKeyWire[1]));
}

}  // namespace demo_map
