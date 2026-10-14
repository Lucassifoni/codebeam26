#include "frame_reader.h"

#include "cobs.h"

static const uint8_t kFrameDelimiter = 0x00;

FrameReader::FrameReader(uint8_t *encoded, size_t encoded_capacity,
                         uint8_t *decoded, size_t decoded_capacity)
    : encoded_(encoded),
      encoded_capacity_(encoded_capacity),
      encoded_length_(0),
      decoded_(decoded),
      decoded_capacity_(decoded_capacity),
      overflow_(false) {}

size_t FrameReader::push(uint8_t byte) {
  if (byte != kFrameDelimiter) {
    if (encoded_length_ < encoded_capacity_) {
      encoded_[encoded_length_++] = byte;
    } else {
      overflow_ = true;
    }
    return 0;
  }

  size_t decoded_length = 0;
  if (!overflow_ && encoded_length_ > 0 &&
      cobs_decode_bounds(encoded_length_) <= decoded_capacity_) {
    decoded_length = cobs_decode(encoded_, encoded_length_, decoded_);
  }

  encoded_length_ = 0;
  overflow_ = false;
  return decoded_length;
}
