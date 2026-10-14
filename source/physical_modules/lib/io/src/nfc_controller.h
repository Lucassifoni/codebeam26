#pragma once

#include <stddef.h>
#include <stdint.h>

/// @file
/// Backend-agnostic NFC reader interface. A controller detects the tag in the
/// field and exposes page-granular access; concrete backends (e.g. an MFRC522
/// over I2C) do the radio work. Kept semantics-free so the pure NfcSession and
/// any per-module value convention (e.g. an NDEF text record) sit above it and
/// stay host-testable.
///
/// Page granular for NTAG21x / Ultralight: writes land one 4-byte page at a
/// time (the tag's write command size); reads return an arbitrary byte run so a
/// multi-page record can be pulled in one call. No authentication — NTAG user
/// memory is open, unlike MIFARE Classic.

/// @brief NTAG21x / Ultralight page size, and the write granularity.
static constexpr uint8_t kNfcPageBytes = 4;

/// @brief Upper bound on a single deferred write a session holds (a whole NDEF
///        text record fits well within this; keeps the session's buffer fixed).
static constexpr size_t kNfcMaxPayloadBytes = 64;

/// @brief Identifies the tag currently in the field.
struct TagInfo {
  uint8_t uid[10];
  uint8_t uid_len;
  uint8_t sak;
};

class NfcController {
 public:
  virtual ~NfcController() = default;

  /// @brief If a tag is present, fill `out` and return true; else return false.
  virtual bool detect(TagInfo &out) = 0;

  /// @brief Cheaply confirm that the tag the last successful detect() found is
  ///        still in the field, without a full wake + select. False when there
  ///        is no such tag, when it left, or when another tag took its place;
  ///        the caller then falls back to detect(). A detect() is what makes a
  ///        tag confirmable again.
  virtual bool still_present() = 0;

  /// @brief Read `len` bytes from the present tag starting at `start_page` into
  ///        `out`. False on any failure.
  virtual bool read(uint8_t start_page, uint8_t *out, size_t len) = 0;

  /// @brief Write one 4-byte page to the present tag. False on any failure.
  virtual bool write_page(uint8_t page, const uint8_t in[kNfcPageBytes]) = 0;

  /// @brief End the session with the current tag (halt).
  virtual void release() = 0;
};
