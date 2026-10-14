#pragma once

#include <stddef.h>
#include <stdint.h>

#include "led_matrix.h"

/// @file
/// Drives LedMatrix::refresh_step() off the main loop using a periodic
/// `esp_timer`. The timer uses the default task-context dispatch (ESP_TIMER_TASK),
/// so the callback runs in a normal task — which is what makes it safe to drive
/// SPI shift-register column/row buses from the refresh (SPI must not run in a
/// hard ISR).
///
/// A FreeRTOS mutex (not a portMUX spinlock) serializes set()/clear() against
/// the refresh: a mutex blocks the competing task without disabling interrupts,
/// so it can safely span the SPI writes inside refresh_step(), and it carries
/// priority inheritance. Write the framebuffer only through this wrapper once
/// begin() has been called.

class LedRefreshTimer {
 public:
  explicit LedRefreshTimer(LedMatrix &matrix);
  ~LedRefreshTimer();

  /// @brief Start refreshing so the whole frame is shown `frame_hz` times per
  ///        second (per-row period = 1e6 / (frame_hz * rows) µs).
  /// @return false if the timer/mutex could not be created.
  bool begin(uint32_t frame_hz);
  void end();

  void set(size_t row, size_t col, bool on);
  void clear();

 private:
  static void on_timer(void *arg);

  LedMatrix &matrix_;
  void *timer_handle_;  // esp_timer_handle_t
  void *mutex_;         // SemaphoreHandle_t
};
