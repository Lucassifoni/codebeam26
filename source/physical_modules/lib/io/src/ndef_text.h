#pragma once

#include <stddef.h>
#include <stdint.h>

/// @file
/// Pure NDEF "Text" record codec for NTAG21x user memory. Encodes a UTF-8
/// string as a single short NDEF Text record (language "en") wrapped in the
/// NTAG TLV structure — `0x03 <len> <ndef-message> 0xFE` — ready to be written
/// from the tag's first user page; decodes that structure back to the string.
/// No Arduino/radio dependency, so it is host-tested alongside the other pure
/// lib/io logic. The reader backend only moves bytes to/from tag pages; the
/// record layout lives here and stays testable.

namespace ndef_text {

/// @brief Longest text the module stores on a tag. A short record with a
///        single-byte TLV length keeps the whole layout in the one-byte-length
///        regime, which is all NTAG213 capacity and the use case need.
static constexpr size_t kMaxText = 46;

/// @brief Encoded byte count for `text_len` characters: NDEF TLV header (2) +
///        record header (4) + status + "en" language (3) + text + terminator (1).
static constexpr size_t encoded_size(size_t text_len) { return text_len + 10; }

/// @brief Buffer size that always holds the largest supported encoding.
static constexpr size_t kMaxEncoded = encoded_size(kMaxText);

/// @brief Encode `text` (`text_len` bytes, <= kMaxText) into `out` (`cap` bytes).
/// @return encoded length, or 0 if the text is too long or `out` is too small.
size_t encode(const uint8_t *text, size_t text_len, uint8_t *out, size_t cap);

/// @brief Decode an NDEF Text record TLV from `in` (`len` bytes) into `out`
///        (`cap` bytes); writes the text bytes and sets `*text_len`.
/// @return true on a well-formed UTF-8 text record; false on any malformation,
///         a UTF-16 record, or text that does not fit `cap`. Tolerates leading
///         NULL (0x00) TLVs and scans for the first NDEF-message (0x03) TLV, so
///         it reads back both our own writes and phone-written text tags.
bool decode(const uint8_t *in, size_t len, uint8_t *out, size_t cap,
            size_t *text_len);

}  // namespace ndef_text
