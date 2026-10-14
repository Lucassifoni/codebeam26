#include "framing.h"

#include "cobs.h"

static const uint8_t kFrameDelimiter = 0x00;

size_t frame_encode(const uint8_t *payload, size_t length, uint8_t *dst) {
  const size_t encoded = cobs_encode(payload, length, dst);
  dst[encoded] = kFrameDelimiter;
  return encoded + 1;
}
