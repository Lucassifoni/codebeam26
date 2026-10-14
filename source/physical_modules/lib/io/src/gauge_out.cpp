#include "gauge_out.h"

#include <Arduino.h>

GaugeOut::GaugeOut(uint8_t pin, uint32_t freq_hz, uint8_t resolution_bits)
    : pin_(pin), freq_(freq_hz), resolution_(resolution_bits) {}

bool GaugeOut::begin() { return ledcAttach(pin_, freq_, resolution_); }

void GaugeOut::set(uint8_t duty) {
  const uint32_t max_duty = (1u << resolution_) - 1u;
  const uint32_t value = (static_cast<uint32_t>(duty) * max_duty) / 255u;
  ledcWrite(pin_, value);
}
