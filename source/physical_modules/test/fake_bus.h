#pragma once

#include <cstdint>
#include <cstring>
#include <vector>

#include "bit_bus.h"

/// @file
/// Host-only fakes for the bus interfaces, used by the matrix unit tests. Not
/// compiled into firmware. They record/inject bit patterns so the pure matrix
/// logic can be exercised with no hardware.

/// @brief Records every write() as a snapshot, for inspecting refresh sequences.
class FakeOutputBus : public OutputBus {
 public:
  explicit FakeOutputBus(size_t width) : width_(width) {}

  size_t width() const override { return width_; }

  void write(const uint8_t *bits) override {
    const size_t nbytes = (width_ + 7) / 8;
    writes.emplace_back(bits, bits + nbytes);
  }

  bool bit_in(const std::vector<uint8_t> &w, size_t i) const {
    return (w[i >> 3] >> (i & 7)) & 1u;
  }

  int one_hot_index(const std::vector<uint8_t> &w) const {
    int found = -1;
    for (size_t i = 0; i < width_; i++) {
      if (bit_in(w, i)) {
        if (found != -1) return -2;
        found = static_cast<int>(i);
      }
    }
    return found;
  }

  size_t width_;
  std::vector<std::vector<uint8_t>> writes;
};

/// @brief Returns a settable fixed reading; used to probe drive behaviour.
class FakeInputBus : public InputBus {
 public:
  explicit FakeInputBus(size_t width)
      : width_(width), data_((width + 7) / 8, 0) {}

  size_t width() const override { return width_; }
  void read(uint8_t *bits) const override {
    memcpy(bits, data_.data(), data_.size());
  }

  size_t width_;
  std::vector<uint8_t> data_;
};

/// @brief Couples a one-hot drive OutputBus with a sense InputBus: reading the
/// sense bus returns the pressed columns for whichever drive line is currently
/// active, modelling a real scanned key matrix.
class ScriptedKeyIo {
 public:
  ScriptedKeyIo(size_t drives, size_t senses)
      : drives_(drives),
        senses_(senses),
        sense_bytes_((senses + 7) / 8),
        truth_(drives * ((senses + 7) / 8), 0),
        drive_(*this),
        sense_(*this) {}

  void press(size_t d, size_t s, bool on) {
    uint8_t &byte = truth_[d * sense_bytes_ + (s >> 3)];
    const uint8_t mask = static_cast<uint8_t>(1u << (s & 7));
    if (on) {
      byte |= mask;
    } else {
      byte &= static_cast<uint8_t>(~mask);
    }
  }

  OutputBus &drive() { return drive_; }
  InputBus &sense() { return sense_; }

 private:
  class Drive : public OutputBus {
   public:
    explicit Drive(ScriptedKeyIo &io) : io_(io) {}
    size_t width() const override { return io_.drives_; }
    void write(const uint8_t *bits) override {
      io_.active_ = -1;
      for (size_t i = 0; i < io_.drives_; i++) {
        if ((bits[i >> 3] >> (i & 7)) & 1u) io_.active_ = static_cast<int>(i);
      }
    }

   private:
    ScriptedKeyIo &io_;
  };

  class Sense : public InputBus {
   public:
    explicit Sense(ScriptedKeyIo &io) : io_(io) {}
    size_t width() const override { return io_.senses_; }
    void read(uint8_t *bits) const override {
      if (io_.active_ < 0) {
        memset(bits, 0, io_.sense_bytes_);
        return;
      }
      memcpy(bits, &io_.truth_[io_.active_ * io_.sense_bytes_],
             io_.sense_bytes_);
    }

   private:
    ScriptedKeyIo &io_;
  };

  size_t drives_;
  size_t senses_;
  size_t sense_bytes_;
  std::vector<uint8_t> truth_;
  int active_ = -1;
  Drive drive_;
  Sense sense_;
};
