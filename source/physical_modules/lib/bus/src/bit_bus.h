#pragma once

#include <stddef.h>
#include <stdint.h>

/// @file
/// Abstract digital line buses. An OutputBus drives `width()` output lines from
/// a packed bit buffer; an InputBus reads `width()` input lines into one. Bit
/// packing matches BitView (bit i -> byte i/8, position i%8).
///
/// Every matrix is written against these interfaces, so the same scan/refresh
/// logic runs unchanged whether the lines are direct GPIO pins or a daisy chain
/// of shift registers. The concrete backends live in gpio_bus.h / spi_shift_bus.h.
/// These interfaces are pure (no Arduino), which keeps the matrices host-testable.

class OutputBus {
 public:
  virtual ~OutputBus() = default;

  /// @brief Number of output lines this bus drives.
  virtual size_t width() const = 0;

  /// @brief Drive all lines from `bits` (packed, line i = bit i).
  virtual void write(const uint8_t *bits) = 0;
};

class InputBus {
 public:
  virtual ~InputBus() = default;

  /// @brief Number of input lines this bus reads.
  virtual size_t width() const = 0;

  /// @brief Read all lines into `bits` (packed, line i = bit i).
  virtual void read(uint8_t *bits) const = 0;
};
