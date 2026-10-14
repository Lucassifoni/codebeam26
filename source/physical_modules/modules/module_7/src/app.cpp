#define MODULE_ID 0x07

#include "app.h"

#include <Arduino.h>
#include <SPI.h>

#include <string.h>

#include <key_matrix.h>
#include <key_panel.h>
#include <key_snapshot.h>
#include <link.h>
#include <protocol.h>
#include <spi_shift_bus.h>

/// @file
/// module_7: the switch panel — 30 latching switches in one 5x6 diode matrix,
/// and 60 directly driven LEDs (two per switch) on a chain of eight 595s.
///
/// The firmware is semantic-free, like module_3: it reports the raw
/// (drive, sense) crosspoint and writes whatever bitmap the host sends. It
/// holds no map from channel to switch, because there is none to hold — the
/// host's claim walk discovers which LED belongs to which switch at the bench,
/// so a swapped pigtail is re-registered rather than re-soldered.
///
/// Every bus is sized to **whole chips** rather than to the wires actually
/// landed: a row on Q5-Q7, a column on D6/D7 or an LED on a spare output must
/// still be inside the bus, or a mis-landed wire is silently dead instead of
/// merely permuted. The cost is three empty drive steps per scan.
///
/// The widths fix the Snapshot layout (drive * 8 + sense), which is shared with
/// the host codec and nowhere else.
///
/// One SPI bus, six pins: SCK + MOSI (drive 595 and the LED chain, in
/// parallel) + MISO (sense 165) + three selects. The LED chain is written only
/// on command, so nothing contends for the bus.
///
/// Wiring, chip-by-chip landing tables and bring-up order:
/// docs_and_plans/guides/module_7-wiring.md
///
/// Protocol (frame body after the module discriminant byte):
///   host -> device  Ping        (0x11)                            : -> Pong
///   host -> device  SetLeds     (0x12) + 8 B (bit = LED channel)
///   host -> device  RequestSync (0x16)                       : -> Snapshot
///   device -> host  Pong        (0x81)
///   device -> host  KeyEvent    (0x82) + drive + sense + pressed
///   device -> host  Snapshot    (0x88) + 8 B (bit = drive * 8 + sense)

namespace {

// Whole chips, not wired lines: one 595 drives the five rows, one 165 reads the
// six columns, eight 595s source the sixty LEDs over 64 outputs.
constexpr size_t kDrives = 8;
constexpr size_t kSenses = 8;
constexpr size_t kLedCount = 64;

// A latching switch holds its contact mechanically, so neither edge fights a
// marginal contact the way module_3's worn keys do; this only has to outlast
// ordinary bounce. 25 x 2 ms = 50 ms.
constexpr uint8_t kReleaseScans = 25;

// Two consecutive closed readings to commit a press. A phantom press here is a
// phantom *toggle* on the trigger grid — an OpenType feature flipping on its
// own — and the price is one scan of latency on a switch someone has just
// thrown by hand.
constexpr uint8_t kPressScans = 2;
constexpr unsigned long kScanIntervalMs = 2;

constexpr int8_t kSck = 14, kMosi = 13, kMiso = 39;  // 39 = VN, input only
constexpr uint8_t kLedLatch = 25;                    // LED chain RCLK
constexpr uint8_t kSenseLoad = 26;                   // 165 /SH-LD
constexpr uint8_t kDriveLatch = 33;                  // drive 595 RCLK

// Rows are driven low one at a time, columns are pulled up and read low when
// closed; the LED chain sources its anodes, so there high is lit.
constexpr bool kDriveActiveLow = true;
constexpr bool kSenseActiveLow = true;
constexpr bool kLedActiveLow = false;

enum class Command : uint8_t {
  Ping = 0x11,
  SetLeds = 0x12,
  RequestSync = 0x16,
};

enum class Report : uint8_t {
  Pong = 0x81,
  KeyEvent = 0x82,
  Snapshot = 0x88,
};

constexpr size_t kLedBytes = (kLedCount + 7) / 8;
constexpr size_t kSnapshotBytes = key_snapshot::bytes(kDrives, kSenses);

SPIClass g_spi(HSPI);
SPISettings g_spi_settings(8000000, MSBFIRST, SPI_MODE0);

SpiShiftOutputBus g_drive(g_spi, kDriveLatch, kDrives, g_spi_settings,
                          kDriveActiveLow);
SpiShiftOutputBus g_leds(g_spi, kLedLatch, kLedCount, g_spi_settings,
                         kLedActiveLow);

// No SPISettings: SpiShiftInputBus owns the '165's sampling edge and clock,
// because getting those wrong looks exactly like a wiring fault. Two boards
// lost an afternoon each to it before the class took them over.
SpiShiftInputBus g_sense(g_spi, kSenseLoad, kSenses, kSenseActiveLow);

uint8_t g_stable[KeyMatrix::stable_bytes(kDrives, kSenses)];
uint8_t g_counters[KeyMatrix::counter_bytes(kDrives, kSenses)];
KeyMatrix g_keys(g_drive, g_sense, kReleaseScans, g_stable, g_counters,
                 kPressScans);

// The committed table is worth announcing once a press has had its kPressScans
// readings to commit. KeyPanel owns the order of scan-then-settle, so this
// sketch cannot get the boot burst wrong.
KeyPanel g_panel(g_keys, kPressScans);

unsigned long g_last_scan_ms = 0;

// Columns are pulled up through 10k and run the width of two panels, so a
// column held low by a key on the previous drive step needs time to climb back
// before the next row is sampled. module_3 needed 100 us on a bigger panel;
// this one is a third of the wire, and 6 drive steps x 100 us still fits well
// inside the 2 ms scan.
void settle() { delayMicroseconds(100); }

// Everything closed at power-on would otherwise arrive as a press that never
// happened — 18 spurious feature toggles on every port open, since opening the
// port pulses DTR and resets the board. KeyPanel drops those transitions and
// sends this instead, which says the same thing without lying about when it
// started.
void send_snapshot(const uint8_t *bits, size_t bytes, void *) {
  uint8_t payload[1 + kSnapshotBytes];
  payload[0] = static_cast<uint8_t>(Report::Snapshot);
  const size_t n = bytes < kSnapshotBytes ? bytes : kSnapshotBytes;
  memcpy(&payload[1], bits, n);
  serial_link::send_frame(payload, 1 + n);
}

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
    // A flat bitmap over all 64 outputs, written out as it arrived: which
    // channel lights which switch is the host's business entirely.
    case Command::SetLeds:
      if (length >= 1 + kLedBytes) {
        g_leds.write(&command[1]);
      }
      break;
    case Command::RequestSync:
      g_panel.resync(send_snapshot, nullptr);
      break;
  }
}

}  // namespace

void app_setup() {
  serial_link::begin(proto::kBaud, proto::kModuleId);

  g_spi.begin(kSck, kMiso, kMosi, -1);
  g_drive.begin();
  g_leds.begin();
  g_sense.begin();
  g_keys.set_settle(settle);

  // A 595 powers up holding whatever its register happened to come up with, and
  // a reset here is also a reset the host caused by opening the port. Blank the
  // panel until the host re-sends its frame.
  const uint8_t dark[kLedBytes] = {0};
  g_leds.write(dark);
}

void app_loop() {
  serial_link::poll(apply_command);

  const unsigned long now = millis();
  if (now - g_last_scan_ms < kScanIntervalMs) {
    return;
  }
  g_last_scan_ms = now;

  g_panel.step(on_key_event, send_snapshot, nullptr);
}
