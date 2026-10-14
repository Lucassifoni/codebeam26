#include <cstdio>
#include <cstring>

#include "analog_axis.h"
#include "analog_edges.h"
#include "button_bank.h"
#include "fake_bus.h"
#include "fake_nfc.h"
#include "key_reporter.h"
#include "ndef_text.h"
#include "nfc_session.h"
#include "pulse_activity.h"
#include "quadrature_encoder.h"

/// @file
/// Host unit tests for the pure lib/io logic (AnalogAxis, AnalogEdges,
/// QuadratureEncoder, ButtonBank, KeyReporter, NfcSession), driven through
/// fakes. Run via `make test`.

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

// --- AnalogAxis -----------------------------------------------------------

AnalogAxis::Config axis_config(uint8_t ema_shift, uint16_t deadzone = 0) {
  return AnalogAxis::Config{/*center=*/2048, /*min=*/0,          /*max=*/4095,
                            deadzone,         /*out_range=*/127,  ema_shift};
}

void test_axis_calibration() {
  AnalogAxis axis(axis_config(0));

  expect("axis at center -> 0", axis.update(2048) == 0);
  expect("axis at max -> +out_range", axis.update(4095) == 127);
  expect("axis at min -> -out_range", axis.update(0) == -127);

  const int16_t mid = axis.update(3072);
  expect("axis midway high is near half range", mid > 55 && mid < 70);
  const int16_t midlow = axis.update(1024);
  expect("axis midway low is near negative half", midlow < -55 && midlow > -70);
}

void test_axis_clamping() {
  AnalogAxis::Config cfg{2048, 1024, 3072, 0, 127, 0};
  AnalogAxis axis(cfg);

  expect("reading past calibrated max clamps to +out_range",
         axis.update(4095) == 127);
  expect("reading past calibrated min clamps to -out_range",
         axis.update(0) == -127);
}

void test_axis_deadzone() {
  AnalogAxis axis(axis_config(0, /*deadzone=*/200));

  expect("inside deadzone -> 0", axis.update(2048 + 150) == 0);
  expect("just below center inside deadzone -> 0", axis.update(2048 - 150) == 0);
  expect("outside deadzone -> nonzero", axis.update(2048 + 600) > 0);
}

void test_axis_ema_convergence() {
  AnalogAxis axis(axis_config(3));
  axis.reset(2048);
  expect("seeded EMA reports center", axis.filtered() == 2048);

  for (int i = 0; i < 120; i++) axis.update(4095);
  expect("EMA converges toward the steady sample", axis.filtered() > 4000);
  expect("converged axis reads +out_range", axis.value() == 127);

  const uint16_t before = axis.filtered();
  axis.update(0);
  expect("smoothed axis moves gradually, not instantly",
         axis.filtered() < before && axis.filtered() > 2048);
}

// --- QuadratureEncoder ----------------------------------------------------

void feed(QuadratureEncoder &enc, const uint8_t (*states)[2], size_t n) {
  for (size_t i = 0; i < n; i++) enc.update(states[i][0], states[i][1]);
}

void test_encoder_forward_detent() {
  QuadratureEncoder enc(4);
  const uint8_t cw[5][2] = {{0, 0}, {0, 1}, {1, 1}, {1, 0}, {0, 0}};
  feed(enc, cw, 5);
  expect("full CW Gray cycle -> +1 detent", enc.flush() == 1);
  expect("flush resets to 0", enc.flush() == 0);
}

void test_encoder_reverse_detent() {
  QuadratureEncoder enc(4);
  const uint8_t ccw[5][2] = {{0, 0}, {1, 0}, {1, 1}, {0, 1}, {0, 0}};
  feed(enc, ccw, 5);
  expect("full CCW Gray cycle -> -1 detent", enc.flush() == -1);
}

void test_encoder_multi_detent() {
  QuadratureEncoder enc(4);
  const uint8_t cw[4][2] = {{0, 1}, {1, 1}, {1, 0}, {0, 0}};
  enc.update(0, 0);  // seed phase
  for (int r = 0; r < 3; r++) feed(enc, cw, 4);
  expect("three CW cycles -> +3 detents", enc.flush() == 3);
}

