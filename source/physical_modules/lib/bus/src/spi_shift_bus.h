#pragma once

#include <SPI.h>
#include <stddef.h>
#include <stdint.h>

#include "bit_bus.h"

/// @file
/// Shift-register bus backends over hardware SPI, for large matrices.
/// SpiShiftOutputBus drives a 74HC595 chain; SpiShiftInputBus reads a 74HC165
/// chain. Both are daisy-chainable to arbitrary depth: a chain of K chips is
/// 8*K lines, and write()/read() move `ceil(width/8)` bytes (= K).
///
/// Each bus takes its own SPIClass instance, so the 595 output chain and the
/// 165 input chain can live on independent SPI peripherals (VSPI/HSPI) — that
/// is what lets a timer-driven LED refresh and a loop-driven key scan run
/// without sharing a bus. The app calls SPIClass::begin() with its pins; this
/// class only manages the per-chain latch (595) / load (165) line.
///
/// Wire convention: byte[0] is shifted first, MSB-first (per SPISettings). Map
/// physical outputs/inputs to bit indices by your chain ordering. `active_low`
/// inverts the electrical sense while keeping the logical view (1 = driven /
/// pressed).

class SpiShiftOutputBus : public OutputBus {
 public:
  SpiShiftOutputBus(SPIClass &spi, uint8_t latch_pin, size_t bits,
                    SPISettings settings, bool active_low = false);

  /// @brief Configure the latch pin. Call after SPIClass::begin(), from setup().
  void begin();

  size_t width() const override { return bits_; }
  void write(const uint8_t *bits) override;

  static constexpr size_t kMaxChainBytes = 64;  // up to 512 outputs

 private:
  SPIClass &spi_;
  uint8_t latch_;
  size_t bits_;
  SPISettings settings_;
  bool active_low_;
};

/// Reads a 74HC165 chain.
///
/// **This bus chooses its own SPI mode and clock, and callers cannot override
/// the mode.** How to clock a '165 is a property of the chip, not of the board,
/// and getting it wrong has cost two boards an afternoon each:
///
/// A '165 shifts Q7 on the RISING edge of CP. `SPI_MODE0` samples MISO on the
/// rising edge too, so the master races the chip's own output — it is meant to
/// catch the pre-edge value, but with HC parts at 3.3 V the margin is tens of
/// nanoseconds and above a few MHz the ESP32 loses. Every sample then carries
/// the *next* bit: the first bit of the chain is dropped, and the last sample
/// picks up whatever follows the real data — the chain's SER input, tied to GND,
/// arriving as a permanently pressed key on the last index.
///
/// The symptom is not a read that looks broken. It is one input stuck pressed
/// that survives replacing the chip, one input that never reports at all, and
/// every other input off by one — a map that looks like a wiring mistake, on a
/// board where every electrical measurement passes. Both times, the copper was
/// innocent.
///
/// `SPI_MODE2` samples on the FALLING edge, the opposite one from the shift,
/// which turns the race into half a clock of margin. The clock is clamped on top
/// of that: a sense read is a handful of bytes against a scan measured in
/// hundreds of microseconds, so the rate buys nothing worth this failure mode.
class SpiShiftInputBus : public InputBus {
 public:
  /// Sampling edge for every '165 read. Not a parameter: see the class comment.
  static constexpr uint8_t kDataMode = SPI_MODE2;

  /// Default and ceiling for the read clock. A caller may ask for less, never
  /// for more.
  static constexpr uint32_t kClockHz = 4000000;

  /// @param clock_hz  read clock, clamped to kClockHz.
  SpiShiftInputBus(SPIClass &spi, uint8_t load_pin, size_t bits,
                   bool active_low = false, uint32_t clock_hz = kClockHz);

  /// @brief Configure the load pin. Call after SPIClass::begin(), from setup().
  void begin();

  size_t width() const override { return bits_; }
  void read(uint8_t *bits) const override;

  static constexpr size_t kMaxChainBytes = 64;  // up to 512 inputs

 private:
  SPIClass &spi_;
  uint8_t load_;
  size_t bits_;
  SPISettings settings_;
  bool active_low_;
};
