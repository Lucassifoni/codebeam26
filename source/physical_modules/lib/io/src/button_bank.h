#pragma once

#include <stddef.h>
#include <stdint.h>

#include "bit_bus.h"

/// @file
/// Debounced reader for a flat bank of buttons behind an InputBus (direct GPIO
/// or a 74HC165 chain). It carries its own copy of the counter-based debounce
/// loop — deliberately not sharing KeyMatrix's, which is coupled to the
/// drive/sense scan — so the two evolve independently. A raw level must disagree
/// with the committed (stable) state for `debounce_scans` consecutive steps
/// before the state flips and a transition event fires. Pure and hardware-free;
/// storage is caller-owned. Host-testable with a fake InputBus.

struct ButtonEvent {
  uint16_t index;
  bool pressed;
};

/// @brief Invoked once per debounced press/release transition during step().
using ButtonEventHandler = void (*)(const ButtonEvent &event, void *ctx);

class ButtonBank {
 public:
  /// Caller buffers: `stable_bits` is stable_bytes(bus.width()); `counters` is
  /// counter_bytes(bus.width()). Both should start zeroed.
  ButtonBank(InputBus &bus, uint8_t debounce_scans, uint8_t *stable_bits,
             uint8_t *counters);

  /// @brief Read the bus once, update debounce state, and emit transition
  ///        events. Returns true if any button's committed state changed this
  ///        step. `on_event` may be null.
  bool step(ButtonEventHandler on_event, void *ctx);

  bool pressed(size_t index) const;
  size_t count() const { return bus_.width(); }

  static constexpr size_t stable_bytes(size_t buttons) {
    return (buttons + 7) / 8;
  }
  static constexpr size_t counter_bytes(size_t buttons) { return buttons; }

  /// @brief Max bus width (bytes of read scratch on the stack).
  static constexpr size_t kMaxBytes = 32;  // up to 256 buttons

 private:
  InputBus &bus_;
  uint8_t debounce_scans_;
  uint8_t *stable_;
  uint8_t *counters_;
};