void test_encoder_bounce_and_invalid_ignored() {
  QuadratureEncoder enc(4);
  const uint8_t bounce[5][2] = {{0, 0}, {0, 1}, {0, 0}, {0, 1}, {0, 0}};
  feed(enc, bounce, 5);
  expect("bounce back and forth completes no detent", enc.flush() == 0);

  QuadratureEncoder enc2(4);
  const uint8_t invalid[3][2] = {{0, 0}, {1, 1}, {0, 0}};  // diagonal jumps
  feed(enc2, invalid, 3);
  expect("invalid diagonal transitions ignored", enc2.flush() == 0);
}

// --- ButtonBank -----------------------------------------------------------

struct ButtonLog {
  std::vector<ButtonEvent> events;
};

void collect_button(const ButtonEvent &e, void *ctx) {
  static_cast<ButtonLog *>(ctx)->events.push_back(e);
}

void set_button(FakeInputBus &bus, size_t i, bool on) {
  const uint8_t mask = static_cast<uint8_t>(1u << (i & 7));
  if (on) {
    bus.data_[i >> 3] |= mask;
  } else {
    bus.data_[i >> 3] &= static_cast<uint8_t>(~mask);
  }
}

void test_button_debounce_and_events() {
  FakeInputBus bus(8);
  uint8_t stable[ButtonBank::stable_bytes(8)] = {0};
  uint8_t counters[ButtonBank::counter_bytes(8)] = {0};
  ButtonBank bank(bus, 3, stable, counters);

  ButtonLog log;
  set_button(bus, 5, true);

  expect("no change before debounce (1)", !bank.step(collect_button, &log));
  expect("no change before debounce (2)", !bank.step(collect_button, &log));
  expect("no event before threshold", log.events.empty());
  expect("not pressed before threshold", !bank.pressed(5));

  expect("change reported on third agreeing step",
         bank.step(collect_button, &log));
  expect("press event on third step",
         log.events.size() == 1 && log.events[0].index == 5 &&
             log.events[0].pressed);
  expect("pressed() reflects committed state", bank.pressed(5));

  set_button(bus, 5, false);
  bank.step(collect_button, &log);
  bank.step(collect_button, &log);
  expect("no release event before threshold", log.events.size() == 1);
  expect("release reported on third step", bank.step(collect_button, &log));
  expect("release event is not-pressed",
         log.events.size() == 2 && !log.events[1].pressed);
  expect("pressed() cleared after release", !bank.pressed(5));
}

void test_button_bounce_resets_counter() {
  FakeInputBus bus(8);
  uint8_t stable[ButtonBank::stable_bytes(8)] = {0};
  uint8_t counters[ButtonBank::counter_bytes(8)] = {0};
  ButtonBank bank(bus, 3, stable, counters);

  ButtonLog log;
  set_button(bus, 0, true);
  bank.step(collect_button, &log);
  bank.step(collect_button, &log);
  set_button(bus, 0, false);  // bounce before threshold
  bank.step(collect_button, &log);
  set_button(bus, 0, true);
  bank.step(collect_button, &log);
  bank.step(collect_button, &log);
  expect("bounce resets debounce counter (no premature event)",
         log.events.empty() && !bank.pressed(0));
}

// --- KeyReporter ----------------------------------------------------------

// The whole point of the unit: a contact already closed at power-on must reach
// the host as state, never as an edge.
void test_reporter_suppresses_the_boot_burst() {
  FakeInputBus bus(8);
  uint8_t stable[ButtonBank::stable_bytes(8)] = {0};
  uint8_t counters[ButtonBank::counter_bytes(8)] = {0};
  ButtonBank bank(bus, 3, stable, counters);
  KeyReporter reporter(3);

  ButtonLog log;
  set_button(bus, 2, true);  // held down before the board came up

  int snapshot_at = -1;
  for (int scan = 0; scan < 3; scan++) {
    bank.step(collect_button, &log);
    if (reporter.settle()) {
      snapshot_at = scan;
    }
  }

  expect("snapshot on the settling scan", snapshot_at == 2);
  expect("armed once settled", reporter.armed());
  expect("the boot state committed", bank.pressed(2));
  // The commit and the snapshot land on the same scan, which is exactly why a
  // handler gated on armed() emits nothing for the boot state.
  expect("the boot transition coincides with the snapshot",
         log.events.size() == 1 && log.events[0].index == 2 &&
             log.events[0].pressed && snapshot_at == 2);
}

