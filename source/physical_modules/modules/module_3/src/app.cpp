#define MODULE_ID 0x03

#include "app.h"

#include <Arduino.h>
#include <SPI.h>

#include <key_matrix.h>
#include <link.h>
#include <protocol.h>
#include <spi_shift_bus.h>

/// @file
/// module_3: a clustered ~196-key keyboard as a 16 drive x 32 sense matrix over
/// shift registers. The keys sit in five irregular islands, but the matrix is
/// one panel-wide grid: a drive line is a physical panel row, a sense line a
/// physical panel column, and a key's address is simply where it sits. 9 rows
/// and 28 columns are used, provisioned to whole shift registers (see
/// docs_and_plans/.../module_3.md).
///
/// The firmware is semantic-free: it reports the raw (drive, sense) crosspoint
/// as an opaque key ID and holds no per-board map. The host binds key ID ->
/// meaning at commissioning by dynamic registration ("press a key, write its
/// meaning"), so re-wiring is simply re-registered. This sketch is therefore
/// byte-identical on every module_3 board. Unwired crosspoints have no switch
/// and never fire, so the sparse layout needs no filtering.
///
/// Single SPI bus (keys only, no LED refresh contending): SCK + MOSI (2x 595
/// drive chain out) + MISO (4x 165 sense chain in) + 595 latch + 165 load =
/// 5 pins.
///
/// Protocol (frame body after the module discriminant byte):
///   host -> device  Ping     (0x11)                            : -> Pong
///   device -> host  Pong     (0x81)
///   device -> host  KeyEvent (0x82) + drive + sense + pressed  : per transition

namespace {

// 9 panel rows and 28 panel columns are wired; the buses are sized to whole
// shift registers (2x 595, 4x 165). Spare lines carry no switch and never fire,
// but unused 165 inputs must still be pulled up or they report phantom keys.
constexpr size_t kDrives = 16;
constexpr size_t kSenses = 32;
// KeyMatrix debounce is leading-edge: the first scan that sees a change fires,
// then the key is ignored for this many scans while the contact settles. So this
// only has to exceed the bounce duration — it costs no press latency, only a
// floor on how soon a release can follow its press. These switches were seen
// chattering across ~50 ms, so 25 scans x 2 ms = 50 ms, and being generous here
// is nearly free.
// A release is only believed after this many *consecutive* open readings; a
// press commits on the first closed one. 50 x 2 ms = 100 ms, chosen against a
// measurement: a held key on this panel re-opens on a regular ~16 ms cycle, so
// the run has to be comfortably longer than that gap to read as one press. The
// cost is 100 ms of release latency and a floor on retyping one key, neither of
// which matters here. This is a filter over a marginal contact, not a fix for
// it — see docs_and_plans/work/todo/debounce-rollout.md.
constexpr uint8_t kReleaseScans = 50;

// 1 = commit a press on the first closed reading.
//
// 2 was tried and killed every key on the panel. The run must be *consecutive*,
// and these contacts read closed only intermittently while held — which the
// release hold-off hides, since a press that never completes a release run
// looks like a clean hold. So a press filter cannot assume a solid closure here;
// smear has to be rejected by settling longer instead, which costs scan rate
// rather than presses.
constexpr uint8_t kPressScans = 1;
constexpr unsigned long kScanIntervalMs = 2;

// === EDIT FOR YOUR WIRING. Example pins; avoid GPIO1/3 (UART0) and mind
// strapping/input-only pins. SPI can be remapped to most GPIOs. ===
constexpr int8_t kSck = 14, kMosi = 13, kMiso = 34;  // single key SPI bus
constexpr uint8_t kDriveLatch = 25;                  // 595 chain latch
constexpr uint8_t kSenseLoad = 26;                   // 165 chain load

// Selected drive row is driven LOW, senses are pulled up, pressed reads LOW.
// This must agree with the diode orientation and pull-ups on the board.
constexpr bool kDriveActiveLow = true;
constexpr bool kSenseActiveLow = true;

enum class Command : uint8_t {
  Ping = 0x11,
};

enum class Report : uint8_t {
  Pong = 0x81,
  KeyEvent = 0x82,
};

SPIClass g_key_spi(HSPI);
SPISettings g_spi_settings(8000000, MSBFIRST, SPI_MODE0);

SpiShiftOutputBus g_drive(g_key_spi, kDriveLatch, kDrives, g_spi_settings,
                          kDriveActiveLow);

// The sense chain reads on the opposite clock edge from the drive chain, and at
// a lower rate. Neither is stated here any more: SpiShiftInputBus owns both,
// because the reason is the '165's own timing rather than anything about this
// board. That comment used to live here, and module_2 was wired, built and
// debugged without it — which is how the same afternoon got spent twice.
SpiShiftInputBus g_sense(g_key_spi, kSenseLoad, kSenses, kSenseActiveLow);

uint8_t g_stable[KeyMatrix::stable_bytes(kDrives, kSenses)];
uint8_t g_counters[KeyMatrix::counter_bytes(kDrives, kSenses)];
KeyMatrix g_keys(g_drive, g_sense, kReleaseScans, g_stable, g_counters,
                 kPressScans);

unsigned long g_last_scan_ms = 0;

// Panel-wide sense lines are long and pulled up through 10k, so the release
// edge between drive steps is the slow one: a sense held low by a key on the
// previous drive has to climb back to a valid logic high before the next drive
// is sampled, or that key smears onto its neighbour and briefly reports a
// crosspoint nobody pressed. 20 us was sized for a bare board; a fully wired
// panel adds the diode junction capacitance of every key on the column plus the
// harness, and brief phantom presses on remote keys were showing up. 100 us is
// 5x the margin and still fits: 16 drive steps x 100 us = 1.6 ms, inside the
// 2 ms scan interval, so the scan rate is unchanged.
void settle() { delayMicroseconds(100); }

void on_key_event(const KeyEvent &event, void *) {
  const uint8_t payload[1 + 3] = {
      static_cast<uint8_t>(Report::KeyEvent),
      static_cast<uint8_t>(event.drive),
      static_cast<uint8_t>(event.sense),
      static_cast<uint8_t>(event.pressed ? 1 : 0),
  };
  serial_link::send_frame(payload, sizeof(payload));
}

void apply_command(const uint8_t *command, size_t length) {
  if (length == 0) {
    return;
  }
  switch (static_cast<Command>(command[0])) {
    case Command::Ping: {
      const uint8_t pong = static_cast<uint8_t>(Report::Pong);
      serial_link::send_frame(&pong, sizeof(pong));
      break;
    }
  }
}

}  // namespace

void app_setup() {
  serial_link::begin(proto::kBaud, proto::kModuleId);

  g_key_spi.begin(kSck, kMiso, kMosi, -1);
  g_drive.begin();
  g_sense.begin();
  g_keys.set_settle(settle);
}

void app_loop() {
  serial_link::poll(apply_command);

  const unsigned long now = millis();
  if (now - g_last_scan_ms < kScanIntervalMs) {
    return;
  }
  g_last_scan_ms = now;

  g_keys.scan(on_key_event, nullptr);
}
