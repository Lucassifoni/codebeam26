#define MODULE_ID 0x02

#include "app.h"

#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/task.h>
#include <SPI.h>
#include <Wire.h>

#include <button_bank.h>
#include <gauge_out.h>
#include <key_reporter.h>
#include <link.h>
#include <mfrc522_i2c_controller.h>
#include <ndef_text.h>
#include <nfc_controller.h>
#include <nfc_session.h>
#include <protocol.h>
#include <quadrature_encoder.h>
#include <spi_shift_bus.h>

/// @file
/// module_2: a mixed peripheral board — 3 analog joysticks (1 axis each), a
/// rotary encoder, 8 pushbuttons + 8 LEDs, 3 analog DC-voltmeter gauges, and an
/// MFRC522 NFC reader on I2C. The joysticks stream raw ADC (the host conditions
/// them); only the ADC/PWM/SPI/I2C touches are Arduino calls here.
///
/// The 8 LEDs and 8 buttons share one SPI bus (a 74HC595 + a 74HC165) rather
/// than 16 GPIOs — module_2 already spends pins on 3 ADC1 inputs, 3 ledc PWMs, 2
/// encoder lines, and the I2C pair. Swap to direct GPIO buses if a board wires
/// them straight.
///
/// The loop runs two cadences: a fast tick (~3 ms) for buttons/encoder and an
/// axis tick (~30 ms) streaming raw joystick ADC. The NFC reader is polled every
/// ~100 ms from its own task on the other core, because a poll blocks for tens
/// of milliseconds on the reader's radio timeouts. Sharing the loop with it cut
/// the key and encoder scan to ~10 Hz: short presses never outlasted the
/// debounce, and the quadrature decoder missed most edges.
///
/// The NFC task alone touches Wire and the reader, and the loop alone touches
/// Serial. Two queues cross between them: WriteTag requests go to the task, and
/// tag reports come back to the loop, which frames them.
///
/// NFC value convention (module-local, pure): each tag stores a short UTF-8
/// string (<= ndef_text::kMaxText) as a single NDEF text record starting at the
/// first user page. The wire carries the plain string; the NDEF layout lives in
/// the pure ndef_text codec. On arrival the record is read and decoded, shipping
/// the string in TagRead; a WriteTag command carries the new string, encoded and
/// written on the next present tag.
///
/// Protocol (frame body after the module discriminant byte):
///   host -> device  Ping          (0x11)                 : -> Pong
///   host -> device  SetLeds       (0x12) + 1 B (8 bits)
///   host -> device  SetGauge      (0x13) + index + value (0..255)
///   host -> device  WriteTag      (0x14) + len + UTF-8 bytes (len <= kMaxText)
///   host -> device  SetBrightness (0x15) + 1 B (0 dark .. 255 full)
///   host -> device  RequestSync   (0x16)                 : -> Snapshot
///   device -> host  Pong        (0x81)
///   device -> host  KeyEvent    (0x82) + index + pressed    on transition
///   device -> host  Axes        (0x83) + 3x uint16 raw ADC (BE)   every ~30ms
///   device -> host  Encoder     (0x84) + 1 signed B (detents)  on detent
///   device -> host  TagRead     (0x85) + uid_len + UID + SAK + len + UTF-8  on arrival
///   device -> host  TagGone     (0x86)                         on removal
///   device -> host  WriteResult (0x87) + status + uid_len + UID after WriteTag
///   device -> host  Snapshot    (0x88) + 1 B (8 bits)      once settled, and
///                                                          on RequestSync
///   device -> host  Fault       (0x8F) + subsystem + index at setup, per part
///                                                          that failed to init,
///                                                          incl. the NFC task
///
/// A Fault's index is a channel number for the gauges, and for the NFC reader a
/// code: 0x00 nothing answered on I2C at all, 0xFF the reader answered but would
/// not initialise, anything else the address of whatever *did* answer.
///
/// Keys report per-index events, never a bitmap: the address is the identity, so
/// all three input boards (0x02, 0x03, 0x07) route the same way host-side and
/// the firmware holds no map. The one exception is the boot state, which is a
/// Snapshot — see KeyReporter for why an edge would be a lie there.