void test_reporter_arms_once_and_stays_armed() {
  KeyReporter reporter(3);

  expect("not armed on the first scan", !reporter.settle() && !reporter.armed());
  expect("not armed on the second scan", !reporter.settle());
  expect("snapshot on the third scan", reporter.settle());
  expect("armed after the snapshot", reporter.armed());
  expect("no second snapshot", !reporter.settle() && !reporter.settle());
  expect("still armed", reporter.armed());
}

void test_reporter_settles_immediately_when_asked_to() {
  KeyReporter reporter(1);

  expect("a one-scan settle arms on its first scan", reporter.settle());
  expect("and stays armed", reporter.armed() && !reporter.settle());
}

void test_reporter_reset_disarms() {
  KeyReporter reporter(2);

  reporter.settle();
  expect("armed before the reset", reporter.settle() && reporter.armed());

  reporter.reset();
  expect("disarmed by the reset", !reporter.armed());
  expect("and settles again from scratch", !reporter.settle() && reporter.settle());
}

// --- NfcSession -----------------------------------------------------------

struct NfcLog {
  int arrivals = 0;
  int removals = 0;
  int writes = 0;
  TagInfo last_tag{};
  bool last_write_ok = false;
};

void on_arrival(const TagInfo &tag, void *ctx) {
  auto *l = static_cast<NfcLog *>(ctx);
  l->arrivals++;
  l->last_tag = tag;
}
void on_removal(void *ctx) { static_cast<NfcLog *>(ctx)->removals++; }
void on_write(const TagInfo &tag, bool ok, void *ctx) {
  auto *l = static_cast<NfcLog *>(ctx);
  l->writes++;
  l->last_write_ok = ok;
  (void)tag;
}

const NfcSession::Handlers kHandlers{on_arrival, on_removal, on_write};

void test_nfc_arrival_edge_once() {
  FakeNfcController nfc;
  NfcSession session(3);
  NfcLog log;
  const uint8_t uid_a[4] = {0xDE, 0xAD, 0xBE, 0xEF};

  nfc.set_tag(uid_a, 4, 0x08);
  session.poll(nfc, kHandlers, &log);
  session.poll(nfc, kHandlers, &log);
  expect("arrival emitted once per new UID", log.arrivals == 1);
  expect("arrival carries the UID",
         log.last_tag.uid_len == 4 && log.last_tag.uid[0] == 0xDE);

  const uint8_t uid_b[7] = {1, 2, 3, 4, 5, 6, 7};
  nfc.set_tag(uid_b, 7, 0x00);
  session.poll(nfc, kHandlers, &log);
  expect("changed UID emits a new arrival", log.arrivals == 2);
}

void test_nfc_removal_debounce() {
  FakeNfcController nfc;
  NfcSession session(3);
  NfcLog log;
  const uint8_t uid[4] = {0xAA, 0xBB, 0xCC, 0xDD};

  nfc.set_tag(uid, 4, 0x08);
  session.poll(nfc, kHandlers, &log);

  nfc.set_absent();
  session.poll(nfc, kHandlers, &log);
  session.poll(nfc, kHandlers, &log);
  expect("no removal before miss threshold", log.removals == 0);
  expect("still held present mid-debounce", session.present());
  session.poll(nfc, kHandlers, &log);
  expect("removal emitted after miss threshold", log.removals == 1);
  expect("session released the controller", nfc.releases == 1);

  session.poll(nfc, kHandlers, &log);
  expect("no repeated removal once gone", log.removals == 1);
}

