#include "../../third_party/media_kit_video/windows/mailbox_frame_state.h"

#include <array>
#include <cassert>
#include <iostream>

struct GpuSimulation {
  MailboxFrameState state;
  std::array<int, 4> complete_at{};
  std::array<int, 4> frame_number{};
  int clock = 0;
  int promotions = 0;
  int last_displayed_frame = 0;

  void render(int latency) {
    ++clock;
    const int write = state.write_slot();
    const int pending = state.pending_slot();
    const int displayed = state.completed_slot();
    assert(write != pending && write != displayed);
    if (pending >= 0) assert(pending != displayed);
    complete_at[write] = clock + latency;
    frame_number[write] = clock;
    const bool ready = pending < 0 || complete_at[pending] <= clock;
    const bool submitted = state.submit(ready);
    if (pending >= 0 && !ready) {
      // Keep polling this exact fence, and keep the currently displayed slot
      // untouched while rendering can continue in the private write slot.
      assert(!submitted);
      assert(state.pending_slot() == pending);
      assert(state.completed_slot() == displayed);
      assert(state.write_slot() == write);
    }
    if (state.completed_slot() != displayed) {
      const int slot = state.completed_slot();
      assert(complete_at[slot] <= clock);
      assert(frame_number[slot] > last_displayed_frame);
      last_displayed_frame = frame_number[slot];
      ++promotions;
    }
  }
};

int main() {
  // Startup and stable playback must continue at both normal and slow GPU
  // completion rates. The previous mailbox stopped presenting at latency=2.
  for (const int latency : {1, 2, 3, 5, 20}) {
    GpuSimulation gpu;
    for (int i = 0; i < 120; ++i) gpu.render(latency);
    assert(gpu.promotions == 119 / latency);
    assert(gpu.last_displayed_frame > 0);
    std::cout << "latency=" << latency
              << " promotions=" << gpu.promotions << '\n';
  }

  // Changing load / monitor presentation must recover without re-opening
  // the player. Consumer sampling frequency does not drive producer progress.
  GpuSimulation gpu;
  for (int i = 0; i < 20; ++i) gpu.render(1);
  const int before_slow = gpu.promotions;
  for (int i = 0; i < 60; ++i) gpu.render(5);
  assert(gpu.promotions > before_slow);
  for (int i = 0; i < 20; ++i) gpu.render(1);
  assert(gpu.last_displayed_frame >= 98);

  gpu.state.reset();
  assert(gpu.state.write_slot() == 0);
  assert(gpu.state.pending_slot() == -1);
  assert(gpu.state.completed_slot() == 2);
  gpu.render(2);
  gpu.render(2);
  gpu.render(2);
  assert(gpu.state.completed_slot() == 0);
  std::cout << "mailbox frame-state regression checks passed\n";
}
