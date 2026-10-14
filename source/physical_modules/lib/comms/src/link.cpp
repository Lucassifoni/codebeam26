#include "link.h"

#include <Arduino.h>
#include <string.h>

#include "frame_reader.h"
#include "framing.h"
#include "protocol.h"

namespace serial_link {
namespace {

constexpr size_t kBodyCapacity = 1 + proto::kMaxPayloadBytes;

uint8_t g_module_id = 0;

uint8_t g_rx_encoded[frame_encoded_bounds(kBodyCapacity)];
uint8_t g_rx_decoded[kBodyCapacity];
FrameReader g_reader(g_rx_encoded, sizeof(g_rx_encoded), g_rx_decoded,
                     sizeof(g_rx_decoded));

}  // namespace

bool send_frame(const uint8_t *payload, size_t length) {
  if (length > proto::kMaxPayloadBytes) {
    return false;
  }

  uint8_t body[kBodyCapacity];
  body[0] = g_module_id;
  memcpy(body + 1, payload, length);
  const size_t body_len = 1 + length;

  uint8_t frame[frame_encoded_bounds(kBodyCapacity)];
  const size_t n = frame_encode(body, body_len, frame);
  return Serial.write(frame, n) == n;
}

bool begin(unsigned long baud, uint8_t module_id) {
  g_module_id = module_id;
  Serial.begin(baud);

  const uint8_t hello = static_cast<uint8_t>(proto::MsgType::Hello);

  for (uint8_t attempt = 0; attempt < proto::kHelloRetries; ++attempt) {
    send_frame(&hello, sizeof(hello));

    const unsigned long deadline = millis() + proto::kHelloAckTimeoutMs;
    while (static_cast<long>(millis() - deadline) < 0) {
      if (Serial.available() > 0) {
        Serial.read();
        return true;
      }
      delay(1);
    }
  }

  return false;
}

void poll(CommandHandler on_command) {
  while (Serial.available() > 0) {
    const int byte = Serial.read();
    if (byte < 0) {
      break;
    }

    const size_t length = g_reader.push(static_cast<uint8_t>(byte));
    if (length == 0) {
      continue;
    }

    const uint8_t *frame = g_reader.frame();
    if (frame[0] != g_module_id) {
      continue;
    }
    on_command(frame + 1, length - 1);
  }
}

}  // namespace serial_link
