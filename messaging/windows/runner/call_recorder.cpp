// A call's voices, each to a file of its own, and each made an AAC file, on Windows (lib/voice/recorder.dart; Matt,
// 2026-11-21: "my friend is not able to see plugins added for recording calls on his pc"). As the Mac's
// (macos/Runner/CallRecorder.swift) and Android's: 48 kHz mono 16-bit, each held to the clock, silence where a voice
// came late or stopped.
//
// - This device's own voice: the block VoiceFx has just cleaned (CallRecorderMic, from voice_fx.cpp), silence while
//   muted.
// - Someone else's: a sink on their decoded track (libwebrtc's RTCAudioTrack::AddSink), found by its id through
//   flutter_webrtc's own instance, before this device's volume for them.
// - "encode": one voice's file as AAC in an .m4a, by Media Foundation's sink writer. The app puts the voices'
//   files together into one MP4 itself (lib/voice/mp4_merge.dart), so nothing here relies on Media Foundation
//   writing several sound tracks into one file.
// _wfopen: the standard library's plain file opening, as voicefx does (_CRT_SECURE_NO_WARNINGS).
#define _CRT_SECURE_NO_WARNINGS
#include "call_recorder.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "flutter_webrtc.h"
#include "flutter_webrtc/flutter_web_r_t_c_plugin.h"
#include "rtc_audio_track.h"
#include "rtc_media_track.h"

#include "main_thread.h"

namespace {

constexpr int kRate = 48000;

std::wstring Wide(const std::string& s) {
  if (s.empty()) return std::wstring();
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), out.data(), n);
  return out;
}

// One voice's file.
class Track {
 public:
  explicit Track(const std::string& path) {
    std::wstring w = Wide(path);
    size_t slash = w.find_last_of(L"\\/");
    if (slash != std::wstring::npos) CreateDirectoryW(w.substr(0, slash).c_str(), nullptr);
    file_ = _wfopen(w.c_str(), L"wb");
  }
  ~Track() { Close(); }

  bool ok() const { return file_ != nullptr; }

  int64_t written() {
    std::lock_guard<std::mutex> lock(mutex_);
    return written_;
  }

  // Writes [frames] samples given at [rate] in [channels] channels, held to [due] samples; [read] gives sample i of
  // channel c on the 16-bit scale.
  template <typename Read>
  void Write(int64_t due, int frames, int rate, int channels, Read read) {
    if (frames <= 0 || rate <= 0) return;
    std::lock_guard<std::mutex> lock(mutex_);
    if (!file_) return;
    const int n = static_cast<int>(static_cast<int64_t>(frames) * kRate / rate);
    if (due - written_ > kRate / 10) PadLocked(due - n);
    if (written_ - due > kRate / 10) return;
    const int ch = std::max(1, channels);
    std::vector<int16_t> out(static_cast<size_t>(n));
    for (int i = 0; i < n; i++) {
      double pos = static_cast<double>(i) * rate / kRate;
      int a = std::min(static_cast<int>(pos), frames - 1);
      int b = std::min(a + 1, frames - 1);
      float f = static_cast<float>(pos - a);
      float v = 0;
      for (int c = 0; c < ch; c++) v += read(a, c) * (1 - f) + read(b, c) * f;
      v /= ch;
      out[i] = static_cast<int16_t>(std::max(-32768.0f, std::min(32767.0f, v)));
    }
    fwrite(out.data(), 2, out.size(), file_);
    written_ += n;
  }

  void Pad(int64_t to) {
    std::lock_guard<std::mutex> lock(mutex_);
    PadLocked(to);
  }

  void Close() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (file_) fclose(file_);
    file_ = nullptr;
  }

 private:
  void PadLocked(int64_t to) {
    if (!file_) return;
    int64_t gap = to - written_;
    if (gap <= 0) return;
    static const std::vector<int16_t> zeros(kRate, 0);
    while (gap > 0) {
      int64_t n = std::min<int64_t>(gap, kRate);
      fwrite(zeros.data(), 2, static_cast<size_t>(n), file_);
      gap -= n;
    }
    written_ = to;
  }

  std::mutex mutex_;
  FILE* file_ = nullptr;
  int64_t written_ = 0;
};

std::atomic<int64_t> g_started{0};  // steady_clock microseconds at the start; 0 while not recording
std::atomic<bool> g_muted{false};

