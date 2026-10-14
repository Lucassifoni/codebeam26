#pragma once

#include <stddef.h>
#include <stdint.h>

#include <MFRC522DriverI2C.h>
#include <MFRC522v2.h>
#include <Wire.h>

#include "nfc_controller.h"

/// @file
/// NfcController backend for an MFRC522 reader on I2C driving NTAG21x /
/// Ultralight tags, via the MFRC522v2 library's MFRC522DriverI2C. This is the
/// only impure NFC unit — it drives the radio — so the pure NfcSession and the
/// module's NDEF value convention sit above it and stay host-testable.
///
/// NTAG user memory is open: there is no authentication. Writes are 4-byte page
/// writes (MIFARE_Ultralight_Write); reads pull 16-byte runs (MIFARE_Read, which
/// returns four pages) and are sliced to the requested length.
///
/// A detected tag is left selected (ACTIVE) rather than halted, and every later
/// operation reuses that selection: halting is expensive on this reader, because
/// HLTA succeeds only by drawing no answer, so every halt waits out the full
/// 25 ms receive timeout. still_present() is then a single one-page READ that a
/// present tag answers within a millisecond. Any failed exchange halts the tag
/// and drops the selection, so the next detect() starts from a known state: WUPA
/// wakes a halted tag, but an ACTIVE one ignores it.

class Mfrc522I2cController : public NfcController {
 public:
  /// @param address I2C address of the reader (MFRC522 default 0x28).
  /// @param wire    I2C bus; the app must have called Wire.begin(sda, scl).
  Mfrc522I2cController(uint8_t address, TwoWire &wire);

  /// @brief Initialise the reader (PCD_Init). Call after Wire.begin().
  bool begin();

  bool detect(TagInfo &out) override;
  bool still_present() override;
  bool read(uint8_t start_page, uint8_t *out, size_t len) override;
  bool write_page(uint8_t page, const uint8_t in[kNfcPageBytes]) override;
  void release() override;

 private:
  bool wake_and_select();
  bool ensure_selected();
  void drop_selection();
  void halt();

  MFRC522DriverI2C driver_;
  MFRC522 reader_;
  bool selected_;
};
