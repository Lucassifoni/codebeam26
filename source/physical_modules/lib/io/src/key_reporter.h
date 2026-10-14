#pragma once

#include <stdint.h>

/// @file
/// Decides whether a bank of keys reports its state or its transitions.
///
/// A ButtonBank starts with its committed state zeroed, so any contact already
/// closed at power-on presents as a *transition* a few scans in. For momentary
/// keys that is merely wrong; for the latching switches on the panel board it is
/// a lie about the operator's settings, and both boards must report the same
/// shape. So the first settled scan is announced as a snapshot — committed
/// state, no edges — and only afterwards do transitions become events.
///
/// Pure and hardware-free: the app owns the ButtonBank and the link, this owns
/// the one decision, and a test can drive it without either.

class KeyReporter {
 public:
  /// @param settle_scans scans before the bank's committed state is trustworthy.
  ///        The bank commits a disagreeing input after `debounce_scans` steps,
  ///        so the two should match.
  explicit KeyReporter(uint8_t settle_scans);

  /// @brief Feed one completed scan.
  /// @return true exactly once, on the scan that settles the bank — the caller
  ///         sends one snapshot then, and no events for that scan.
  bool settle();

  /// @brief Whether transitions may now be reported as events. False until the
  ///        settling scan, which is what suppresses the boot burst.
  bool armed() const { return armed_; }

  /// @brief Forget the settling, as after a bus re-init. A host resync asks for
  ///        a snapshot of a bank that is already settled and does not come here.
  void reset();

 private:
  uint8_t settle_scans_;
  uint8_t scans_;
  bool armed_;
};
