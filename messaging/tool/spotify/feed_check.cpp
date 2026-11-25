// Checks the PC's music feed (windows/runner/music_feed.h) on any computer, without a sound: c++ -std=c++17
// tool/spotify/feed_check.cpp -o build/spotify/feed-check && build/spotify/feed-check
#include "../../windows/runner/music_feed.h"

#include <cstdio>
#include <thread>

static int wrong = 0;
static void check(bool ok, const char* what) {
  if (!ok) {
    std::printf("FAIL: %s\n", what);
    wrong++;
  }
}

// Frames numbered from [from]: left is the number, right is its negative.
static std::vector<int16_t> block(int from, size_t frames) {
  std::vector<int16_t> b(frames * 2);
  for (size_t i = 0; i < frames; i++) {
    b[i * 2] = static_cast<int16_t>((from + static_cast<int>(i)) % 30000 + 1);
    b[i * 2 + 1] = static_cast<int16_t>(-b[i * 2]);
  }
  return b;
}

int main() {
  const size_t kF = MusicFeed::kFrames;
  std::vector<int16_t> out(kF * 2, 77);
  {
    MusicFeed f(20, 100);
    f.Read(out.data(), kF);
    check(out[0] == 0 && out[kF * 2 - 1] == 0, "nothing waiting is silence");
    f.Write(block(0, kF).data(), kF);
    f.Read(out.data(), kF);
    check(out[0] == 0, "too little waiting to begin");
    f.Write(block(480, kF).data(), kF);
    f.Read(out.data(), kF);
    check(out[0] == 1 && out[1] == -1, "left first, then right");
    check(out[(kF - 1) * 2] == 480, "in order");
    f.Read(out.data(), kF);
    check(out[0] == 481, "on from there");
    f.Read(out.data(), kF);
    check(out[0] == 0, "run dry is silence");
    f.Write(block(0, kF).data(), kF);
    f.Read(out.data(), kF);
    check(out[0] == 0, "and it waits for a little before it begins again");
  }
  {
    MusicFeed f(20, 100);
    f.Write(block(0, kF * 2).data(), kF * 2);
    f.Read(out.data(), kF);
    f.Write(block(960, 100).data(), 100);
    f.Read(out.data(), kF);
    f.Read(out.data(), kF);
    check(out[0] == 961 && out[99 * 2] == 1060 && out[100 * 2] == 0, "part of a block, then silence");
  }
  {
    // 100 ms is the most: the oldest goes.
    MusicFeed f(20, 100);
    for (int i = 0; i < 50; i++) f.Write(block(i * 480, kF).data(), kF);
    f.Read(out.data(), kF);
    check(out[0] == 40 * 480 + 1, "never more than it may hold behind");
    f.Clear();
    f.Write(block(0, 48000).data(), 48000);
    f.Read(out.data(), kF);
    check(out[0] == 48000 - 4800 - 30000 + 1, "a burst longer than all of it: its newest part");
    f.Clear();
    f.Read(out.data(), kF);
    check(out[0] == 0, "cleared");
    f.Write(nullptr, kF * 3);
    f.Read(out.data(), kF);
    check(out[0] == 0 && out[1] == 0, "a silent block");
  }
  {
    // Written and read by two threads at once, as it is: every frame whole, and in order.
    MusicFeed f(20, 100);
    bool on = true, whole = true;
    std::thread w([&] {
      for (int i = 0; i < 4000; i++) f.Write(block(i * 480, kF).data(), kF);
      on = false;
    });
    for (int i = 0; i < 4000; i++) {
      f.Read(out.data(), kF);
      for (size_t k = 0; k < kF; k++) whole = whole && out[k * 2] == -out[k * 2 + 1];
    }
    w.join();
    check(whole && !on, "two threads at once");
  }
  std::printf(wrong ? "%d wrong\n" : "PASS\n", wrong);
  return wrong ? 1 : 0;
}