void test_nfc_pending_write_fires_on_next_tag() {
  FakeNfcController nfc;
  NfcSession session(3);
  NfcLog log;
  const uint8_t uid[4] = {0x11, 0x22, 0x33, 0x44};

  const uint8_t data[6] = {0x03, 0x0A, 0xD1, 0x01, 0x06, 0x54};
  session.queue_write(4, data, sizeof(data));
  expect("write pending after queue", session.write_pending());

  session.poll(nfc, kHandlers, &log);  // no tag yet
  expect("write does not fire with no tag", nfc.pages_written.empty());
  expect("write still pending", session.write_pending());

  nfc.set_tag(uid, 4, 0x08);
  session.poll(nfc, kHandlers, &log);
  expect("write spans two pages from the start page",
         nfc.pages_written.size() == 2 && nfc.pages_written[0] == 4 &&
             nfc.pages_written[1] == 5);
  expect("first page holds the leading bytes",
         nfc.page(4)[0] == 0x03 && nfc.page(4)[3] == 0x01);
  expect("partial last page is zero-padded",
         nfc.page(5)[0] == 0x06 && nfc.page(5)[1] == 0x54 &&
             nfc.page(5)[2] == 0x00 && nfc.page(5)[3] == 0x00);
  expect("write result reported ok", log.writes == 1 && log.last_write_ok);
  expect("write no longer pending", !session.write_pending());

  session.poll(nfc, kHandlers, &log);
  expect("write is consumed, not repeated", nfc.pages_written.size() == 2);
}

void test_nfc_write_on_already_present_tag() {
  FakeNfcController nfc;
  NfcSession session(3);
  NfcLog log;
  const uint8_t uid[4] = {0x55, 0x66, 0x77, 0x88};

  nfc.set_tag(uid, 4, 0x08);
  session.poll(nfc, kHandlers, &log);
  expect("arrival for the present tag", log.arrivals == 1);

  const uint8_t data[4] = {0x03, 0x00, 0xFE, 0x00};
  session.queue_write(4, data, sizeof(data));
  session.poll(nfc, kHandlers, &log);
  expect("write applied without a new arrival", log.arrivals == 1);
  expect("write recorded", nfc.pages_written.size() == 1 && log.writes == 1);
}

void test_nfc_held_tag_confirmed_without_detect() {
  FakeNfcController nfc;
  NfcSession session(3);
  NfcLog log;
  const uint8_t uid[7] = {0x04, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66};

  nfc.set_tag(uid, 7, 0x00);
  for (int i = 0; i < 10; i++) {
    session.poll(nfc, kHandlers, &log);
  }
  expect("a held tag is detected once", nfc.detects == 1);
  expect("and confirmed cheaply on every later poll", nfc.presence_checks == 9);
  expect("a held tag arrives once", log.arrivals == 1 && log.removals == 0);
}

void test_nfc_lost_selection_reselects_silently() {
  FakeNfcController nfc;
  NfcSession session(3);
  NfcLog log;
  const uint8_t uid[4] = {0x01, 0x02, 0x03, 0x04};

  nfc.set_tag(uid, 4, 0x08);
  session.poll(nfc, kHandlers, &log);
  nfc.drop_selection();
  session.poll(nfc, kHandlers, &log);
  expect("a failed confirmation falls back to detect", nfc.detects == 2);
  expect("the same tag re-selected is not a new arrival", log.arrivals == 1);
  expect("nor a removal", log.removals == 0 && session.present());

  session.poll(nfc, kHandlers, &log);
  expect("confirmation resumes after the re-select", nfc.detects == 2);
}

void test_nfc_swap_between_polls_is_an_arrival() {
  FakeNfcController nfc;
  NfcSession session(3);
  NfcLog log;
  const uint8_t uid_a[4] = {0xA0, 0xA1, 0xA2, 0xA3};
  const uint8_t uid_b[4] = {0xB0, 0xB1, 0xB2, 0xB3};

  nfc.set_tag(uid_a, 4, 0x08);
  session.poll(nfc, kHandlers, &log);
  nfc.set_tag(uid_b, 4, 0x08);
  session.poll(nfc, kHandlers, &log);
  expect("a swapped tag is a new arrival",
         log.arrivals == 2 && log.last_tag.uid[0] == 0xB0);
  expect("with no removal in between", log.removals == 0);
}

