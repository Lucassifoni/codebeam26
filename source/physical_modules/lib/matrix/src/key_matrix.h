#pragma once

#include <stddef.h>
#include <stdint.h>

#include "bit_bus.h"

/// @file
/// Anti-ghost key-matrix scanner. Drives one line of `drive` active at a time
/// (one-hot), reads all `sense` lines, and records the full pressed table. Every
/// key is assumed to have its own diode, so simultaneous presses are
/// unambiguous (full N-key rollover) — no ghost masking is needed.
///
/// Debounce is asymmetric, because press and release are not the same problem.
///
/// A press commits on the **first** closed reading, so press latency is one scan
/// whatever the switch does afterwards. A release requires `release_scans`
/// **consecutive** open readings, and any closed reading in between restarts the
/// run.
///
/// That asymmetry is what makes a marginal contact usable. A worn or dirty
/// switch does not bounce briefly and settle — it re-opens repeatedly for as
/// long as it is held, so no symmetric rule works: treat one open reading as a
/// release and the key chatters, wait for stability on the press edge and a
/// quick tap is swallowed. Holding the press until a sustained absence proves
/// otherwise gets both, and it subsumes ordinary press bounce for free, since
/// bounce is exactly a run of opens too short to qualify.
///
/// The cost is release latency, and a floor on how fast one key can be retyped.
/// `release_scans` should comfortably exceed the longest gap a held contact
/// leaves open.
///
/// `press_scans` defaults to 1 — commit immediately — which is right when the
/// only noise is bounce. Raise it where a *press* can be spurious: on a large
/// panel a sense line that has not recovered before the next drive is sampled
/// smears the previous key onto its neighbour, and because a committed press is
/// then held for the whole release run, a single bad reading becomes a phantom
/// keystroke. Requiring two consecutive closed readings costs one scan of
/// latency and rejects any smear narrower than the gap between drive steps.
///
/// Storage is caller-owned.

struct KeyEvent {
  uint16_t drive;
  uint16_t sense;
  bool pressed;
};

/// @brief Invoked once per debounced press/release transition during scan().
using KeyEventHandler = void (*)(const KeyEvent &event, void *ctx);

class KeyMatrix {
 public:
  /// Caller buffers: `stable_bits` is stable_bytes(D,S); `counters` is
  /// counter_bytes(D,S). Both should start zeroed.
  KeyMatrix(OutputBus &drive, InputBus &sense, uint8_t release_scans,
            uint8_t *stable_bits, uint8_t *counters, uint8_t press_scans = 1);

  /// @brief Optional settling callback invoked after driving each line and
  ///        before sampling, for RC/diode settle on hardware (e.g. a
  ///        delayMicroseconds shim). Default none. Function pointer keeps the
  ///        class free of Arduino dependencies.
  void set_settle(void (*settle)()) { settle_ = settle; }

  /// @brief Run one full scan over all drive lines, updating debounce state and
  ///        emitting transition events. `on_event` may be null.
  void scan(KeyEventHandler on_event, void *ctx);

  bool pressed(size_t drive, size_t sense) const;

  size_t drives() const { return drive_.width(); }
  size_t senses() const { return sense_.width(); }

  static constexpr size_t stable_bytes(size_t drives, size_t senses) {
    return (drives * senses + 7) / 8;
  }
  static constexpr size_t counter_bytes(size_t drives, size_t senses) {
    return drives * senses;
  }

  /// @brief Per-axis line cap (bytes of one-hot/sense scratch on the stack).
  static constexpr size_t kMaxAxisBytes = 32;  // up to 256 lines per axis

 private:
  size_t key_index(size_t drive, size_t sense) const {
    return drive * sense_.width() + sense;
  }

  OutputBus &drive_;
  InputBus &sense_;
  uint8_t release_scans_;
  uint8_t press_scans_;
  uint8_t *stable_;
  uint8_t *counters_;
  void (*settle_)() = nullptr;
};
