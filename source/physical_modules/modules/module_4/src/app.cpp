#define MODULE_ID 0x04

#include "app.h"

#include <Arduino.h>

#include <button_bank.h>
#include <gpio_bus.h>
#include <link.h>
#include <protocol.h>
#include <analog_edges.h>
#include <pulse_activity.h>

/// @file
/// module_4: 2 buttons + trackball. The trackball is used as an activity trigger
/// ("spin the ball -> random action"), not a pointer, so we need pulses only —
/// no direction, axis, or position. The received part is an optomechanical PS/2
/// trackball; we ignore its PS/2 controller and tap the comparator output of
/// each encoder wheel (one line per wheel, both needed since an axis-aligned
/// spin turns only one wheel).
///
/// Those taps are read with the **ADC, not as digital inputs**. On the real
/// wheels the slots only partially occlude the IR source — far less cleanly than
/// the bench obturators the first design was measured against — so each line
/// swings between the high rail and some intermediate level rather than between
/// the rails. A digital input reads that as a constant HIGH and there is no edge
/// to interrupt on. The pure AnalogEdges unit recovers the pulses instead: it
/// tracks each line's own decaying peak/trough envelope and counts the falling
/// crossings of a hysteresis band around the midpoint, so it needs to know
/// neither line's absolute levels and adapts as they drift. When the ball stops,
/// the envelope collapses and counting stops on its own.
///
/// The taps are sampled on **every loop pass**, not on the tick: the wheels
/// pulse far faster than the 3 ms tick, and an undersampled train is an
/// undercounted one. The pure PulseActivity unit then turns the per-tick count
/// into a debounced-by-threshold Activity report, with an idle decay that sheds
/// stray pulses (vibration). Both units are unchanged in what they hand the
/// host: the Activity report is the same byte it always was.
///
/// The button half needs no shift register: two switches wire straight to GPIO,
/// each to GND with the internal pull-up, so a pressed key reads LOW (active_low).
///
/// Protocol (frame body after the module discriminant byte):
///   host -> device  Ping     (0x11)                     : -> Pong
///   device -> host  Pong     (0x81)
///   device -> host  Buttons  (0x82) + 1 B (2 bits used) : on change
///   device -> host  Activity (0x83) + 1 B (pulse count) : when the ball is spun

