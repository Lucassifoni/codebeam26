#pragma once

#include <stddef.h>
#include <stdint.h>

#include "key_matrix.h"
#include "key_reporter.h"

/// @file
/// A scanned key matrix that reports its first settled state and its later
/// transitions — the whole snapshot-vs-events rule, in one place.
///
/// Splitting the rule across a sketch is how it gets wired backwards: scan
/// before settle and the boot burst escapes, settle before scan and the
/// snapshot describes a table nobody has read yet. Both mistakes compile, both
/// look like a panel fault, and neither is visible in a diff. So the order
/// lives here and the sketch cannot hold it wrong — the same reasoning that put
/// the '165's sampling edge inside SpiShiftInputBus.
///
/// It matters most on a panel of *latching* switches, where most contacts are
/// closed at any time: reported as edges, the state a board wakes up in would
/// fire a real command per closed switch, on every reset — and the host resets
/// the board merely by opening the serial port.
///
/// Hardware-free: the matrix owns the buses, this owns the decision, and a test
/// drives both through fakes.

class KeyPanel {
 public:
  /// @brief Receives a packed committed table. Bit index is
  ///        `drive * senses + sense`.
  using SnapshotHandler = void (*)(const uint8_t *bits, size_t bytes, void *ctx);

  /// Ceiling on matrix size, in snapshot bytes: 512 crosspoints.
  static constexpr size_t kMaxSnapshotBytes = 64;

  /// @param settle_scans scans before the matrix's committed table is
  ///        trustworthy — match it to the matrix's `press_scans`, which is what
  ///        decides when a closed contact has become a committed one.
  KeyPanel(KeyMatrix &keys, uint8_t settle_scans);

  /// @brief Run one scan. Before the panel settles, transitions are dropped and
  ///        `on_snapshot` fires exactly once, on the settling scan; afterwards
  ///        every transition reaches `on_event` and no snapshot is sent.
  ///        Either handler may be null.
  void step(KeyEventHandler on_event, SnapshotHandler on_snapshot, void *ctx);

  /// @brief Send the committed table again, on the host's request. Does not
  ///        disturb the scan sequence, and works whether or not the panel has
  ///        settled — a host asking for truth gets the best available.
  void resync(SnapshotHandler on_snapshot, void *ctx);

  /// @brief Whether transitions are being reported yet.
  bool armed() const { return reporter_.armed(); }

  /// @brief Forget the settling, as after a bus re-init: the next scans are
  ///        silent again and the one that settles sends a fresh snapshot.
  void reset() { reporter_.reset(); }

  /// @brief Bytes a snapshot of this panel occupies.
  size_t snapshot_bytes() const;

 private:
  struct Trampoline {
    KeyPanel *panel;
    KeyEventHandler on_event;
    void *ctx;
  };

  static void on_scan_event(const KeyEvent &event, void *ctx);

  KeyMatrix &keys_;
  KeyReporter reporter_;
};