int64_t NowMicros() {
  return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

// Samples due now, by the clock since the recording began.
int64_t Due() {
  int64_t s = g_started.load();
  if (s == 0) return 0;
  return (NowMicros() - s) * kRate / 1000000;
}

// What WebRTC hands someone else's decoded sound to.
class Sink : public libwebrtc::AudioTrackSink {
 public:
  explicit Sink(std::shared_ptr<Track> track) : track_(std::move(track)) {}
  void OnData(const void* audio_data, int bits_per_sample, int sample_rate, size_t number_of_channels, size_t number_of_frames) override {
    if (!audio_data || g_started.load() == 0) return;
    const int ch = static_cast<int>(number_of_channels);
    const int frames = static_cast<int>(number_of_frames);
    if (bits_per_sample == 16) {
      const auto* s = static_cast<const int16_t*>(audio_data);
      track_->Write(Due(), frames, sample_rate, ch, [&](int i, int c) { return static_cast<float>(s[i * ch + c]); });
    } else if (bits_per_sample == 32) {
      const auto* f = static_cast<const float*>(audio_data);
      track_->Write(Due(), frames, sample_rate, ch, [&](int i, int c) { return f[i * ch + c] * 32768.0f; });
    }
  }

 private:
  std::shared_ptr<Track> track_;
};

struct Other {
  std::shared_ptr<Track> track;
  libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> rtc;
  std::unique_ptr<Sink> sink;
};

std::mutex g_mutex;
std::shared_ptr<Track> g_mic;
std::map<std::string, Other> g_others;
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;

libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack> RemoteAudio(const std::string& id) {
  auto* webrtc = FlutterWebRTCPluginSharedInstance();
  if (!webrtc) return nullptr;
  flutter_webrtc_plugin::FlutterWebRTCBase* base = webrtc;
  auto track = base->MediaTrackForId(id);
  if (!track || track->kind().std_string() != "audio") return nullptr;
  return libwebrtc::scoped_refptr<libwebrtc::RTCAudioTrack>(static_cast<libwebrtc::RTCAudioTrack*>(track.get()));
}

void Unhook(Other& o) {
  if (o.rtc && o.sink) o.rtc->RemoveSink(o.sink.get());
  o.rtc = nullptr;
  o.sink.reset();
}

bool Add(const std::string& key, const std::string& id, const std::string& path) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (g_started.load() == 0) return false;
  auto rtc = RemoteAudio(id);
  if (!rtc) return false;
  auto it = g_others.find(key);
  std::shared_ptr<Track> track;
  if (it != g_others.end()) {
    Unhook(it->second);
    track = it->second.track;
  } else {
    track = std::make_shared<Track>(path);
    if (!track->ok()) return false;
  }
  Other o;
  o.track = track;
  o.rtc = rtc;
  o.sink = std::make_unique<Sink>(track);
  o.rtc->AddSink(o.sink.get());
  g_others[key] = std::move(o);
  return true;
}

void Remove(const std::string& key) {
  std::lock_guard<std::mutex> lock(g_mutex);
  auto it = g_others.find(key);
  if (it != g_others.end()) Unhook(it->second);
}

// Stops every tap, fills each file to the end with silence, and says how many samples each has.
flutter::EncodableMap StopAll() {
  std::lock_guard<std::mutex> lock(g_mutex);
  flutter::EncodableMap counts;
  if (g_started.load() == 0) return counts;
  const int64_t end = Due();
  if (g_mic) {
    g_mic->Pad(end);
    g_mic->Close();
    counts[flutter::EncodableValue("me")] = flutter::EncodableValue(g_mic->written());
  }
  g_mic.reset();
  for (auto& [key, o] : g_others) {
    Unhook(o);
    o.track->Pad(end);
    o.track->Close();
    counts[flutter::EncodableValue(key)] = flutter::EncodableValue(o.track->written());
  }
  g_others.clear();
  g_started.store(0);
  return counts;
}

#define CHECK(hr, what)                  \
  do {                                   \
    if (FAILED(hr)) {                    \
      char b[96];                        \
      snprintf(b, sizeof b, "%s (0x%08lx)", what, static_cast<unsigned long>(hr)); \
      return std::string(b);             \
    }                                    \
  } while (0)

template <typename T>
void Free(T*& p) {
  if (p) p->Release();
  p = nullptr;
}

