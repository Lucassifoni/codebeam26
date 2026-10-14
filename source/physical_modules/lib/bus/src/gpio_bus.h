#pragma once

#include <stddef.h>
#include <stdint.h>

#include "bit_bus.h"

/// @file
/// Direct-GPIO bus backends, for small matrices wired straight to pins.
/// Construct with a caller-owned pin array; call begin() from setup() (pin
/// modes are configured there, not in the constructor, since buses are normally
/// globals constructed before the Arduino runtime is ready).
///
/// `active_low` selects electrical polarity while the bus presents a logical
/// view to the matrices (logical 1 = line driven / key pressed).

class GpioOutputBus : public OutputBus {
 public:
  GpioOutputBus(const uint8_t *pins, size_t count, bool active_low);

  void begin();

  size_t width() const override { return count_; }
  void write(const uint8_t *bits) override;

 private:
  const uint8_t *pins_;
  size_t count_;
  bool active_low_;
};

class GpioInputBus : public InputBus {
 public:
  GpioInputBus(const uint8_t *pins, size_t count, bool active_low,
               bool use_pullup);

  void begin();

  size_t width() const override { return count_; }
  void read(uint8_t *bits) const override;

 private:
  const uint8_t *pins_;
  size_t count_;
  bool active_low_;
  bool use_pullup_;
};
