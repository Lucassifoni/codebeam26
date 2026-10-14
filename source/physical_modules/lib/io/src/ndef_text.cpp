#include "ndef_text.h"

#include <string.h>

namespace ndef_text {
namespace {

constexpr uint8_t kTlvNull = 0x00;
constexpr uint8_t kTlvNdef = 0x03;
constexpr uint8_t kTlvTerminator = 0xFE;
constexpr uint8_t kTlvLenThreeByte = 0xFF;

// Record header for a single, well-known, short Text record:
// MB(0x80) | ME(0x40) | SR(0x10) | TNF=well-known(0x01).
constexpr uint8_t kRecordHeader = 0xD1;
constexpr uint8_t kTypeLength = 0x01;
constexpr uint8_t kTypeText = 0x54;  // 'T'
constexpr uint8_t kTnfMask = 0x07;
constexpr uint8_t kTnfWellKnown = 0x01;
constexpr uint8_t kFlagShortRecord = 0x10;

constexpr uint8_t kLangLength = 0x02;  // "en"
constexpr uint8_t kStatusUtf16 = 0x80;
constexpr uint8_t kStatusLangMask = 0x3F;
constexpr uint8_t kLang0 = 'e';
constexpr uint8_t kLang1 = 'n';

// A short record's fixed prefix: flags, type length, payload length, type.
constexpr size_t kRecordHeaderBytes = 4;
// Payload prefix before the text: the status byte plus the language code.
constexpr size_t kPayloadPrefixBytes = 1 + kLangLength;

}  // namespace

size_t encode(const uint8_t *text, size_t text_len, uint8_t *out, size_t cap) {
  if (text_len > kMaxText) {
    return 0;
  }
  const size_t need = encoded_size(text_len);
  if (cap < need) {
    return 0;
  }

  const uint8_t payload_len =
      static_cast<uint8_t>(kPayloadPrefixBytes + text_len);
  const uint8_t ndef_len =
      static_cast<uint8_t>(kRecordHeaderBytes + payload_len);

  size_t n = 0;
  out[n++] = kTlvNdef;
  out[n++] = ndef_len;
  out[n++] = kRecordHeader;
  out[n++] = kTypeLength;
  out[n++] = payload_len;
  out[n++] = kTypeText;
  out[n++] = kLangLength;
  out[n++] = kLang0;
  out[n++] = kLang1;
  for (size_t i = 0; i < text_len; i++) {
    out[n++] = text[i];
  }
  out[n++] = kTlvTerminator;
  return n;
}

bool decode(const uint8_t *in, size_t len, uint8_t *out, size_t cap,
            size_t *text_len) {
  size_t i = 0;
  while (i < len && in[i] == kTlvNull) {
    i++;
  }
  if (i >= len || in[i] != kTlvNdef) {
    return false;
  }
  i++;
  if (i >= len) {
    return false;
  }
  const uint8_t ndef_len = in[i++];
  if (ndef_len == kTlvLenThreeByte || ndef_len < kRecordHeaderBytes + 1) {
    return false;
  }
  if (i + ndef_len > len) {
    return false;
  }

  const uint8_t *msg = in + i;
  const uint8_t flags = msg[0];
  const uint8_t type_len = msg[1];
  const uint8_t payload_len = msg[2];
  const uint8_t type = msg[3];
  if ((flags & kFlagShortRecord) == 0 || (flags & kTnfMask) != kTnfWellKnown ||
      type_len != kTypeLength || type != kTypeText) {
    return false;
  }
  if (kRecordHeaderBytes + static_cast<size_t>(payload_len) > ndef_len ||
      payload_len < 1) {
    return false;
  }

  const uint8_t status = msg[kRecordHeaderBytes];
  if (status & kStatusUtf16) {
    return false;
  }
  const uint8_t lang_len = status & kStatusLangMask;
  if (static_cast<size_t>(1 + lang_len) > payload_len) {
    return false;
  }

  const size_t decoded_len = payload_len - 1 - lang_len;
  if (decoded_len > cap) {
    return false;
  }
  memcpy(out, msg + kRecordHeaderBytes + 1 + lang_len, decoded_len);
  *text_len = decoded_len;
  return true;
}

}  // namespace ndef_text
