#include <cstdio>
#include <vector>

#include "fake_bus.h"
#include "key_matrix.h"
#include "key_panel.h"
#include "key_snapshot.h"

/// @file
/// Host unit tests for module_7's snapshot-vs-events rule and its 8x8 merged
/// matrix, driven through fake buses. Run via `make test`.
///
/// The board is two physical panels (6x3 and 6x2) wired as one 5x6 matrix, and
/// the buses are sized to whole chips — 8 x 8 — so that a row, column or LED
/// landed on a spare pin is still inside the bus. These tests exercise the
/// spare lines deliberately for that reason.

namespace {

int g_failures = 0;

void expect(const char *name, bool cond) {
  if (cond) {
    printf("ok   - %s\n", name);
  } else {
    g_failures++;
    printf("FAIL - %s\n", name);
  }
}

constexpr size_t kDrives = 8;
constexpr size_t kSenses = 8;
constexpr uint8_t kPressScans = 2;
constexpr uint8_t kReleaseScans = 2;

struct Recorder {
  std::vector<KeyEvent> events;
  std::vector<std::vector<uint8_t>> snapshots;

  void clear() {
    events.clear();
    snapshots.clear();
  }

  bool saw(size_t drive, size_t sense, bool pressed) const {
    for (const KeyEvent &event : events) {
      if (event.drive == drive && event.sense == sense &&
          event.pressed == pressed) {
        return true;
      }
    }
    return false;
  }
};

void rec_event(const KeyEvent &event, void *ctx) {
  static_cast<Recorder *>(ctx)->events.push_back(event);
}

void rec_snapshot(const uint8_t *bits, size_t bytes, void *ctx) {
  static_cast<Recorder *>(ctx)->snapshots.emplace_back(bits, bits + bytes);
}

bool bit_at(const std::vector<uint8_t> &bits, size_t drive, size_t sense) {
  const size_t index = drive * kSenses + sense;
  return (bits[index >> 3] >> (index & 7)) & 1u;
}

/// One matrix, one panel, and the buffers they need. Assembled exactly as the
/// sketch assembles them, so what the tests drive is what the board runs.
struct Bench {
  ScriptedKeyIo io{kDrives, kSenses};
  uint8_t stable[KeyMatrix::stable_bytes(kDrives, kSenses)] = {0};
  uint8_t counters[KeyMatrix::counter_bytes(kDrives, kSenses)] = {0};
  KeyMatrix keys{io.drive(),  io.sense(), kReleaseScans,
                 stable,      counters,   kPressScans};
  KeyPanel panel{keys, kPressScans};
  Recorder rec;

