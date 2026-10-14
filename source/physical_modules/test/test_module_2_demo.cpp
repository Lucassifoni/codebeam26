#include <cstdio>

#include "demo_map.h"

/// @file
/// Host unit tests for module_2_demo's wire mapping: which of module_2's LED
/// bits reach the two local LEDs, and which module_2 key indices the two local
/// buttons report as. Run via `make test`.

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

}  // namespace

int main() {
  using namespace demo_map;

  expect("keys report as module_2 buttons 6 and 5",
         kKeyWire[0] == 6 && kKeyWire[1] == 5);

  expect("no LEDs lit from an empty byte", local_leds(0x00) == 0x00);
  expect("LED 2 drives local LED 0", local_leds(1u << 2) == 0x01);
  expect("LED 7 drives local LED 1", local_leds(1u << 7) == 0x02);
  expect("both mapped LEDs drive both locals",
         local_leds((1u << 2) | (1u << 7)) == 0x03);
  expect("unmapped LED bits are ignored",
         local_leds(static_cast<uint8_t>(~((1u << 2) | (1u << 7)))) == 0x00);
  expect("all bits set lights both", local_leds(0xFF) == 0x03);

  expect("empty snapshot", wire_snapshot(0x00) == 0x00);
  expect("local button 0 snapshots as bit 6", wire_snapshot(0x01) == (1u << 6));
  expect("local button 1 snapshots as bit 5", wire_snapshot(0x02) == (1u << 5));
  expect("both buttons snapshot as bits 6 and 5",
         wire_snapshot(0x03) == ((1u << 6) | (1u << 5)));
  expect("stray local bits do not leak into the snapshot",
         wire_snapshot(0xFC) == 0x00);

  if (g_failures == 0) {
    printf("module_2_demo: all passed\n");
    return 0;
  }
  printf("module_2_demo: %d failure(s)\n", g_failures);
  return 1;
}
