#include "spi_shift_bus.h"

#include <Arduino.h>

SpiShiftOutputBus::SpiShiftOutputBus(SPIClass &spi, uint8_t latch_pin,
                                     size_t bits, SPISettings settings,
                                     bool active_low)
    : spi_(spi),
      latch_(latch_pin),
      bits_(bits),
      settings_(settings),
      active_low_(active_low) {}

void SpiShiftOutputBus::begin() {
  pinMode(latch_, OUTPUT);
  digitalWrite(latch_, LOW);
}

void SpiShiftOutputBus::write(const uint8_t *bits) {
  const size_t nbytes = (bits_ + 7) / 8;
  if (nbytes > kMaxChainBytes) {
    return;
  }

  uint8_t buf[kMaxChainBytes];
  for (size_t i = 0; i < nbytes; i++) {
    buf[i] = active_low_ ? static_cast<uint8_t>(~bits[i]) : bits[i];
  }

  spi_.beginTransaction(settings_);
  digitalWrite(latch_, LOW);
  spi_.writeBytes(buf, nbytes);
  digitalWrite(latch_, HIGH);
  spi_.endTransaction();
}

SpiShiftInputBus::SpiShiftInputBus(SPIClass &spi, uint8_t load_pin, size_t bits,
                                   bool active_low, uint32_t clock_hz)
    : spi_(spi),
      load_(load_pin),
      bits_(bits),
      settings_(clock_hz > kClockHz ? kClockHz : clock_hz, MSBFIRST, kDataMode),
      active_low_(active_low) {}

void SpiShiftInputBus::begin() {
  pinMode(load_, OUTPUT);
  digitalWrite(load_, HIGH);
}

void SpiShiftInputBus::read(uint8_t *bits) const {
  const size_t nbytes = (bits_ + 7) / 8;
  if (nbytes > kMaxChainBytes) {
    return;
  }

  spi_.beginTransaction(settings_);
  digitalWrite(load_, LOW);
  delayMicroseconds(1);
  digitalWrite(load_, HIGH);
  spi_.transferBytes(nullptr, bits, nbytes);
  spi_.endTransaction();

  for (size_t i = 0; i < nbytes; i++) {
    if (active_low_) {
      bits[i] = static_cast<uint8_t>(~bits[i]);
    }
  }

  const size_t extra = nbytes * 8 - bits_;
  if (extra > 0) {
    bits[nbytes - 1] &= static_cast<uint8_t>(0xFF >> extra);
  }
}
