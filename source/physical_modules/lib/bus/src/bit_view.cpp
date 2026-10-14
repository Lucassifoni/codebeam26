#include "bit_view.h"

#include <string.h>

BitView::BitView(uint8_t *bytes, size_t bit_count)
    : bytes_(bytes), bit_count_(bit_count) {}

bool BitView::get(size_t index) const {
  if (index >= bit_count_) {
    return false;
  }
  return (bytes_[index >> 3] >> (index & 7)) & 1u;
}

void BitView::set(size_t index, bool on) {
  if (index >= bit_count_) {
    return;
  }
  const uint8_t mask = static_cast<uint8_t>(1u << (index & 7));
  if (on) {
    bytes_[index >> 3] |= mask;
  } else {
    bytes_[index >> 3] &= static_cast<uint8_t>(~mask);
  }
}

void BitView::clear() {
  memset(bytes_, 0, byte_count());
}
