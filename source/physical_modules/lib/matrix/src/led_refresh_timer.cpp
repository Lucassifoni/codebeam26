#include "led_refresh_timer.h"

#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

LedRefreshTimer::LedRefreshTimer(LedMatrix &matrix)
    : matrix_(matrix), timer_handle_(nullptr), mutex_(nullptr) {}

LedRefreshTimer::~LedRefreshTimer() {
  end();
  if (mutex_ != nullptr) {
    vSemaphoreDelete(static_cast<SemaphoreHandle_t>(mutex_));
    mutex_ = nullptr;
  }
}

void LedRefreshTimer::on_timer(void *arg) {
  LedRefreshTimer *self = static_cast<LedRefreshTimer *>(arg);
  SemaphoreHandle_t mutex = static_cast<SemaphoreHandle_t>(self->mutex_);
  if (xSemaphoreTake(mutex, portMAX_DELAY) == pdTRUE) {
    self->matrix_.refresh_step();
    xSemaphoreGive(mutex);
  }
}

bool LedRefreshTimer::begin(uint32_t frame_hz) {
  const size_t rows = matrix_.rows();
  if (rows == 0 || frame_hz == 0) {
    return false;
  }
  if (mutex_ == nullptr) {
    mutex_ = xSemaphoreCreateMutex();
    if (mutex_ == nullptr) {
      return false;
    }
  }

  uint64_t period_us = 1000000ULL / (static_cast<uint64_t>(frame_hz) * rows);
  if (period_us == 0) {
    period_us = 1;
  }

  esp_timer_create_args_t args = {};
  args.callback = &LedRefreshTimer::on_timer;
  args.arg = this;
  args.dispatch_method = ESP_TIMER_TASK;
  args.name = "led_refresh";

  esp_timer_handle_t handle = nullptr;
  if (esp_timer_create(&args, &handle) != ESP_OK) {
    return false;
  }
  timer_handle_ = handle;
  return esp_timer_start_periodic(handle, period_us) == ESP_OK;
}

void LedRefreshTimer::end() {
  if (timer_handle_ != nullptr) {
    esp_timer_handle_t handle = static_cast<esp_timer_handle_t>(timer_handle_);
    esp_timer_stop(handle);
    esp_timer_delete(handle);
    timer_handle_ = nullptr;
  }
}

void LedRefreshTimer::set(size_t row, size_t col, bool on) {
  SemaphoreHandle_t mutex = static_cast<SemaphoreHandle_t>(mutex_);
  if (mutex != nullptr && xSemaphoreTake(mutex, portMAX_DELAY) == pdTRUE) {
    matrix_.set(row, col, on);
    xSemaphoreGive(mutex);
  } else {
    matrix_.set(row, col, on);
  }
}

void LedRefreshTimer::clear() {
  SemaphoreHandle_t mutex = static_cast<SemaphoreHandle_t>(mutex_);
  if (mutex != nullptr && xSemaphoreTake(mutex, portMAX_DELAY) == pdTRUE) {
    matrix_.clear();
    xSemaphoreGive(mutex);
  } else {
    matrix_.clear();
  }
}
