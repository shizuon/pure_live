// Copyright (c) 2026 Pure Live contributors.
// SPDX-License-Identifier: MIT
#ifndef MEDIA_KIT_MAILBOX_FRAME_STATE_H_
#define MEDIA_KIT_MAILBOX_FRAME_STATE_H_

#include <atomic>

// Slot ownership for a single render producer and a Flutter consumer.
// GPU fences and textures remain in MailboxSwapChain. Only completed_slot()
// is read from the consumer thread; all other operations are producer-only.
class MailboxFrameState {
 public:
  int write_slot() const { return write_; }
  int pending_slot() const { return pending_; }
  int completed_slot() const {
    return completed_.load(std::memory_order_acquire);
  }

  // Called after rendering/signalling write_. Never recycle a pending slot
  // until its fence completes. Replacing it every frame would starve
  // presentation whenever GPU latency exceeds one render interval.
  bool submit(bool pending_complete) {
    if (pending_ >= 0) {
      if (!pending_complete) return false;
      spare_ = completed_.load(std::memory_order_relaxed);
      completed_.store(pending_, std::memory_order_release);
    }
    pending_ = write_;
    write_ = free_;
    free_ = spare_;
    return true;
  }

  // Resize calls this only after the old consumer has detached.
  void reset() {
    write_ = 0;
    free_ = 1;
    pending_ = -1;
    spare_ = 3;
    completed_.store(2, std::memory_order_release);
  }

 private:
  int write_ = 0;
  int free_ = 1;
  int pending_ = -1;
  int spare_ = 3;
  std::atomic<int> completed_{2};
};

#endif  // MEDIA_KIT_MAILBOX_FRAME_STATE_H_