// --- NdefText -------------------------------------------------------------

void test_ndef_encode_roundtrip() {
  const char *text = "HELLO-42";
  const size_t tlen = 8;
  uint8_t buf[ndef_text::kMaxEncoded];
  const size_t n = ndef_text::encode(
      reinterpret_cast<const uint8_t *>(text), tlen, buf, sizeof(buf));
  expect("encoded length matches formula", n == ndef_text::encoded_size(tlen));
  expect("starts with NDEF TLV tag", buf[0] == 0x03);
  expect("ends with terminator", buf[n - 1] == 0xFE);

  uint8_t out[ndef_text::kMaxText];
  size_t out_len = 0;
  const bool ok = ndef_text::decode(buf, n, out, sizeof(out), &out_len);
  expect("decode succeeds", ok);
  expect("decoded length matches", out_len == tlen);
  expect("decoded bytes match", memcmp(out, text, tlen) == 0);
}

void test_ndef_empty_string() {
  uint8_t buf[ndef_text::kMaxEncoded];
  const size_t n = ndef_text::encode(nullptr, 0, buf, sizeof(buf));
  expect("empty encodes to minimum size", n == ndef_text::encoded_size(0));
  uint8_t out[ndef_text::kMaxText];
  size_t out_len = 99;
  const bool ok = ndef_text::decode(buf, n, out, sizeof(out), &out_len);
  expect("empty decodes to zero length", ok && out_len == 0);
}

void test_ndef_max_length_roundtrip() {
  uint8_t text[ndef_text::kMaxText];
  for (size_t i = 0; i < sizeof(text); i++) {
    text[i] = static_cast<uint8_t>('A' + (i % 26));
  }
  uint8_t buf[ndef_text::kMaxEncoded];
  const size_t n = ndef_text::encode(text, sizeof(text), buf, sizeof(buf));
  expect("max-length fills the max encoding", n == ndef_text::kMaxEncoded);
  uint8_t out[ndef_text::kMaxText];
  size_t out_len = 0;
  expect("max-length roundtrips",
         ndef_text::decode(buf, n, out, sizeof(out), &out_len) &&
             out_len == ndef_text::kMaxText &&
             memcmp(out, text, out_len) == 0);
}

void test_ndef_rejects_over_length_and_small_buffer() {
  uint8_t text[ndef_text::kMaxText + 1] = {0};
  uint8_t buf[ndef_text::kMaxEncoded + 16];
  expect("over-length text is rejected",
         ndef_text::encode(text, sizeof(text), buf, sizeof(buf)) == 0);

  const uint8_t abc[3] = {'a', 'b', 'c'};
  uint8_t tiny[4];
  expect("insufficient output buffer is rejected",
         ndef_text::encode(abc, sizeof(abc), tiny, sizeof(tiny)) == 0);
}

void test_ndef_decode_tolerates_leading_null_tlvs() {
  const char *text = "Xy";
  uint8_t inner[ndef_text::kMaxEncoded];
  const size_t n = ndef_text::encode(
      reinterpret_cast<const uint8_t *>(text), 2, inner, sizeof(inner));
  uint8_t buf[ndef_text::kMaxEncoded + 3];
  buf[0] = 0x00;
  buf[1] = 0x00;
  buf[2] = 0x00;
  memcpy(buf + 3, inner, n);
  uint8_t out[ndef_text::kMaxText];
  size_t out_len = 0;
  expect("decode skips leading NULL TLVs",
         ndef_text::decode(buf, n + 3, out, sizeof(out), &out_len) &&
             out_len == 2 && out[0] == 'X' && out[1] == 'y');
}

