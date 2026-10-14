#include <cstdio>
#include <cstring>

#include "cobs.h"
#include "frame_reader.h"
#include "framing.h"
#include "protocol.h"

/// @file
/// Host-side unit tests for the pure COBS/framing logic. No Arduino, no board:
/// compiled and run natively via `make test`. Vectors are the canonical COBS
/// examples plus the 254-byte boundary that exercises the block-split path.

namespace {

int g_failures = 0;

void expect_bytes(const char *name, const uint8_t *got, size_t got_len,
                  const uint8_t *want, size_t want_len) {
  bool ok = got_len == want_len && memcmp(got, want, want_len) == 0;
  if (ok) {
    printf("ok   - %s\n", name);
    return;
  }

  g_failures++;
  printf("FAIL - %s\n      got (%zu):", name, got_len);
  for (size_t i = 0; i < got_len; i++) printf(" %02X", got[i]);
  printf("\n      want(%zu):", want_len);
  for (size_t i = 0; i < want_len; i++) printf(" %02X", want[i]);
  printf("\n");
}

void test_cobs_vectors() {
  {
    const uint8_t in[] = {0x00};
    const uint8_t want[] = {0x01, 0x01};
    uint8_t out[8];
    size_t n = cobs_encode(in, sizeof(in), out);
    expect_bytes("single zero", out, n, want, sizeof(want));
  }
  {
    const uint8_t in[] = {0x11, 0x22, 0x00, 0x33};
    const uint8_t want[] = {0x03, 0x11, 0x22, 0x02, 0x33};
    uint8_t out[8];
    size_t n = cobs_encode(in, sizeof(in), out);
    expect_bytes("zero in the middle", out, n, want, sizeof(want));
  }
  {
    const uint8_t in[] = {0x11, 0x22, 0x33, 0x44};
    const uint8_t want[] = {0x05, 0x11, 0x22, 0x33, 0x44};
    uint8_t out[8];
    size_t n = cobs_encode(in, sizeof(in), out);
    expect_bytes("no zeros", out, n, want, sizeof(want));
  }
  {
    uint8_t out[2];
    const uint8_t want[] = {0x01};
    size_t m = cobs_encode(nullptr, 0, out);
    expect_bytes("empty payload", out, m, want, sizeof(want));
  }
}

void test_block_split_at_254() {
  uint8_t in[254];
  memset(in, 0x01, sizeof(in));

  uint8_t out[300];
  size_t n = cobs_encode(in, sizeof(in), out);

  uint8_t want[256];
  want[0] = 0xFF;
  memset(want + 1, 0x01, 254);
  want[255] = 0x01;

  expect_bytes("254 non-zero bytes split block", out, n, want, sizeof(want));

  if (cobs_encode_bounds(254) != 256) {
    g_failures++;
    printf("FAIL - cobs_encode_bounds(254) = %zu, want 256\n",
           cobs_encode_bounds(254));
  } else {
    printf("ok   - cobs_encode_bounds(254)\n");
  }
}

void test_frame_appends_delimiter() {
  const uint8_t in[] = {0x11, 0x22, 0x00, 0x33};
  const uint8_t want[] = {0x03, 0x11, 0x22, 0x02, 0x33, 0x00};
  uint8_t out[16];
  size_t n = frame_encode(in, sizeof(in), out);
  expect_bytes("frame appends 0x00 delimiter", out, n, want, sizeof(want));

  if (frame_encoded_bounds(4) != cobs_encode_bounds(4) + 1) {
    g_failures++;
    printf("FAIL - frame_encoded_bounds mismatch\n");
  } else {
    printf("ok   - frame_encoded_bounds\n");
  }
}

void test_frame_is_module_headed() {
  const uint8_t body[] = {static_cast<uint8_t>(proto::MsgType::Hello)};
  uint8_t in[1 + sizeof(body)];
  in[0] = proto::kModuleId;
  memcpy(in + 1, body, sizeof(body));

  uint8_t out[16];
  size_t n = frame_encode(in, sizeof(in), out);

  const uint8_t want[] = {0x03, proto::kModuleId,
                          static_cast<uint8_t>(proto::MsgType::Hello), 0x00};
  expect_bytes("frame is headed by module id", out, n, want, sizeof(want));
}

void expect_true(const char *name, bool cond) {
  if (cond) {
    printf("ok   - %s\n", name);
  } else {
    g_failures++;
    printf("FAIL - %s\n", name);
  }
}

void test_cobs_roundtrip() {
  const uint8_t payloads[][6] = {
      {0x00, 0x11, 0x00, 0x22, 0x00, 0x33},
      {0xFF, 0xFE, 0xFD, 0xFC, 0xFB, 0xFA},
      {0x00, 0x00, 0x00, 0x00, 0x00, 0x00},
  };

  for (size_t p = 0; p < 3; p++) {
    uint8_t enc[16];
    uint8_t dec[16];
    size_t enc_len = cobs_encode(payloads[p], 6, enc);
    size_t dec_len = cobs_decode(enc, enc_len, dec);
    bool ok = dec_len == 6 && memcmp(dec, payloads[p], 6) == 0;
    char name[64];
    snprintf(name, sizeof(name), "cobs roundtrip case %zu", p);
    expect_true(name, ok);
  }
}

void feed(FrameReader &reader, const uint8_t *bytes, size_t len,
          size_t *out_len) {
  *out_len = 0;
  for (size_t i = 0; i < len; i++) {
    size_t n = reader.push(bytes[i]);
    if (n > 0) *out_len = n;
  }
}

void test_frame_reader_reassembles() {
  uint8_t enc[64], dec[64];
  FrameReader reader(enc, sizeof(enc), dec, sizeof(dec));

  const uint8_t body[] = {0x01, 0x10, 0x00, 0x01};
  uint8_t wire[16];
  size_t wire_len = frame_encode(body, sizeof(body), wire);

  size_t got_len = 0;
  feed(reader, wire, wire_len, &got_len);

  bool ok = got_len == sizeof(body) && memcmp(reader.frame(), body, got_len) == 0;
  expect_true("FrameReader reassembles a delimited frame", ok);
}

void test_frame_reader_two_frames_and_noise() {
  uint8_t enc[64], dec[64];
  FrameReader reader(enc, sizeof(enc), dec, sizeof(dec));

  const uint8_t a[] = {0x05, 0xAA};
  const uint8_t b[] = {0x07, 0xBB, 0xCC};
  uint8_t wire_a[16], wire_b[16];
  size_t la = frame_encode(a, sizeof(a), wire_a);
  size_t lb = frame_encode(b, sizeof(b), wire_b);

  size_t got = 0;
  feed(reader, wire_a, la, &got);
  bool ok_a = got == sizeof(a) && memcmp(reader.frame(), a, got) == 0;

  size_t leading_delimiter = reader.push(0x00);
  bool ok_noise = leading_delimiter == 0;

  feed(reader, wire_b, lb, &got);
  bool ok_b = got == sizeof(b) && memcmp(reader.frame(), b, got) == 0;

  expect_true("FrameReader decodes first frame", ok_a);
  expect_true("FrameReader ignores empty frame between delimiters", ok_noise);
  expect_true("FrameReader decodes second frame after noise", ok_b);
}

}  // namespace

int main() {
  test_cobs_vectors();
  test_block_split_at_254();
  test_cobs_roundtrip();
  test_frame_appends_delimiter();
  test_frame_is_module_headed();
  test_frame_reader_reassembles();
  test_frame_reader_two_frames_and_noise();

  if (g_failures == 0) {
    printf("\nAll tests passed.\n");
    return 0;
  }
  printf("\n%d test(s) failed.\n", g_failures);
  return 1;
}