namespace {

constexpr size_t kAxisCount = 3;
constexpr size_t kButtonCount = 8;
constexpr size_t kLedCount = 8;
constexpr size_t kGaugeCount = 3;

constexpr uint8_t kDebounceScans = 3;
constexpr unsigned long kFastTickMs = 3;
constexpr unsigned long kNfcPollMs = 100;
constexpr unsigned long kAxisTickMs = 30;  // raw ADC stream cadence (host conditions)

// === EDIT FOR YOUR WIRING. Placeholder pins; avoid strapping GPIO0/2/5/12/15
// and UART0 GPIO1/3. Input-only GPIO34-39 are used only for inputs (ADC, MISO).
// Shared key/LED SPI bus (HSPI): a 74HC595 (LEDs) + a 74HC165 (buttons).
constexpr int8_t kSck = 14, kMosi = 13, kMiso = 39;  // 39 input-only: 165 -> MCU
constexpr uint8_t kLedLatch = 25, kBtnLoad = 26;
// LED chain brightness: PWM on the '595's active-low /OE. Above 20 kHz because
// this panel gets filmed. A 10k pull-down at the chip holds the outputs enabled
// through reset, before this pin is driven at all.
constexpr uint8_t kLedOe = 27;
constexpr uint32_t kLedOeFreqHz = 25000;
// Gauges: ledc PWM -> 0-3 V voltmeter direct (internal RC; no op-amp/filter).
// Above 20 kHz like the LED /OE, but here to keep the movements quiet: the coil
// sits in a magnet gap and radiates whatever ripple current it carries, so an
// audible-band carrier makes the meters whine.
constexpr uint8_t kGaugePins[kGaugeCount] = {16, 17, 4};
constexpr uint32_t kGaugeFreqHz = 25000;
constexpr uint8_t kGaugeResBits = 8;
// Rotary encoder channels.
constexpr uint8_t kEncA = 18, kEncB = 19;
// NFC reader on I2C (through a bidirectional level shifter; board runs at 5 V).
constexpr uint8_t kSda = 21, kScl = 22;
constexpr uint8_t kNfcAddress = 0x28;
// NTAG21x: the NDEF text record is written from the first user page. A read
// pulls the whole record region (rounded to whole 16-byte reads by the backend).
constexpr uint8_t kNfcNdefStartPage = 4;
constexpr size_t kNfcReadBytes = ndef_text::kMaxEncoded;
// Joysticks on ADC1 (all input-only, fine for analog in).
constexpr uint8_t kAxisPins[kAxisCount] = {34, 35, 36};

// 165 inputs pulled up, pressed reads low; LEDs driven straight (active high).
constexpr bool kBtnActiveLow = true;
constexpr bool kLedActiveLow = false;

enum class Command : uint8_t {
  Ping = 0x11,
  SetLeds = 0x12,
  SetGauge = 0x13,
  WriteTag = 0x14,
  SetBrightness = 0x15,
  RequestSync = 0x16,
};

enum class Report : uint8_t {
  Pong = 0x81,
  KeyEvent = 0x82,
  Axes = 0x83,
  Encoder = 0x84,
  TagRead = 0x85,
  TagGone = 0x86,
  WriteResult = 0x87,
  Snapshot = 0x88,
  Fault = 0x8F,
};

// What failed to initialise, for Fault. A dead peripheral that reports itself is
// a wiring bug; one that stays quiet is an afternoon.
enum class Subsystem : uint8_t {
  Gauge = 0x01,
  LedBrightness = 0x02,
  Nfc = 0x03,
  NfcTask = 0x04,
};

// Fault indices for Subsystem::Nfc.
constexpr uint8_t kNfcNothingAnswered = 0x00;
constexpr uint8_t kNfcInitFailed = 0xFF;

// The reader's radio exchanges and the I2C transfers under them run here, off
// the loop. The stack is sized by hand, not measured: it holds the NDEF record
// buffers and the MFRC522 library's small frames, with margin.
constexpr uint32_t kNfcTaskStackBytes = 4096;
constexpr UBaseType_t kNfcTaskPriority = 1;
// A poll can emit a read, a removal and a write result at once; the loop drains
// every pass, so this only has to absorb a burst.
constexpr UBaseType_t kNfcReportDepth = 8;

SPIClass g_spi(HSPI);
SPISettings g_spi_settings(8000000, MSBFIRST, SPI_MODE0);

SpiShiftOutputBus g_led_bus(g_spi, kLedLatch, kLedCount, g_spi_settings,
                            kLedActiveLow);
// The key bus takes no SPISettings: SpiShiftInputBus owns the '165's sampling
// edge and clock, because that is a fact about the chip and getting it wrong
// looks exactly like a wiring fault. See its class comment.
SpiShiftInputBus g_btn_bus(g_spi, kBtnLoad, kButtonCount, kBtnActiveLow);

uint8_t g_btn_stable[ButtonBank::stable_bytes(kButtonCount)];
uint8_t g_btn_counters[ButtonBank::counter_bytes(kButtonCount)];
ButtonBank g_buttons(g_btn_bus, kDebounceScans, g_btn_stable, g_btn_counters);

// The bank commits a disagreeing input after kDebounceScans steps, so that is
// when its state is worth announcing.
KeyReporter g_key_reporter(kDebounceScans);

QuadratureEncoder g_encoder(4);

GaugeOut g_gauges[kGaugeCount] = {
    GaugeOut(kGaugePins[0], kGaugeFreqHz, kGaugeResBits),
    GaugeOut(kGaugePins[1], kGaugeFreqHz, kGaugeResBits),
    GaugeOut(kGaugePins[2], kGaugeFreqHz, kGaugeResBits),
};

// The LED chain's /OE is a ledc pin driven from a 0..255 duty, which is what
// GaugeOut is. The duty is inverted at the call site: /OE is active low, so a
// duty of 0 is full brightness.
GaugeOut g_led_brightness(kLedOe, kLedOeFreqHz, kGaugeResBits);

Mfrc522I2cController g_nfc_ctrl(kNfcAddress, Wire);
NfcSession g_nfc_session(3);

unsigned long g_last_fast_ms = 0;
unsigned long g_last_axis_ms = 0;

// What the NFC task hands the loop to frame. `kind` picks which fields matter:
// TagRead uses tag + text, TagGone none, WriteResult tag + ok.
struct NfcReport {
  Report kind;
  TagInfo tag;
  bool ok;
  uint8_t text_len;
  uint8_t text[ndef_text::kMaxText];
};

// An encoded NDEF record waiting for the next present tag. Depth 1, overwritten:
// a newer WriteTag replaces an unfired one, as NfcSession::queue_write does.
struct NfcWrite {
  uint8_t len;
  uint8_t bytes[ndef_text::kMaxEncoded];
};

QueueHandle_t g_nfc_reports = nullptr;
QueueHandle_t g_nfc_writes = nullptr;

struct NfcEvents {
  bool arrived = false;
  TagInfo tag{};
  bool departed = false;
  bool wrote = false;
  bool write_ok = false;
  TagInfo write_tag{};
};
NfcEvents g_nfc_events;

void on_arrival(const TagInfo &tag, void *) {
  g_nfc_events.arrived = true;
  g_nfc_events.tag = tag;
}
void on_removal(void *) { g_nfc_events.departed = true; }
void on_write(const TagInfo &tag, bool ok, void *) {
  g_nfc_events.wrote = true;
  g_nfc_events.write_ok = ok;
  g_nfc_events.write_tag = tag;
}
const NfcSession::Handlers kNfcHandlers{on_arrival, on_removal, on_write};

void send_key_event(const ButtonEvent &event, void *) {
  // Transitions before the bank has settled are the boot state arriving as
  // edges; the snapshot says the same thing without lying about when it started.
  if (!g_key_reporter.armed()) {
    return;
  }
  const uint8_t payload[3] = {static_cast<uint8_t>(Report::KeyEvent),
                              static_cast<uint8_t>(event.index),
                              static_cast<uint8_t>(event.pressed ? 1 : 0)};
  serial_link::send_frame(payload, sizeof(payload));
}

void send_snapshot() {
  uint8_t bits = 0;
  for (size_t i = 0; i < kButtonCount; i++) {
    if (g_buttons.pressed(i)) {
      bits |= static_cast<uint8_t>(1u << i);
    }
  }
  const uint8_t payload[2] = {static_cast<uint8_t>(Report::Snapshot), bits};
  serial_link::send_frame(payload, sizeof(payload));
}

// Probe an address with a zero-length write: the ACK is the whole answer.
uint8_t i2c_answers(uint8_t address) {
  Wire.beginTransmission(address);
  return Wire.endTransmission();
}

// The first address that answers, other than the one we wanted. A reader strapped
// to a different address and a bus with nothing on it look identical from the
// reader's own address, and this is what tells them apart.
uint8_t i2c_first_other(uint8_t besides) {
  for (uint8_t address = 0x08; address <= 0x77; address++) {
    if (address != besides && i2c_answers(address) == 0) {
      return address;
    }
  }
  return kNfcNothingAnswered;
}

void send_fault(Subsystem subsystem, uint8_t index) {
  const uint8_t payload[3] = {static_cast<uint8_t>(Report::Fault),
                              static_cast<uint8_t>(subsystem), index};
  serial_link::send_frame(payload, sizeof(payload));
}

void send_axes() {
  uint8_t payload[1 + 2 * kAxisCount];
  size_t n = 0;
  payload[n++] = static_cast<uint8_t>(Report::Axes);
  for (size_t i = 0; i < kAxisCount; i++) {
    const uint16_t raw = static_cast<uint16_t>(analogRead(kAxisPins[i]));
    payload[n++] = static_cast<uint8_t>(raw >> 8);
    payload[n++] = static_cast<uint8_t>(raw & 0xFF);
  }
  serial_link::send_frame(payload, n);
}

void send_encoder(int16_t delta) {
  const int8_t d = delta > 127 ? 127 : (delta < -128 ? -128 : static_cast<int8_t>(delta));
  const uint8_t payload[2] = {static_cast<uint8_t>(Report::Encoder),
                              static_cast<uint8_t>(d)};
  serial_link::send_frame(payload, sizeof(payload));
}

void send_tag_read(const TagInfo &tag, const uint8_t *text, uint8_t text_len) {
  uint8_t payload[1 + 1 + sizeof(tag.uid) + 1 + 1 + ndef_text::kMaxText];
  size_t n = 0;
  payload[n++] = static_cast<uint8_t>(Report::TagRead);
  payload[n++] = tag.uid_len;
  for (uint8_t i = 0; i < tag.uid_len && i < sizeof(tag.uid); i++) {
    payload[n++] = tag.uid[i];
  }
  payload[n++] = tag.sak;
  payload[n++] = text_len;
  for (uint8_t i = 0; i < text_len; i++) {
    payload[n++] = text[i];
  }
  serial_link::send_frame(payload, n);
}

void send_tag_gone() {
  const uint8_t payload[1] = {static_cast<uint8_t>(Report::TagGone)};
  serial_link::send_frame(payload, sizeof(payload));
}

void send_write_result(const TagInfo &tag, bool ok) {
  uint8_t payload[1 + 1 + 1 + sizeof(tag.uid)];
  size_t n = 0;
  payload[n++] = static_cast<uint8_t>(Report::WriteResult);
  payload[n++] = static_cast<uint8_t>(ok ? 0 : 1);
  payload[n++] = tag.uid_len;
  for (uint8_t i = 0; i < tag.uid_len && i < sizeof(tag.uid); i++) {
    payload[n++] = tag.uid[i];
  }
  serial_link::send_frame(payload, n);
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
    case Command::SetLeds:
      if (length >= 1 + 1) {
        uint8_t bits = command[1];
        g_led_bus.write(&bits);
      }
      break;
    case Command::SetGauge:
      if (length >= 1 + 2) {
        const uint8_t index = command[1];
        if (index < kGaugeCount) {
          g_gauges[index].set(command[2]);
        }
      }
      break;
    // 0 dark, 255 full. Inverted here because /OE is active low, so the pin
    // spends more time low the brighter the chain is asked to be.
    case Command::SetBrightness:
      if (length >= 1 + 1) {
        g_led_brightness.set(static_cast<uint8_t>(255u - command[1]));
      }
      break;
    case Command::RequestSync:
      send_snapshot();
      break;
    case Command::WriteTag:
      if (length >= 1 + 1) {
        const uint8_t text_len = command[1];
        if (text_len <= ndef_text::kMaxText && length >= 2u + text_len) {
          NfcWrite write{};
          const size_t n = ndef_text::encode(&command[2], text_len, write.bytes,
                                             sizeof(write.bytes));
          if (n > 0 && g_nfc_writes != nullptr) {
            write.len = static_cast<uint8_t>(n);
            xQueueOverwrite(g_nfc_writes, &write);
          }
        }
      }
      break;
  }
}

