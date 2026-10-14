#pragma once

#include <stddef.h>
#include <stdint.h>

#include "bit_bus.h"

/// @file
/// Multiplexed LED matrix. Rows are driven one-hot, one at a time; for each
/// lit row the column pattern is presented on the column bus. Calling
/// refresh_step() repeatedly (at a steady rate) cycles through the rows fast
/// enough to appear continuous. Each step blanks the rows before changing
/// columns, so a column change never bleeds into the previously lit row
/// (inter-row ghosting).
///
/// Pure and host-testable: it only talks to the row/column buses. The framebuffer
/// is caller-owned, laid out as one packed column pattern per row
/// (row r's columns at framebuffer + r * ceil(cols/8)). Thread-safety against a
/// concurrent writer is provided by LedRefreshTimer, not here.

class LedMatrix {
 public:
  LedMatrix(OutputBus &rows, OutputBus &cols, uint8_t *framebuffer);

  void set(size_t row, size_t col, bool on);
  bool get(size_t row, size_t col) const;
  void clear();

  size_t rows() const { return rows_.width(); }
  size_t cols() const { return cols_.width(); }

  /// @brief Advance to the next row and display it (blank → columns → enable).
  void refresh_step();

  static constexpr size_t framebuffer_bytes(size_t rows, size_t cols) {
    return rows * ((cols + 7) / 8);
  }

  /// @brief Row-count cap (bytes of one-hot row scratch on the stack).
  static constexpr size_t kMaxRowBytes = 32;  // up to 256 rows

 private:
  size_t col_bytes() const { return (cols_.width() + 7) / 8; }

  OutputBus &rows_;
  OutputBus &cols_;
  uint8_t *fb_;
  size_t current_row_;
};