namespace {

constexpr size_t kButtonCount = 2;
constexpr uint8_t kDebounceScans = 3;
constexpr unsigned long kTickIntervalMs = 3;

// === EDIT FOR YOUR WIRING. GPIO16/22 both sit on the board's D15-D23 side, where
// the buttons' JST header lands, at opposite ends of it. Both support internal
// pull-ups and are neither strapping (0/2/5/12/15) nor UART0 (1/3) nor
// input-only (34-39). GPIO22 is the default I2C SCL and 16 a WROVER PSRAM line,
// neither of which this board uses. Each button ties its pin to GND; the pull-up
// holds it HIGH when open, so pressed = LOW. The ADC1 side of the board is left
// to the trackball taps.
constexpr uint8_t kButtonPins[kButtonCount] = {16, 22};

// The switches are wired on their NORMALLY CLOSED contact, so the sense is
// inverted from the usual: the contact ties the pin to GND at rest and *opens*
// on press, letting the internal pull-up take it HIGH. Hence active_low = false
// — a set bit is a HIGH pin is a pressed button. The pull-up stays enabled; it
// is what provides the HIGH once the contact opens.
//
// Worth knowing about this half of the switch: at rest the pin is driven, and a
// broken wire floats to the pull-up and reads as a *stuck press*. On the normally
// open contact the failure is the other way round — a broken wire reads as never
// pressed, which for RESET and PRINT is the quieter failure. Move to the NO
// contact and set this back to true if that matters more than the wiring already
// done.
constexpr bool kButtonActiveLow = false;
constexpr bool kButtonUsePullup = true;

// Trackball activity: one comparator output per encoder wheel, each via a
// resistor divider, read as an analog level. GPIO34/35 are ADC1 (CH6/CH7),
// input-only, and take no internal pull-up to fight the divider. ADC1 is used
// rather than ADC2 because ADC2 is unavailable whenever WiFi is up.
//
// Size the divider so BOTH levels land inside the ADC's usable range: the ESP32
// compresses above ~3.1 V, so a swing whose high sits at the rail loses its top
// and can read as no swing at all. Aim the high at roughly 2.5 V and the span
// follows.
constexpr size_t kTapCount = 2;
constexpr uint8_t kTapPins[kTapCount] = {34, 35};

// Revisable defaults, tuned at install against the real ball — the numbers that
// matter are in counts of the 12-bit ADC (4095 counts over the ~3.1 V span).
//   min_span 150  ~120 mV: above the ADC's own noise, below any real swing.
//   decay 2       at ~10 kHz sampling the envelope survives a pulse period and
//                 collapses ~50 ms after the ball stops.
constexpr AnalogEdges::Config kEdgesConfig{/*min_span=*/150, /*decay=*/2,
                                           /*hysteresis_pct=*/20};
constexpr PulseActivity::Config kActivityConfig{/*fire_threshold=*/4,
                                                /*idle_decay=*/2};
constexpr uint8_t kAdcResolutionBits = 12;

enum class Command : uint8_t {
  Ping = 0x11,
};

enum class Report : uint8_t {
  Pong = 0x81,
  Buttons = 0x82,
  Activity = 0x83,  // one report per debounced burst of ball motion
};

GpioInputBus g_btn_bus(kButtonPins, kButtonCount, kButtonActiveLow,
                       kButtonUsePullup);

uint8_t g_btn_stable[ButtonBank::stable_bytes(kButtonCount)];
uint8_t g_btn_counters[ButtonBank::counter_bytes(kButtonCount)];
ButtonBank g_buttons(g_btn_bus, kDebounceScans, g_btn_stable, g_btn_counters);

PulseActivity g_activity(kActivityConfig);

AnalogEdges g_taps[kTapCount] = {AnalogEdges(kEdgesConfig),
                                 AnalogEdges(kEdgesConfig)};

uint16_t g_pulses = 0;

// Both wheels feed one counter: the ball's activity is the sum, and which wheel
// turned is exactly the information this module does not want.
void sample_taps() {
  for (size_t i = 0; i < kTapCount; i++) {
    if (g_taps[i].update(static_cast<uint16_t>(analogRead(kTapPins[i]))) &&
        g_pulses < 0xFFFF) {
      g_pulses++;
    }
  }
}

uint16_t take_pulses() {
  const uint16_t n = g_pulses;
  g_pulses = 0;
  return n;
}

unsigned long g_last_tick_ms = 0;

void send_buttons() {
  uint8_t bits = 0;
  for (size_t i = 0; i < kButtonCount; i++) {
    if (g_buttons.pressed(i)) {
      bits |= static_cast<uint8_t>(1u << i);
    }
  }
  const uint8_t payload[2] = {static_cast<uint8_t>(Report::Buttons), bits};
  serial_link::send_frame(payload, sizeof(payload));
}

void send_activity(uint8_t count) {
  const uint8_t payload[2] = {static_cast<uint8_t>(Report::Activity), count};
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
  g_btn_bus.begin();

  analogReadResolution(kAdcResolutionBits);
  for (size_t i = 0; i < kTapCount; i++) {
    pinMode(kTapPins[i], INPUT);
    analogSetPinAttenuation(kTapPins[i], ADC_11db);
  }
}

void app_loop() {
  serial_link::poll(apply_command);

  // Every pass, not on the tick: the wheels pulse far faster than 3 ms.
  sample_taps();

  const unsigned long now = millis();
  if (now - g_last_tick_ms < kTickIntervalMs) {
    return;
  }
  g_last_tick_ms = now;

  if (g_buttons.step(nullptr, nullptr)) {
    send_buttons();
  }

  if (g_activity.update(take_pulses())) {
    send_activity(g_activity.report());
  }
}
