#include "mfrc522_i2c_controller.h"

#include <string.h>

namespace {
// MIFARE_Read returns four pages (16 data bytes) plus a 2-byte CRC.
constexpr uint8_t kReadChunkBytes = 16;
constexpr uint8_t kReadBufferBytes = 18;
// Page 0 holds the UID head on every NTAG21x / Ultralight, so it always reads.
constexpr uint8_t kPresencePage = 0;
}  // namespace

Mfrc522I2cController::Mfrc522I2cController(uint8_t address, TwoWire &wire)
    : driver_(address, wire), reader_(driver_), selected_(false) {}

bool Mfrc522I2cController::begin() { return reader_.PCD_Init(); }

bool Mfrc522I2cController::wake_and_select() {
  uint8_t atqa[2];
  uint8_t atqa_len = sizeof(atqa);
  const MFRC522::StatusCode woke = reader_.PICC_WakeupA(atqa, &atqa_len);
  if (woke != MFRC522::StatusCode::STATUS_OK &&
      woke != MFRC522::StatusCode::STATUS_COLLISION) {
    return false;
  }
  return reader_.PICC_Select(&reader_.uid) == MFRC522::StatusCode::STATUS_OK;
}

bool Mfrc522I2cController::ensure_selected() {
  if (!selected_) {
    selected_ = wake_and_select();
  }
  return selected_;
}

void Mfrc522I2cController::drop_selection() {
  halt();
  selected_ = false;
}

void Mfrc522I2cController::halt() { reader_.PICC_HaltA(); }

bool Mfrc522I2cController::detect(TagInfo &out) {
  if (selected_) {
    drop_selection();
  }
  if (!ensure_selected()) {
    return false;
  }
  const uint8_t n = reader_.uid.size <= sizeof(out.uid)
                        ? reader_.uid.size
                        : static_cast<uint8_t>(sizeof(out.uid));
  out.uid_len = n;
  out.sak = reader_.uid.sak;
  memcpy(out.uid, reader_.uid.uidByte, n);
  return true;
}

bool Mfrc522I2cController::still_present() {
  if (!selected_) {
    return false;
  }
  uint8_t buffer[kReadBufferBytes];
  uint8_t buffer_len = sizeof(buffer);
  if (reader_.MIFARE_Read(kPresencePage, buffer, &buffer_len) ==
      MFRC522::StatusCode::STATUS_OK) {
    return true;
  }
  drop_selection();
  return false;
}

bool Mfrc522I2cController::read(uint8_t start_page, uint8_t *out, size_t len) {
  if (!ensure_selected()) {
    return false;
  }
  size_t done = 0;
  while (done < len) {
    uint8_t buffer[kReadBufferBytes];
    uint8_t buffer_len = sizeof(buffer);
    const uint8_t page =
        static_cast<uint8_t>(start_page + done / kNfcPageBytes);
    const MFRC522::StatusCode status =
        reader_.MIFARE_Read(page, buffer, &buffer_len);
    if (status != MFRC522::StatusCode::STATUS_OK ||
        buffer_len < kReadChunkBytes) {
      drop_selection();
      return false;
    }
    const size_t remaining = len - done;
    const size_t chunk = remaining < kReadChunkBytes ? remaining : kReadChunkBytes;
    memcpy(out + done, buffer, chunk);
    done += chunk;
  }
  return true;
}

bool Mfrc522I2cController::write_page(uint8_t page,
                                      const uint8_t in[kNfcPageBytes]) {
  if (!ensure_selected()) {
    return false;
  }
  uint8_t buffer[kNfcPageBytes];
  memcpy(buffer, in, kNfcPageBytes);
  if (reader_.MIFARE_Ultralight_Write(page, buffer, kNfcPageBytes) !=
      MFRC522::StatusCode::STATUS_OK) {
    drop_selection();
    return false;
  }
  return true;
}

void Mfrc522I2cController::release() { drop_selection(); }
