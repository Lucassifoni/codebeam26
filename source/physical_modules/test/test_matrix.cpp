#include <cstdio>
#include <vector>

#include "bit_view.h"
#include "fake_bus.h"
#include "key_matrix.h"
#include "led_matrix.h"

/// @file
/// Host unit tests for the pure matrix logic (BitView, KeyMatrix, LedMatrix),
/// driven through fake buses. Run via `make test`.

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

void test_bit_view_pack() {
  uint8_t bytes[4] = {0, 0, 0, 0};
  BitView v(bytes, 30);

  expect("BitView byte_count for 30 bits", v.byte_count() == 4);
  expect("BitView size", v.size() == 30);

  v.set(0, true);
  v.set(8, true);
  v.set(29, true);
  expect("bit 0 set -> byte0 lsb", bytes[0] == 0x01);
  expect("bit 8 set -> byte1 lsb", bytes[1] == 0x01);
  expect("bit 29 set -> byte3 bit5", bytes[3] == 0x20);
  expect("get reads back set bits", v.get(0) && v.get(8) && v.get(29));
  expect("get on unset bit is false", !v.get(1) && !v.get(15));

  v.set(0, false);
  expect("clearing a bit", !v.get(0) && bytes[0] == 0x00);

  v.set(100, true);
  expect("out-of-range set is ignored", !v.get(100));

  v.set(8, true);
  v.clear();
  expect("clear zeroes all bytes",
         bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0);
}

struct EventLog {
  std::vector<KeyEvent> events;
};

void collect(const KeyEvent &e, void *ctx) {
  static_cast<EventLog *>(ctx)->events.push_back(e);
}

void test_key_one_hot_drive() {
  FakeOutputBus drive(5);
  FakeInputBus sense(6);
  uint8_t stable[KeyMatrix::stable_bytes(5, 6)] = {0};
  uint8_t counters[KeyMatrix::counter_bytes(5, 6)] = {0};
  KeyMatrix keys(drive, sense, 1, stable, counters);

  keys.scan(nullptr, nullptr);

  bool ok = drive.writes.size() == 5;
  for (size_t d = 0; d < drive.writes.size(); d++) {
    if (drive.one_hot_index(drive.writes[d]) != static_cast<int>(d)) ok = false;
  }
  expect("scan drives each line one-hot in order", ok);
}

void test_key_debounce_and_events() {
  ScriptedKeyIo io(5, 6);
  uint8_t stable[KeyMatrix::stable_bytes(5, 6)] = {0};
  uint8_t counters[KeyMatrix::counter_bytes(5, 6)] = {0};
  KeyMatrix keys(io.drive(), io.sense(), 3, stable, counters);

  EventLog log;
  io.press(2, 4, true);

  keys.scan(collect, &log);
  expect("press fires on the first scan that sees it", log.events.size() == 1);
  expect("press event carries (2,4,pressed)",
         log.events.size() == 1 && log.events[0].drive == 2 &&
             log.events[0].sense == 4 && log.events[0].pressed);
  expect("pressed() reflects committed state", keys.pressed(2, 4));

  io.press(2, 4, false);
  keys.scan(collect, &log);
  keys.scan(collect, &log);
  expect("release waits for a full run of open readings",
         log.events.size() == 1);
  expect("still committed as pressed mid-run", keys.pressed(2, 4));

  keys.scan(collect, &log);
  expect("release fires on the third consecutive open reading",
         log.events.size() == 2);
  expect("release event is not-pressed",
         log.events.size() == 2 && !log.events[1].pressed);
  expect("pressed() cleared after release", !keys.pressed(2, 4));
}

void test_key_bounce_is_swallowed_by_the_release_run() {
  ScriptedKeyIo io(5, 6);
  uint8_t stable[KeyMatrix::stable_bytes(5, 6)] = {0};
  uint8_t counters[KeyMatrix::counter_bytes(5, 6)] = {0};
  KeyMatrix keys(io.drive(), io.sense(), 3, stable, counters);

  EventLog log;
  io.press(0, 0, true);
  keys.scan(collect, &log);  // commits the press

  io.press(0, 0, false);     // contact chatters...
  keys.scan(collect, &log);
  io.press(0, 0, true);
  keys.scan(collect, &log);
  io.press(0, 0, false);
  keys.scan(collect, &log);
  io.press(0, 0, true);      // ...and settles closed
  keys.scan(collect, &log);

  expect("chatter never completes a release run", log.events.size() == 1);
  expect("the key is still committed as pressed", keys.pressed(0, 0));
}

