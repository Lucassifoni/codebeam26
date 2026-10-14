#pragma once

#include <stddef.h>
#include <stdint.h>

#include "nfc_controller.h"

/// @file
/// Pure presence/edge logic over an NfcController. Polled on a slow tick, it
/// tracks the current tag's UID, debounces removal by a miss count, and emits
/// arrival / removal / write edges through caller-supplied handlers. It also
/// holds a single pending byte run (padded to whole pages) that is written on
/// the next present tag. All of this is host-testable with a fake controller;
/// only the controller backend touches hardware. The byte-run meaning (e.g. an
/// NDEF text record starting at the first user page) is left to the module app
/// above this — the session stays generic and page-granular.
///
/// A held tag is confirmed with the controller's cheap still_present() rather
/// than a full detect(): a tag resting on the reader is the steady state, and a
/// full wake + select + halt on every poll is what made the poll expensive. Only
/// when that confirmation fails does the session fall back to detect(), which
/// then tells a removal (a miss) from a swap (a new UID, so a new arrival).

class NfcSession {
 public:
  struct Handlers {
    void (*on_arrival)(const TagInfo &tag, void *ctx);
    void (*on_removal)(void *ctx);
    void (*on_write)(const TagInfo &tag, bool ok, void *ctx);
  };

  /// @param miss_threshold consecutive absent polls before a removal is emitted.
  explicit NfcSession(uint8_t miss_threshold = 3);

  /// @brief Queue a byte run to write starting at `start_page`, applied on the
  ///        next present tag and padded up to a whole number of 4-byte pages.
  ///        `len` is clamped to kNfcMaxPayloadBytes. A newer queued write
  ///        replaces an unfired one.
  void queue_write(uint8_t start_page, const uint8_t *data, size_t len);

  /// @brief Whether a queued write is still waiting to fire.
  bool write_pending() const { return write_pending_; }

  /// @brief Whether a tag is currently held present.
  bool present() const { return present_; }

  /// @brief Poll the controller once: detect the tag, debounce removal, and emit
  ///        arrival / removal / write edges through `h` (any handler may be
  ///        null).
  void poll(NfcController &controller, const Handlers &h, void *ctx);

 private:
  bool same_uid(const TagInfo &tag) const;
  bool apply_write(NfcController &controller);
  void fire_pending_write(NfcController &controller, const Handlers &h,
                          void *ctx);

  bool present_;
  TagInfo current_;
  uint8_t miss_;
  uint8_t miss_threshold_;

  bool write_pending_;
  uint8_t write_start_page_;
  size_t write_len_;
  uint8_t write_data_[kNfcMaxPayloadBytes];
};
