#include "key_reporter.h"

KeyReporter::KeyReporter(uint8_t settle_scans)
    : settle_scans_(settle_scans), scans_(0), armed_(false) {}

bool KeyReporter::settle() {
  if (armed_) {
    return false;
  }

  scans_++;
  if (scans_ < settle_scans_) {
    return false;
  }

  armed_ = true;
  return true;
}

void KeyReporter::reset() {
  scans_ = 0;
  armed_ = false;
}
