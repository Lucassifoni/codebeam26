#include "key_panel.h"

#include "key_snapshot.h"

KeyPanel::KeyPanel(KeyMatrix &keys, uint8_t settle_scans)
    : keys_(keys), reporter_(settle_scans) {}

size_t KeyPanel::snapshot_bytes() const {
  const size_t bytes = key_snapshot::bytes(keys_.drives(), keys_.senses());
  return bytes < kMaxSnapshotBytes ? bytes : kMaxSnapshotBytes;
}

void KeyPanel::on_scan_event(const KeyEvent &event, void *ctx) {
  Trampoline *t = static_cast<Trampoline *>(ctx);
  if (!t->panel->armed() || t->on_event == nullptr) {
    return;
  }
  t->on_event(event, t->ctx);
}

void KeyPanel::step(KeyEventHandler on_event, SnapshotHandler on_snapshot,
                    void *ctx) {
  Trampoline trampoline{this, on_event, ctx};

  // Scan first: the snapshot has to describe the table this scan committed, not
  // the one before it. The events it produces are dropped until the panel arms,
  // and the scan that arms it is the one the snapshot speaks for.
  keys_.scan(&KeyPanel::on_scan_event, &trampoline);

  if (reporter_.settle()) {
    resync(on_snapshot, ctx);
  }
}

void KeyPanel::resync(SnapshotHandler on_snapshot, void *ctx) {
  if (on_snapshot == nullptr) {
    return;
  }
  const size_t bytes = snapshot_bytes();
  uint8_t bits[kMaxSnapshotBytes];
  key_snapshot::pack(keys_, bits, bytes);
  on_snapshot(bits, bytes, ctx);
}
