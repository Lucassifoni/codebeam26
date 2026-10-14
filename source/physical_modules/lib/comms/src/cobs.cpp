#include "cobs.h"

size_t cobs_encode(const uint8_t *src, size_t length, uint8_t *dst) {
  size_t read_index = 0;
  size_t write_index = 1;
  size_t code_index = 0;
  uint8_t code = 1;

  while (read_index < length) {
    if (src[read_index] == 0) {
      dst[code_index] = code;
      code = 1;
      code_index = write_index++;
      read_index++;
    } else {
      dst[write_index++] = src[read_index++];
      code++;
      if (code == 0xFF) {
        dst[code_index] = code;
        code = 1;
        code_index = write_index++;
      }
    }
  }

  dst[code_index] = code;
  return write_index;
}

size_t cobs_decode(const uint8_t *src, size_t length, uint8_t *dst) {
  size_t read_index = 0;
  size_t write_index = 0;

  while (read_index < length) {
    const uint8_t code = src[read_index];
    if (code == 0 || read_index + code > length) {
      return 0;
    }

    read_index++;
    for (uint8_t i = 1; i < code; i++) {
      dst[write_index++] = src[read_index++];
    }

    if (code != 0xFF && read_index < length) {
      dst[write_index++] = 0;
    }
  }

  return write_index;
}