void fast_tick() {
  // The handler drops everything until the reporter arms, and the scan that arms
  // it is the one whose snapshot carries that same state.
  g_buttons.step(send_key_event, nullptr);
  if (g_key_reporter.settle()) {
    send_snapshot();
  }

  g_encoder.update(digitalRead(kEncA) == HIGH, digitalRead(kEncB) == HIGH);
  const int16_t detents = g_encoder.flush();
  if (detents != 0) {
    send_encoder(detents);
  }
}

void push_report(const NfcReport &report) {
  xQueueSend(g_nfc_reports, &report, portMAX_DELAY);
}

// One NFC poll, on the NFC task. Everything it learns leaves as an NfcReport.
void nfc_tick() {
  NfcWrite write;
  if (xQueueReceive(g_nfc_writes, &write, 0) == pdTRUE) {
    g_nfc_session.queue_write(kNfcNdefStartPage, write.bytes, write.len);
  }

  g_nfc_events = NfcEvents{};
  g_nfc_session.poll(g_nfc_ctrl, kNfcHandlers, nullptr);

  // Read back and ship the tag's string on a fresh arrival AND after any write,
  // so a write onto an already-present tag (no new arrival) still emits the
  // read-back the host verifies against.
  if (g_nfc_events.arrived || g_nfc_events.wrote) {
    NfcReport report{};
    report.kind = Report::TagRead;
    report.tag = g_nfc_events.arrived ? g_nfc_events.tag : g_nfc_events.write_tag;
    uint8_t raw[kNfcReadBytes];
    size_t text_len = 0;
    if (g_nfc_ctrl.read(kNfcNdefStartPage, raw, sizeof(raw)) &&
        ndef_text::decode(raw, sizeof(raw), report.text, sizeof(report.text),
                          &text_len)) {
      report.text_len = static_cast<uint8_t>(text_len);
    }
    push_report(report);
  }
  if (g_nfc_events.departed) {
    NfcReport report{};
    report.kind = Report::TagGone;
    push_report(report);
  }
  if (g_nfc_events.wrote) {
    NfcReport report{};
    report.kind = Report::WriteResult;
    report.tag = g_nfc_events.write_tag;
    report.ok = g_nfc_events.write_ok;
    push_report(report);
  }
}