void test_ndef_decode_rejects_malformed() {
  uint8_t out[ndef_text::kMaxText];
  size_t out_len = 0;
  const uint8_t not_ndef[4] = {0x01, 0x02, 0x03, 0x04};
  expect("non-NDEF leading TLV rejected",
         !ndef_text::decode(not_ndef, sizeof(not_ndef), out, sizeof(out),
                            &out_len));
  const uint8_t truncated[3] = {0x03, 0x20, 0xD1};  // claims 0x20 body bytes
  expect("truncated record rejected",
         !ndef_text::decode(truncated, sizeof(truncated), out, sizeof(out),
                            &out_len));
}

// --- PulseActivity --------------------------------------------------------

void test_activity_fires_at_threshold() {
  PulseActivity act({/*fire_threshold=*/5, /*idle_decay=*/1});

  expect("no fire below threshold (1)", !act.update(2));
  expect("no fire below threshold (2)", !act.update(2));
  expect("fires when accumulation reaches threshold", act.update(1));
  expect("fired count is the accumulated total", act.report() == 5);
  expect("accumulator reset after fire", !act.update(1));
}

void test_activity_idle_decays_stray_pulses() {
  PulseActivity act({/*fire_threshold=*/5, /*idle_decay=*/2});

  expect("below threshold accumulates", !act.update(4));
  act.update(0);  // idle: 4 -> 2
  act.update(0);  // idle: 2 -> 0
  expect("stray pulses decayed away, no false fire", !act.update(4));
}

void test_activity_slow_drip_still_fires() {
  PulseActivity act({/*fire_threshold=*/5, /*idle_decay=*/3});

  // A steady 1-pulse/tick drip never hits an idle tick, so decay never applies.
  expect("drip tick 1", !act.update(1));
  expect("drip tick 2", !act.update(1));
  expect("drip tick 3", !act.update(1));
  expect("drip tick 4", !act.update(1));
  expect("drip reaches threshold on the fifth tick", act.update(1));
  expect("drip fired count", act.report() == 5);
}

void test_activity_report_saturates() {
  PulseActivity act({/*fire_threshold=*/10, /*idle_decay=*/1});

  expect("vigorous spin fires", act.update(1000));
  expect("report saturates at 255", act.report() == 255);
}

// --- AnalogEdges ----------------------------------------------------------

AnalogEdges::Config edges_config(uint16_t min_span = 100, uint16_t decay = 1) {
  return AnalogEdges::Config{min_span, decay, /*hysteresis_pct=*/20};
}

// Feed n periods of a square-ish train between `high` and `low`, `dwell` samples
// at each level, and return how many pulses were counted.
int feed_train(AnalogEdges &edges, uint16_t high, uint16_t low, int periods,
               int dwell) {
  int pulses = 0;
  for (int p = 0; p < periods; p++) {
    for (int i = 0; i < dwell; i++) {
      if (edges.update(high)) pulses++;
    }
    for (int i = 0; i < dwell; i++) {
      if (edges.update(low)) pulses++;
    }
  }
  return pulses;
}

void test_edges_counts_a_partial_swing() {
  AnalogEdges edges(edges_config());

  // The wheels never pull the line down to 0: this is the 3.3 V -> ~2.2 V swing
  // a digital input reads as a constant HIGH.
  const int pulses = feed_train(edges, 4000, 2700, 10, 8);

  expect("partial swing counts one pulse per period", pulses == 10);
}

void test_edges_counts_falling_only() {
  AnalogEdges edges(edges_config());

  // Two crossings per period, one pulse: the count has to match what the
  // interrupt backend produced, since PulseActivity is tuned against it.
  const int pulses = feed_train(edges, 4000, 2700, 5, 8);

  expect("one pulse per period, not two", pulses == 5);
}

void test_edges_adapts_to_a_different_low_level() {
  AnalogEdges a(edges_config());
  AnalogEdges b(edges_config());

  // Each wheel occludes differently, so no fixed threshold can serve both.
  expect("deep swing counts", feed_train(a, 4000, 1200, 6, 8) == 6);
  expect("shallow swing counts the same", feed_train(b, 4000, 3400, 6, 8) == 6);
}

