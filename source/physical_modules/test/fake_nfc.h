#pragma once

#include <cstring>
#include <vector>

#include "nfc_controller.h"

/// @file
/// Host-only fake NfcController for NfcSession tests. Presence and UID are set
/// by the test; page memory is in-memory; write_page / release calls are
/// recorded so the pure session logic can be exercised with no radio. Memory is
/// a flat 256-page (1 KiB) span, enough for any NTAG21x user region a test
/// touches.
///
/// Selection is modelled as on the radio: a successful detect() selects the
/// tag, and only a selected tag passes still_present(). Placing or removing a
/// tag, a release, or drop_selection() (a lost selection with the tag still in
/// the field) all clear it.

class FakeNfcController : public NfcController {
 public:
  static constexpr size_t kPages = 256;

  void set_absent() {
    present_ = false;
    selected_ = false;
  }

  void drop_selection() { selected_ = false; }

  void set_tag(const uint8_t *uid, uint8_t uid_len, uint8_t sak) {
    present_ = true;
    selected_ = false;
    tag_.uid_len = uid_len;
    tag_.sak = sak;
    memcpy(tag_.uid, uid, uid_len);
  }

  bool detect(TagInfo &out) override {
    detects++;
    if (!present_) {
      return false;
    }
    selected_ = true;
    out = tag_;
    return true;
  }

  bool still_present() override {
    presence_checks++;
    return present_ && selected_;
  }

  bool read(uint8_t start_page, uint8_t *out, size_t len) override {
    memcpy(out, &mem_[static_cast<size_t>(start_page) * kNfcPageBytes], len);
    return read_ok_;
  }

  bool write_page(uint8_t page, const uint8_t in[kNfcPageBytes]) override {
    memcpy(&mem_[static_cast<size_t>(page) * kNfcPageBytes], in, kNfcPageBytes);
    pages_written.push_back(page);
    return write_ok_;
  }

  void release() override {
    releases++;
    selected_ = false;
  }

  const uint8_t *page(uint8_t p) const {
    return &mem_[static_cast<size_t>(p) * kNfcPageBytes];
  }

  bool present_ = false;
  bool selected_ = false;
  TagInfo tag_{};
  uint8_t mem_[kPages * kNfcPageBytes] = {0};
  bool read_ok_ = true;
  bool write_ok_ = true;
  int releases = 0;
  int detects = 0;
  int presence_checks = 0;
  std::vector<uint8_t> pages_written;
};