void nfc_task(void *) {
  TickType_t last_wake = xTaskGetTickCount();
  for (;;) {
    vTaskDelayUntil(&last_wake, pdMS_TO_TICKS(kNfcPollMs));
    nfc_tick();
  }
}

// The loop's side of the report queue: frame whatever the NFC task produced.
void drain_nfc_reports() {
  if (g_nfc_reports == nullptr) {
    return;
  }
  NfcReport report;
  while (xQueueReceive(g_nfc_reports, &report, 0) == pdTRUE) {
    switch (report.kind) {
      case Report::TagRead:
        send_tag_read(report.tag, report.text, report.text_len);
        break;
      case Report::TagGone:
        send_tag_gone();
        break;
      case Report::WriteResult:
        send_write_result(report.tag, report.ok);
        break;
      default:
        break;
    }
  }
}

// Off the loop's core, so the radio's blocking never lands on the input scan.
bool start_nfc_task() {
  g_nfc_reports = xQueueCreate(kNfcReportDepth, sizeof(NfcReport));
  g_nfc_writes = xQueueCreate(1, sizeof(NfcWrite));
  if (g_nfc_reports == nullptr || g_nfc_writes == nullptr) {
    return false;
  }
  const BaseType_t other_core = xPortGetCoreID() == 0 ? 1 : 0;
  return xTaskCreatePinnedToCore(nfc_task, "nfc", kNfcTaskStackBytes, nullptr,
                                 kNfcTaskPriority, nullptr, other_core) == pdPASS;
}

}  // namespace