  void step(int times = 1) {
    for (int i = 0; i < times; i++) {
      panel.step(rec_event, rec_snapshot, &rec);
    }
  }
};

// The one that matters on a latching panel: a board that wakes with switches
// already closed must describe them, not replay them as presses nobody made.
void test_boot_state_is_a_snapshot_not_events() {
  Bench bench;
  bench.io.press(0, 0, true);
  bench.io.press(2, 4, true);
  bench.io.press(4, 5, true);

  bench.step();
  expect("first scan is silent", bench.rec.events.empty());
  expect("first scan sends no snapshot", bench.rec.snapshots.empty());

  bench.step();
  expect("settling scan sends exactly one snapshot",
         bench.rec.snapshots.size() == 1);
  expect("settling scan emits no events", bench.rec.events.empty());

  const std::vector<uint8_t> &snap = bench.rec.snapshots[0];
  expect("snapshot is 8 bytes", snap.size() == 8);
  expect("snapshot carries the closed switches",
         bit_at(snap, 0, 0) && bit_at(snap, 2, 4) && bit_at(snap, 4, 5));
  expect("snapshot carries nothing else",
         !bit_at(snap, 0, 1) && !bit_at(snap, 3, 4) && !bit_at(snap, 7, 7));

  bench.rec.clear();
  bench.step(3);
  expect("no further snapshots once settled", bench.rec.snapshots.empty());
}

void test_transitions_after_settling_are_events() {
  Bench bench;
  bench.step(2);
  bench.rec.clear();

  bench.io.press(1, 3, true);
  bench.step(kPressScans);
  expect("a press after settling is an event", bench.rec.saw(1, 3, true));
  expect("a press after settling sends no snapshot",
         bench.rec.snapshots.empty());

  bench.rec.clear();
  bench.io.press(1, 3, false);
  bench.step(kReleaseScans);
  expect("a release after settling is an event", bench.rec.saw(1, 3, false));
}

// A host that has lost track asks for the truth; asking must not cost it the
// next transition, and must not re-arm the boot suppression.
void test_resync_snapshots_without_disturbing_the_scan() {
  Bench bench;
  bench.io.press(3, 2, true);
  bench.step(2);
  bench.rec.clear();

  bench.panel.resync(rec_snapshot, &bench.rec);
  expect("resync sends one snapshot", bench.rec.snapshots.size() == 1);
  expect("resync reports the committed table",
         bit_at(bench.rec.snapshots[0], 3, 2));
  expect("resync emits no events", bench.rec.events.empty());

  bench.rec.clear();
  bench.io.press(0, 6, true);
  bench.step(kPressScans);
  expect("the scan after a resync still reports", bench.rec.saw(0, 6, true));
  expect("the scan after a resync sends no snapshot",
         bench.rec.snapshots.empty());
}

// 30 switches over a matrix provisioned to 64 crosspoints, latched down at the
// same time — which is the normal state of this panel, not an edge case.
void test_thirty_latched_switches_stay_independent() {
  Bench bench;
  bench.step(2);
  bench.rec.clear();

  std::vector<std::pair<size_t, size_t>> wired;
  for (size_t drive = 0; drive < 5; drive++) {
    for (size_t sense = 0; sense < 6; sense++) {
      wired.emplace_back(drive, sense);
    }
  }

  for (const auto &key : wired) {
    bench.io.press(key.first, key.second, true);
    bench.step(kPressScans);
  }

  expect("every latched switch reported its own press", [&] {
    for (const auto &key : wired) {
      if (!bench.rec.saw(key.first, key.second, true)) {
        return false;
      }
    }
    return true;
  }());
  expect("30 presses, no more", bench.rec.events.size() == wired.size());

  bench.rec.clear();
  bench.panel.resync(rec_snapshot, &bench.rec);
  const std::vector<uint8_t> &snap = bench.rec.snapshots[0];
  expect("all 30 read back independently", [&] {
    for (const auto &key : wired) {
      if (!bit_at(snap, key.first, key.second)) {
        return false;
      }
    }
    return true;
  }());
}

// A wire landed on a spare pin is a permutation the host absorbs — but only if
// the firmware scans it at all.
void test_spare_lines_are_live() {
  Bench bench;
  bench.step(2);
  bench.rec.clear();

  bench.io.press(7, 7, true);
  bench.io.press(5, 6, true);
  bench.step(kPressScans);

  expect("a switch on the last spare crosspoint reports",
         bench.rec.saw(7, 7, true));
  expect("a switch on a spare drive and sense reports",
         bench.rec.saw(5, 6, true));
}

// The layout the host codec decodes. Shared with
// test/bbparty/bus/module7_test.exs, and with nothing else.
void test_snapshot_layout() {
  Bench bench;
  bench.io.press(0, 0, true);
  bench.io.press(1, 0, true);
  bench.io.press(4, 5, true);
  bench.io.press(7, 7, true);
  bench.step(2);

  const std::vector<uint8_t> &snap = bench.rec.snapshots[0];
  expect("bit = drive * 8 + sense, byte-exact",
         snap[0] == 0x01 && snap[1] == 0x01 && snap[4] == 0x20 &&
             snap[7] == 0x80);
  expect("untouched bytes are zero",
         snap[2] == 0 && snap[3] == 0 && snap[5] == 0 && snap[6] == 0);
}

void test_snapshot_pack_is_independent_of_the_panel() {
  ScriptedKeyIo io{kDrives, kSenses};
  uint8_t stable[KeyMatrix::stable_bytes(kDrives, kSenses)] = {0};
  uint8_t counters[KeyMatrix::counter_bytes(kDrives, kSenses)] = {0};
  KeyMatrix keys{io.drive(), io.sense(), kReleaseScans,
                 stable,     counters,   kPressScans};

  io.press(2, 1, true);
  keys.scan(nullptr, nullptr);
  keys.scan(nullptr, nullptr);

  uint8_t bits[key_snapshot::bytes(kDrives, kSenses)];
  key_snapshot::pack(keys, bits, sizeof(bits));
  expect("pack sizes to the matrix", sizeof(bits) == 8);
  expect("pack sets the committed crosspoint", bits[2] == 0x02);

  // A caller that under-sizes its buffer loses the tail rather than the stack.
  uint8_t truncated[2] = {0xFF, 0xFF};
  key_snapshot::pack(keys, truncated, sizeof(truncated));
  expect("pack clears what it can reach",
         truncated[0] == 0x00 && truncated[1] == 0x00);
}

}  // namespace

int main() {
  test_boot_state_is_a_snapshot_not_events();
  test_transitions_after_settling_are_events();
  test_resync_snapshots_without_disturbing_the_scan();
  test_thirty_latched_switches_stay_independent();
  test_spare_lines_are_live();
  test_snapshot_layout();
  test_snapshot_pack_is_independent_of_the_panel();

  if (g_failures == 0) {
    printf("\nAll module_7 tests passed.\n");
    return 0;
  }
  printf("\n%d module_7 test(s) failed.\n", g_failures);
  return 1;
}
