#pragma once

/// @file
/// Application entry points. This is the internal "business logic library":
/// the Arduino sketch (module_2.ino) is a thin shim that forwards setup() and
/// loop() here, so the real logic lives in plain compilation units that can
/// evolve and be tested independently of the .ino.

/// @brief One-time initialisation: configure IO and bring up the host link.
void app_setup();

/// @brief Repeated work; returns quickly so the main loop stays responsive.
void app_loop();