void app_setup() {
  serial_link::begin(proto::kBaud, proto::kModuleId);

  analogReadResolution(12);
  for (size_t i = 0; i < kAxisCount; i++) {
    analogSetPinAttenuation(kAxisPins[i], ADC_11db);
  }

  g_spi.begin(kSck, kMiso, kMosi, -1);
  g_led_bus.begin();
  g_btn_bus.begin();
  uint8_t leds_off = 0;
  g_led_bus.write(&leds_off);

  pinMode(kEncA, INPUT_PULLUP);
  pinMode(kEncB, INPUT_PULLUP);

  // A ledc channel that fails to attach leaves a needle that never moves and a
  // chain that never lights, with nothing on the wire to say so. Report it.
  for (size_t i = 0; i < kGaugeCount; i++) {
    if (!g_gauges[i].begin()) {
      send_fault(Subsystem::Gauge, static_cast<uint8_t>(i));
    }
    g_gauges[i].set(0);
  }

  if (!g_led_brightness.begin()) {
    send_fault(Subsystem::LedBrightness, 0);
  }
  g_led_brightness.set(0);  // /OE low: the chain is enabled at full brightness

  // Probe before initialising. Swapped SDA/SCL, a crossed level-shifter channel,
  // a reader at another address and a dead 5 V rail all present the same way —
  // silence — and none of them can be told apart with a meter, because an idle
  // I2C bus sits high either way. The board is the only thing in a position to
  // say which it is, so it says so.
  Wire.begin(kSda, kScl);
  if (i2c_answers(kNfcAddress) != 0) {
    send_fault(Subsystem::Nfc, i2c_first_other(kNfcAddress));
  } else if (!g_nfc_ctrl.begin()) {
    send_fault(Subsystem::Nfc, kNfcInitFailed);
  }

  if (!start_nfc_task()) {
    send_fault(Subsystem::NfcTask, 0);
  }
}

void app_loop() {
  serial_link::poll(apply_command);

  const unsigned long now = millis();
  if (now - g_last_fast_ms >= kFastTickMs) {
    g_last_fast_ms = now;
    fast_tick();
  }
  if (now - g_last_axis_ms >= kAxisTickMs) {
    g_last_axis_ms = now;
    send_axes();
  }
  drain_nfc_reports();
}
