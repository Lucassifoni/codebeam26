#define MODULE_ID 0x02

#include "app.h"

#include <Arduino.h>

#include <button_bank.h>
#include <gpio_bus.h>
#include <key_reporter.h>
#include <link.h>
#include <protocol.h>

#include "demo_map.h"

/// @file
/// module_2_demo: a two-key, two-LED stand-in for module_2, for presentations.
/// It announces itself as 0x02 and speaks module_2's protocol verbatim, so the
/// host cannot tell it apart from a module_2 whose other parts are absent.
///
/// Mapping (see demo_map.h): local key 0 + LED 0 are module_2's button 6 +
/// LED 2; local key 1 + LED 1 are button 5 + LED 7. Keys and LEDs are wired
/// straight to GPIO — no '595/'165.
///
/// Supported subset of module_2's protocol:
///   host -> device  Ping          (0x11)          : -> Pong
///   host -> device  SetLeds       (0x12) + 1 B    : only bits 2 and 7 are used
///   host -> device  RequestSync   (0x16)          : -> Snapshot
///   device -> host  Pong        (0x81)
///   device -> host  KeyEvent    (0x82) + index + pressed   index is 6 or 5
///   device -> host  Snapshot    (0x88) + 1 B    once settled, and on RequestSync
///
/// SetGauge, WriteTag and SetBrightness are accepted and ignored. Axes,
/// Encoder, TagRead/TagGone/WriteResult and Fault are never sent: there is
/// nothing behind them on this board.

namespace {

constexpr uint8_t kDebounceScans = 3;
constexpr unsigned long kFastTickMs = 3;

// Keys between GPIO and GND on the internal pull-ups; LEDs active high through
// a series resistor. Both pairs avoid strapping pins and UART0.
constexpr uint8_t kButtonPins[demo_map::kLines] = {32, 33};
constexpr uint8_t kLedPins[demo_map::kLines] = {25, 26};

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
  Snapshot = 0x88,
};

GpioOutputBus g_led_bus(kLedPins, demo_map::kLines, kLedActiveLow);
GpioInputBus g_btn_bus(kButtonPins, demo_map::kLines, kBtnActiveLow, true);

uint8_t g_btn_stable[ButtonBank::stable_bytes(demo_map::kLines)];
uint8_t g_btn_counters[ButtonBank::counter_bytes(demo_map::kLines)];
ButtonBank g_buttons(g_btn_bus, kDebounceScans, g_btn_stable, g_btn_counters);

KeyReporter g_key_reporter(kDebounceScans);

unsigned long g_last_fast_ms = 0;

void send_key_event(const ButtonEvent &event, void *) {
  if (!g_key_reporter.armed() || event.index >= demo_map::kLines) {
    return;
  }
  const uint8_t payload[3] = {static_cast<uint8_t>(Report::KeyEvent),
                              demo_map::kKeyWire[event.index],
                              static_cast<uint8_t>(event.pressed ? 1 : 0)};
  serial_link::send_frame(payload, sizeof(payload));
}

void send_snapshot() {
  uint8_t local = 0;
  for (size_t i = 0; i < demo_map::kLines; i++) {
    if (g_buttons.pressed(i)) {
      local |= static_cast<uint8_t>(1u << i);
    }
  }
  const uint8_t payload[2] = {static_cast<uint8_t>(Report::Snapshot),
                              demo_map::wire_snapshot(local)};
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
    case Command::SetLeds:
      if (length >= 1 + 1) {
        const uint8_t bits = demo_map::local_leds(command[1]);
        g_led_bus.write(&bits);
      }
      break;
    case Command::RequestSync:
      send_snapshot();
      break;
    case Command::SetGauge:
    case Command::WriteTag:
    case Command::SetBrightness:
      break;
  }
}

void fast_tick() {
  g_buttons.step(send_key_event, nullptr);
  if (g_key_reporter.settle()) {
    send_snapshot();
  }
}

}  // namespace

void app_setup() {
  serial_link::begin(proto::kBaud, proto::kModuleId);

  g_led_bus.begin();
  g_btn_bus.begin();
  const uint8_t leds_off = 0;
  g_led_bus.write(&leds_off);
}

void app_loop() {
  serial_link::poll(apply_command);

  const unsigned long now = millis();
  if (now - g_last_fast_ms >= kFastTickMs) {
    g_last_fast_ms = now;
    fast_tick();
  }
}