void test_edges_ignores_an_unmodulated_line() {
  AnalogEdges edges(edges_config(/*min_span=*/100));

  int pulses = 0;
  // A still ball: the line sits at its level with a couple of counts of ADC
  // noise on it. Nothing here is a pulse.
  for (int i = 0; i < 200; i++) {
    if (edges.update(static_cast<uint16_t>(4000 + (i % 3)))) pulses++;
  }

  expect("noise on a still line is not a spin", pulses == 0);
  expect("span stays below min_span", edges.span() < 100);
}

void test_edges_stops_counting_after_motion_stops() {
  AnalogEdges edges(edges_config(/*min_span=*/100, /*decay=*/4));

  feed_train(edges, 4000, 2700, 6, 8);

  int pulses = 0;
  // The ball stops with the line held high; the envelope collapses onto it.
  for (int i = 0; i < 500; i++) {
    if (edges.update(4000)) pulses++;
  }

  expect("a held level fires at most the one crossing", pulses <= 1);
  expect("envelope collapsed onto the resting level", edges.span() < 100);
}

void test_edges_hysteresis_rejects_dithering_at_the_midpoint() {
  AnalogEdges edges(edges_config());

  feed_train(edges, 4000, 2700, 4, 8);
  const uint16_t mid = static_cast<uint16_t>(edges.low() + edges.span() / 2);

  int pulses = 0;
  // A slow crossing that lingers around the midpoint must count once, not once
  // per wobble.
  for (int i = 0; i < 40; i++) {
    if (edges.update(static_cast<uint16_t>(mid + (i % 2 ? 5 : -5)))) pulses++;
  }

  expect("dithering across the midpoint counts nothing", pulses == 0);
}

void test_edges_span_reports_the_swing() {
  AnalogEdges edges(edges_config());

  expect("span is zero before any sample", edges.span() == 0);
  feed_train(edges, 4000, 2700, 4, 8);
  expect("span reports the tracked swing", edges.span() > 1200);
}

}  // namespace

int main() {
  test_axis_calibration();
  test_axis_clamping();
  test_axis_deadzone();
  test_axis_ema_convergence();

  test_edges_counts_a_partial_swing();
  test_edges_counts_falling_only();
  test_edges_adapts_to_a_different_low_level();
  test_edges_ignores_an_unmodulated_line();
  test_edges_stops_counting_after_motion_stops();
  test_edges_hysteresis_rejects_dithering_at_the_midpoint();
  test_edges_span_reports_the_swing();

  test_encoder_forward_detent();
  test_encoder_reverse_detent();
  test_encoder_multi_detent();
  test_encoder_bounce_and_invalid_ignored();

  test_button_debounce_and_events();
  test_button_bounce_resets_counter();

  test_reporter_suppresses_the_boot_burst();
  test_reporter_arms_once_and_stays_armed();
  test_reporter_settles_immediately_when_asked_to();
  test_reporter_reset_disarms();

  test_nfc_arrival_edge_once();
  test_nfc_removal_debounce();
  test_nfc_pending_write_fires_on_next_tag();
  test_nfc_write_on_already_present_tag();
  test_nfc_held_tag_confirmed_without_detect();
  test_nfc_lost_selection_reselects_silently();
  test_nfc_swap_between_polls_is_an_arrival();

  test_ndef_encode_roundtrip();
  test_ndef_empty_string();
  test_ndef_max_length_roundtrip();
  test_ndef_rejects_over_length_and_small_buffer();
  test_ndef_decode_tolerates_leading_null_tlvs();
  test_ndef_decode_rejects_malformed();

  test_activity_fires_at_threshold();
  test_activity_idle_decays_stray_pulses();
  test_activity_slow_drip_still_fires();
  test_activity_report_saturates();

  if (g_failures == 0) {
    printf("\nAll io tests passed.\n");
    return 0;
  }
  printf("\n%d io test(s) failed.\n", g_failures);
  return 1;
}
