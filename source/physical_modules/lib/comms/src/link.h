#pragma once

#include <stddef.h>
#include <stdint.h>

/// @file
/// Serial transport: the only module that touches the Arduino Serial API.
/// Keeps the COBS/framing logic (cobs.h, framing.h) free of hardware deps so it
/// stays host-testable.

namespace serial_link {

/// @brief Callback invoked for each inbound frame addressed to this module.
/// @param command  message body with the leading module-id byte already
///        stripped; `command[0]` is the module-specific opcode.
/// @param length   number of bytes in `command` (0 if the frame carried only
///        the discriminant).
using CommandHandler = void (*)(const uint8_t *command, size_t length);

/// @brief Bring up the serial link and announce presence to the host.
///
/// Opens the port at `baud` and records `module_id` as the discriminant byte
/// prepended to every outgoing frame. Then repeatedly emits a Hello frame,
/// waiting a bounded time for any byte from the host as acknowledgement.
/// Returns once the host acknowledges or after all retries elapse, so an absent
/// host never blocks boot indefinitely.
/// @param baud       serial line speed.
/// @param module_id  identity placed at the head of every frame from this module.
/// @return true if the host acknowledged, false if the handshake timed out.
bool begin(unsigned long baud, uint8_t module_id);

/// @brief Send a frame to the host: [module_id][payload], COBS-encoded.
///
/// The module discriminant byte recorded in begin() is prepended automatically,
/// so callers pass only the message body.
/// @param payload  message body (may contain 0x00).
/// @param length   number of body bytes; must not exceed proto::kMaxPayloadBytes.
/// @return true if the frame was fully written, false if oversized or the
///         underlying write was short.
bool send_frame(const uint8_t *payload, size_t length);

/// @brief Drain whatever inbound serial bytes are already buffered, reassembling
///        frames. Never blocks waiting for data.
///
/// Consumes only the bytes currently available and returns; a loop pass with no
/// pending bytes is simply a turn without a message. A frame split across calls
/// is preserved between invocations and completes on a later pass. For every
/// complete frame whose leading discriminant byte matches this module's id,
/// `on_command` is invoked with the remaining body; frames addressed to other
/// modules on the shared bus are silently ignored.
void poll(CommandHandler on_command);

}  // namespace serial_link
