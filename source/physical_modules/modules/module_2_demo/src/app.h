#pragma once

/// @file
/// Application entry points. The Arduino sketch (module_2_demo.ino) is a thin
/// shim that forwards setup() and loop() here.

/// @brief One-time initialisation: configure IO and bring up the host link.
void app_setup();

/// @brief Repeated work; returns quickly so the main loop stays responsive.
void app_loop();
