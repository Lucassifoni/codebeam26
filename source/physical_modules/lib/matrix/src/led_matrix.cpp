#include "led_matrix.h"

#include <string.h>

LedMatrix::LedMatrix(OutputBus &rows, OutputBus &cols, uint8_t *framebuffer)
    : rows_(rows),
      cols_(cols),
      fb_(framebuffer),
      current_row_(rows.width() ? rows.width() - 1 : 0) {}

void LedMatrix::set(size_t row, size_t col, bool on) {
  if (row >= rows_.width() || col >= cols_.width()) {
    return;
  }
  uint8_t &byte = fb_[row * col_bytes() + (col >> 3)];
  const uint8_t mask = static_cast<uint8_t>(1u << (col & 7));
  if (on) {
    byte |= mask;
  } else {
    byte &= static_cast<uint8_t>(~mask);
  }
}

bool LedMatrix::get(size_t row, size_t col) const {
  if (row >= rows_.width() || col >= cols_.width()) {
    return false;
  }
  return (fb_[row * col_bytes() + (col >> 3)] >> (col & 7)) & 1u;
}

void LedMatrix::clear() {
  memset(fb_, 0, rows_.width() * col_bytes());
}

void LedMatrix::refresh_step() {
  const size_t row_count = rows_.width();
  const size_t row_bytes = (row_count + 7) / 8;
  if (row_count == 0 || row_bytes > kMaxRowBytes) {
    return;
  }

  uint8_t row_sel[kMaxRowBytes];

  memset(row_sel, 0, row_bytes);
  rows_.write(row_sel);

  current_row_ = (current_row_ + 1) % row_count;

  cols_.write(fb_ + current_row_ * col_bytes());

  row_sel[current_row_ >> 3] = static_cast<uint8_t>(1u << (current_row_ & 7));
  rows_.write(row_sel);
}