void test_key_marginal_contact_stays_pressed() {
  // A worn contact re-opens repeatedly for as long as the key is held. Two open
  // scans then a closed one, over and over, must read as one continuous press.
  ScriptedKeyIo io(5, 6);
  uint8_t stable[KeyMatrix::stable_bytes(5, 6)] = {0};
  uint8_t counters[KeyMatrix::counter_bytes(5, 6)] = {0};
  KeyMatrix keys(io.drive(), io.sense(), 4, stable, counters);

  EventLog log;
  io.press(1, 1, true);
  keys.scan(collect, &log);

  for (int cycle = 0; cycle < 20; cycle++) {
    io.press(1, 1, false);
    keys.scan(collect, &log);
    keys.scan(collect, &log);
    io.press(1, 1, true);
    keys.scan(collect, &log);
  }

  expect("a flickering held contact reports one press and no release",
         log.events.size() == 1 && log.events[0].pressed);
  expect("still committed as pressed after the flicker", keys.pressed(1, 1));

  io.press(1, 1, false);
  for (int i = 0; i < 4; i++) {
    keys.scan(collect, &log);
  }

  expect("a real release still completes the run", log.events.size() == 2);
  expect("and is reported as not-pressed", !keys.pressed(1, 1));
}

void test_key_press_run_rejects_a_smear() {
  // A sense line that has not recovered between drive steps reports a key that
  // is not pressed, for a single scan. With press_scans = 2 it never commits,
  // so it cannot become a phantom keystroke held for the whole release run.
  ScriptedKeyIo io(5, 6);
  uint8_t stable[KeyMatrix::stable_bytes(5, 6)] = {0};
  uint8_t counters[KeyMatrix::counter_bytes(5, 6)] = {0};
  KeyMatrix keys(io.drive(), io.sense(), 10, stable, counters, 2);

  EventLog log;

  io.press(3, 2, true);
  keys.scan(collect, &log);
  io.press(3, 2, false);
  keys.scan(collect, &log);

  expect("a one-scan reading never commits", log.events.empty());
  expect("and leaves no committed state", !keys.pressed(3, 2));

  io.press(3, 2, true);
  keys.scan(collect, &log);
  keys.scan(collect, &log);

  expect("two consecutive readings do commit", log.events.size() == 1);
  expect("committed on the second scan, not the first", keys.pressed(3, 2));
}

void test_key_large_geometry() {
  // module_3 geometry: a 16 drive x 32 sense matrix (11 panel rows and 26 panel
  // columns, provisioned to whole shift registers). Confirms buffer sizing and
  // that a transition reports the raw (drive, sense) address as-is — the
  // firmware's opaque, semantic-free key ID.
  ScriptedKeyIo io(16, 32);
  uint8_t stable[KeyMatrix::stable_bytes(16, 32)] = {0};
  uint8_t counters[KeyMatrix::counter_bytes(16, 32)] = {0};
  KeyMatrix keys(io.drive(), io.sense(), 3, stable, counters);

  expect("16x32 stable buffer is 64 bytes",
         KeyMatrix::stable_bytes(16, 32) == 64);
  expect("16x32 counter buffer is 512 bytes",
         KeyMatrix::counter_bytes(16, 32) == 512);

  EventLog log;
  // sense 25 lives in the fourth sense byte — a width the 5x6 and 24x16
  // geometries never reached.
  io.press(10, 25, true);
  keys.scan(collect, &log);
  keys.scan(collect, &log);
  keys.scan(collect, &log);
  expect("transition at (10,25) yields exactly one event",
         log.events.size() == 1);
  expect("event carries the raw (drive,sense) address + pressed",
         log.events.size() == 1 && log.events[0].drive == 10 &&
             log.events[0].sense == 25 && log.events[0].pressed);
  expect("committed state set at (10,25)", keys.pressed(10, 25));
  expect("an unwired crosspoint never fires", !keys.pressed(0, 0));
}