// [in] (48 kHz mono 16-bit) as AAC in an .m4a at [out], at [bytes_per_second] (12000, 16000, 20000 or 24000: what
// Media Foundation's AAC encoder takes); the reason in words where it couldn't.
std::string Encode(const std::string& in, const std::string& out, int bytes_per_second = 16000) {
  FILE* src = _wfopen(Wide(in).c_str(), L"rb");
  if (!src) return "can't read " + in;
  IMFSinkWriter* writer = nullptr;
  IMFMediaType* target = nullptr;
  IMFMediaType* given = nullptr;
  struct Done {
    FILE* f;
    IMFSinkWriter*& w;
    IMFMediaType*& t;
    IMFMediaType*& g;
    ~Done() {
      fclose(f);
      Free(w);
      Free(t);
      Free(g);
    }
  } done{src, writer, target, given};
  DeleteFileW(Wide(out).c_str());
  HRESULT hr = MFCreateSinkWriterFromURL(Wide(out).c_str(), nullptr, nullptr, &writer);
  CHECK(hr, "no writer");
  hr = MFCreateMediaType(&target);
  CHECK(hr, "no type");
  target->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
  target->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
  target->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
  target->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, kRate);
  target->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 1);
  target->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, bytes_per_second);  // 128 kbit/s for a call, as on the Mac
  DWORD stream = 0;
  hr = writer->AddStream(target, &stream);
  CHECK(hr, "AAC not available");
  hr = MFCreateMediaType(&given);
  CHECK(hr, "no type");
  given->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
  given->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
  given->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
  given->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, kRate);
  given->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 1);
  given->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 2);
  given->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, kRate * 2);
  given->SetUINT32(MF_MT_ALL_SAMPLES_INDEPENDENT, TRUE);
  hr = writer->SetInputMediaType(stream, given, nullptr);
  CHECK(hr, "the encoder won't take the sound");
  hr = writer->BeginWriting();
  CHECK(hr, "couldn't start writing");
  std::vector<uint8_t> buf(kRate * 2 / 10);  // a tenth of a second at a time
  LONGLONG at = 0;
  while (true) {
    size_t n = fread(buf.data(), 1, buf.size(), src);
    n -= n % 2;
    if (n == 0) break;
    IMFMediaBuffer* mb = nullptr;
    IMFSample* sample = nullptr;
    hr = MFCreateMemoryBuffer(static_cast<DWORD>(n), &mb);
    CHECK(hr, "no memory");
    BYTE* p = nullptr;
    mb->Lock(&p, nullptr, nullptr);
    memcpy(p, buf.data(), n);
    mb->Unlock();
    mb->SetCurrentLength(static_cast<DWORD>(n));
    hr = MFCreateSample(&sample);
    if (FAILED(hr)) {
      Free(mb);
      CHECK(hr, "no sample");
    }
    sample->AddBuffer(mb);
    const LONGLONG frames = static_cast<LONGLONG>(n / 2);
    sample->SetSampleTime(at * 10000000 / kRate);
    sample->SetSampleDuration(frames * 10000000 / kRate);
    hr = writer->WriteSample(stream, sample);
    Free(sample);
    Free(mb);
    CHECK(hr, "couldn't add sound");
    at += frames;
  }
  hr = writer->Finalize();
  CHECK(hr, "couldn't finish the file");
  return std::string();
}

const flutter::EncodableValue* Arg(const flutter::EncodableMap* args, const char* name) {
  if (!args) return nullptr;
  auto it = args->find(flutter::EncodableValue(name));
  return it == args->end() ? nullptr : &it->second;
}

std::string Str(const flutter::EncodableMap* args, const char* name) {
  const auto* v = Arg(args, name);
  const auto* s = v ? std::get_if<std::string>(v) : nullptr;
  return s ? *s : std::string();
}

bool Flag(const flutter::EncodableMap* args, const char* name) {
  const auto* v = Arg(args, name);
  const auto* b = v ? std::get_if<bool>(v) : nullptr;
  return b && *b;
}

}  // namespace

std::string EncodeAac(const std::string& in, const std::string& out, int bytes_per_second) {
  return Encode(in, out, bytes_per_second);
}

void CallRecorderMic(const float* samples, int frames, int rate) {
  if (g_started.load() == 0) return;
  std::shared_ptr<Track> mic;
  {
    std::lock_guard<std::mutex> lock(g_mutex);
    mic = g_mic;
  }
  if (!mic) return;
  const bool silent = g_muted.load();
  mic->Write(Due(), frames, rate, 1, [&](int i, int) { return silent ? 0.0f : samples[i]; });
}

void RegisterCallRecorder(flutter::BinaryMessenger* messenger) {
  MainThreadInit();
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(messenger, "ghost/recorder", &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler([](const flutter::MethodCall<flutter::EncodableValue>& call, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    const std::string& m = call.method_name();
    if (m == "start") {
      StopAll();
      auto mic = std::make_shared<Track>(Str(args, "mic"));
      {
        std::lock_guard<std::mutex> lock(g_mutex);
        g_muted.store(Flag(args, "muted"));
        g_mic = mic->ok() ? mic : nullptr;
        if (g_mic) g_started.store(NowMicros());
      }
      result->Success(flutter::EncodableValue(mic->ok()));
    } else if (m == "muted") {
      g_muted.store(Flag(args, "on"));
      result->Success(flutter::EncodableValue(true));
    } else if (m == "add") {
      result->Success(flutter::EncodableValue(Add(Str(args, "key"), Str(args, "track"), Str(args, "path"))));
    } else if (m == "remove") {
      Remove(Str(args, "key"));
      result->Success(flutter::EncodableValue(true));
    } else if (m == "stop") {
      result->Success(flutter::EncodableValue(StopAll()));
    } else if (m == "encode") {
      std::string in = Str(args, "in"), out = Str(args, "out");
      std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>> held(result.release());
      std::thread([in, out, held] {
        HRESULT co = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        HRESULT mf = MFStartup(MF_VERSION);
        std::string error = SUCCEEDED(mf) ? Encode(in, out) : std::string("Media Foundation isn't available");
        if (SUCCEEDED(mf)) MFShutdown();
        if (SUCCEEDED(co)) CoUninitialize();
        RunOnMain([held, error, out] {
          if (error.empty()) {
            held->Success(flutter::EncodableValue(out));
          } else {
            held->Error("encode", error);
          }
        });
      }).detach();
    } else {
      result->NotImplemented();
    }
  });
}
