#include "gpio_bus.h"

#include <Arduino.h>
#include <string.h>

GpioOutputBus::GpioOutputBus(const uint8_t *pins, size_t count, bool active_low)
    : pins_(pins), count_(count), active_low_(active_low) {}

void GpioOutputBus::begin() {
  const uint8_t idle = active_low_ ? HIGH : LOW;
  for (size_t i = 0; i < count_; i++) {
    pinMode(pins_[i], OUTPUT);
    digitalWrite(pins_[i], idle);
  }
}

void GpioOutputBus::write(const uint8_t *bits) {
  for (size_t i = 0; i < count_; i++) {
    const bool driven = (bits[i >> 3] >> (i & 7)) & 1u;
    const uint8_t level =
        driven ? (active_low_ ? LOW : HIGH) : (active_low_ ? HIGH : LOW);
    digitalWrite(pins_[i], level);
  }
}

GpioInputBus::GpioInputBus(const uint8_t *pins, size_t count, bool active_low,
                           bool use_pullup)
    : pins_(pins),
      count_(count),
      active_low_(active_low),
      use_pullup_(use_pullup) {}

void GpioInputBus::begin() {
  const uint8_t mode = use_pullup_ ? INPUT_PULLUP : INPUT;
  for (size_t i = 0; i < count_; i++) {
    pinMode(pins_[i], mode);
  }
}

void GpioInputBus::read(uint8_t *bits) const {
  memset(bits, 0, (count_ + 7) / 8);
  for (size_t i = 0; i < count_; i++) {
    const bool high = digitalRead(pins_[i]) == HIGH;
    const bool active = active_low_ ? !high : high;
    if (active) {
      bits[i >> 3] |= static_cast<uint8_t>(1u << (i & 7));
    }
  }
}
