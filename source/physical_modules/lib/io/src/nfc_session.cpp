#include "nfc_session.h"

#include <string.h>

NfcSession::NfcSession(uint8_t miss_threshold)
    : present_(false),
      current_{},
      miss_(0),
      miss_threshold_(miss_threshold == 0 ? 1 : miss_threshold),
      write_pending_(false),
      write_start_page_(0),
      write_len_(0),
      write_data_{} {}

void NfcSession::queue_write(uint8_t start_page, const uint8_t *data,
                             size_t len) {
  if (len > kNfcMaxPayloadBytes) {
    len = kNfcMaxPayloadBytes;
  }
  write_start_page_ = start_page;
  write_len_ = len;
  memset(write_data_, 0, sizeof(write_data_));
  memcpy(write_data_, data, len);
  write_pending_ = true;
}

bool NfcSession::same_uid(const TagInfo &tag) const {
  return tag.uid_len == current_.uid_len &&
         memcmp(tag.uid, current_.uid, tag.uid_len) == 0;
}

bool NfcSession::apply_write(NfcController &controller) {
  const size_t pages = (write_len_ + kNfcPageBytes - 1) / kNfcPageBytes;
  for (size_t p = 0; p < pages; p++) {
    if (!controller.write_page(static_cast<uint8_t>(write_start_page_ + p),
                               write_data_ + p * kNfcPageBytes)) {
      return false;
    }
  }
  return true;
}

void NfcSession::fire_pending_write(NfcController &controller,
                                    const Handlers &h, void *ctx) {
  if (!write_pending_) {
    return;
  }
  const bool ok = apply_write(controller);
  write_pending_ = false;
  if (h.on_write != nullptr) {
    h.on_write(current_, ok, ctx);
  }
}

void NfcSession::poll(NfcController &controller, const Handlers &h, void *ctx) {
  if (present_ && controller.still_present()) {
    miss_ = 0;
    fire_pending_write(controller, h, ctx);
    return;
  }

  TagInfo tag;
  if (controller.detect(tag)) {
    miss_ = 0;
    if (!present_ || !same_uid(tag)) {
      present_ = true;
      current_ = tag;
      if (h.on_arrival != nullptr) {
        h.on_arrival(tag, ctx);
      }
    }
    fire_pending_write(controller, h, ctx);
    return;
  }

  if (present_ && ++miss_ >= miss_threshold_) {
    present_ = false;
    miss_ = 0;
    controller.release();
    if (h.on_removal != nullptr) {
      h.on_removal(ctx);
    }
  }
}