void test_key_rollover() {
  // Every key has its own diode, so simultaneous presses are unambiguous. Two
  // cases matter on the panel-wide grid: a whole drive rail held at once (up to
  // 26 keys share a row), and one sense column held across several rails.
  ScriptedKeyIo io(16, 32);
  uint8_t stable[KeyMatrix::stable_bytes(16, 32)] = {0};
  uint8_t counters[KeyMatrix::counter_bytes(16, 32)] = {0};
  KeyMatrix keys(io.drive(), io.sense(), 1, stable, counters);

  EventLog row;
  for (size_t s = 0; s < 26; s++) {
    io.press(3, s, true);
  }
  keys.scan(collect, &row);
  expect("26 keys on one drive rail all report", row.events.size() == 26);

  bool all_row = row.events.size() == 26;
  for (size_t i = 0; i < row.events.size(); i++) {
    all_row = all_row && row.events[i].drive == 3 &&
              row.events[i].sense == static_cast<uint16_t>(i) &&
              row.events[i].pressed;
  }
  expect("each carries its own sense index, in scan order", all_row);
  expect("no crosstalk onto a neighbouring rail", !keys.pressed(4, 0));

  EventLog col;
  for (size_t d = 0; d < 16; d++) {
    io.press(d, 30, true);
  }
  keys.scan(collect, &col);
  expect("16 keys on one sense column all report", col.events.size() == 16);

  bool all_col = col.events.size() == 16;
  for (size_t i = 0; i < col.events.size(); i++) {
    all_col = all_col && col.events[i].drive == static_cast<uint16_t>(i) &&
              col.events[i].sense == 30 && col.events[i].pressed;
  }
  expect("each carries its own drive index, in scan order", all_col);
  // (3,0), (3,30) and (4,30) are now all held — the three corners that would
  // fabricate a phantom at (4,0) in a matrix without per-key diodes.
  expect("no ghost at the fourth corner of the pressed rectangle",
         !keys.pressed(4, 0));
}

void test_led_set_get() {
  uint8_t fb[LedMatrix::framebuffer_bytes(5, 6)] = {0};
  FakeOutputBus rows(5);
  FakeOutputBus cols(6);
  LedMatrix leds(rows, cols, fb);

  expect("framebuffer is rows*ceil(cols/8) bytes",
         LedMatrix::framebuffer_bytes(5, 6) == 5);

  leds.set(2, 5, true);
  expect("set/get a pixel", leds.get(2, 5) && !leds.get(2, 4));
  leds.set(2, 5, false);
  expect("clear a pixel", !leds.get(2, 5));
  leds.set(9, 9, true);
  expect("out-of-range set ignored", !leds.get(9, 9));
}

void test_led_refresh_reproduces_framebuffer() {
  uint8_t fb[LedMatrix::framebuffer_bytes(5, 6)] = {0};
  FakeOutputBus rows(5);
  FakeOutputBus cols(6);
  LedMatrix leds(rows, cols, fb);

  leds.set(0, 0, true);
  leds.set(2, 5, true);
  leds.set(4, 3, true);

  for (int i = 0; i < 5; i++) leds.refresh_step();

  bool ok = rows.writes.size() == 10 && cols.writes.size() == 5;

  bool displayed[5][6] = {{false}};
  for (size_t step = 0; step < 5 && ok; step++) {
    const auto &blank = rows.writes[2 * step];
    const auto &enable = rows.writes[2 * step + 1];
    if (rows.one_hot_index(blank) != -1) ok = false;  // -1 == no bit set
    const int row = rows.one_hot_index(enable);
    if (row != static_cast<int>(step)) ok = false;
    for (size_t c = 0; c < 6 && ok; c++) {
      if (cols.bit_in(cols.writes[step], c)) displayed[row][c] = true;
    }
  }
  expect("refresh blanks rows then enables one row per step", ok);
  expect("full cycle reproduces the framebuffer",
         ok && displayed[0][0] && displayed[2][5] && displayed[4][3] &&
             !displayed[0][1] && !displayed[3][3]);
}

}  // namespace

int main() {
  test_bit_view_pack();
  test_key_one_hot_drive();
  test_key_debounce_and_events();
  test_key_bounce_is_swallowed_by_the_release_run();
  test_key_marginal_contact_stays_pressed();
  test_key_press_run_rejects_a_smear();
  test_key_large_geometry();
  test_key_rollover();
  test_led_set_get();
  test_led_refresh_reproduces_framebuffer();

  if (g_failures == 0) {
    printf("\nAll matrix tests passed.\n");
    return 0;
  }
  printf("\n%d matrix test(s) failed.\n", g_failures);
  return 1;
}
