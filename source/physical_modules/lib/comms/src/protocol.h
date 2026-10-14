#pragma once

#include <stddef.h>
#include <stdint.h>

/// @file
/// Wire protocol constants shared between the device firmware and the host.

/// @brief Distinct identity for this physical module on a shared serial bus.
///
/// Every frame is headed by this byte so the host can demultiplex modules. Each
/// board is flashed with a unique value; override per build without editing
/// source, e.g.:
///   arduino-cli compile ... --build-property "compiler.cpp.extra_flags=-DMODULE_ID=0x02"
#ifndef MODULE_ID
#define MODULE_ID 0x01
#endif

namespace proto {

/// @brief Type of the leading frame discriminant byte.
using ModuleId = uint8_t;

/// @brief This module's identity, taken from the MODULE_ID build flag.
constexpr ModuleId kModuleId = static_cast<ModuleId>(MODULE_ID);

/// @brief Serial line speed; matches the known-good flashing/monitor config.
constexpr unsigned long kBaud = 115200;

/// @brief Largest payload a single frame may carry, sized for the on-stack
///        encode buffer in the link layer.
constexpr size_t kMaxPayloadBytes = 250;

/// @brief Number of hello frames emitted at boot while waiting for the host.
constexpr uint8_t kHelloRetries = 20;

/// @brief Per-attempt window to receive a host acknowledgement, in ms.
constexpr unsigned long kHelloAckTimeoutMs = 250;

/// @brief Transport-level message types, common to every module. The first
///        body byte (after the module discriminant) carries this value. Module-
///        specific command and report opcodes live in each module's own code
///        and must not collide with these reserved values.
enum class MsgType : uint8_t {
  Hello = 0x01,
};

}  // namespace proto
