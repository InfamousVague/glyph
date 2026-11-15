// What is done to the microphone before Opus, on Windows (lib/voice/voice_fx.dart; Matt, 2026-11-15: "build in like
// krisp noise supression or other fancy noise suppression tools, add a volume slider for input ... with
// overboosting"): RNNoise, DeepFilterNet where the build made it, and the gain, from native/voicefx, set as
// the capture post-processing of flutter_webrtc's own WebRTC. flutter_webrtc's DLL hands out its instance
// (FlutterWebRTCPluginSharedInstance), and its audio_processing() is libwebrtc's RTCAudioProcessing, whose
// CustomProcessing gets each 10 ms block: floats on the 16-bit scale, as on Android and the Mac.
#include "voice_fx.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>
#include <string>
#include <thread>

#include "flutter_webrtc.h"
#include "flutter_webrtc/flutter_web_r_t_c_plugin.h"
#include "rtc_audio_processing.h"

extern "C" {
#include "voicefx.h"
}

namespace {

class Processor : public libwebrtc::RTCAudioProcessing::CustomProcessing {
 public:
  Processor() : fx_(voicefx_create()) {}

  void Initialize(int sample_rate_hz, int num_channels) override {}

  void Process(int num_bands, int num_frames, int buffer_size, float* buffer) override {
    voicefx_process(fx_, buffer, num_frames, num_frames * 100);
  }

  void Reset(int new_rate) override {}

  void Release() override {}

  VoiceFx* fx() { return fx_; }

 private:
  VoiceFx* fx_;
};

Processor* g_processor = nullptr;
bool g_attached = false;
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;

bool Attach() {
  if (g_attached) return true;
  auto* webrtc = FlutterWebRTCPluginSharedInstance();
  if (!webrtc) return false;
  flutter_webrtc_plugin::FlutterWebRTCBase* base = webrtc;
  auto processing = base->audio_processing();
  if (!processing) return false;
  processing->SetCapturePostProcessing(g_processor);
  g_attached = true;
  return true;
}

}  // namespace

void RegisterVoiceFx(flutter::BinaryMessenger* messenger) {
  if (!g_processor) {
    g_processor = new Processor();
    // DeepFilterNet, where this build has it: its model is built in, made ready once, off this thread. A build
    // without it answers 0 and offers RNNoise alone.
    std::thread([fx = g_processor->fx()] { voicefx_deepfilter_model(fx, ""); }).detach();
  }
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(messenger, "ghost/voicefx", &flutter::StandardMethodCodec::GetInstance());
  g_channel->SetMethodCallHandler([](const flutter::MethodCall<flutter::EncodableValue>& call, std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() == "modes") {
      int bits = voicefx_modes(g_processor->fx());
      flutter::EncodableList modes;
      if (bits & (1 << VOICEFX_RNNOISE)) modes.push_back(flutter::EncodableValue("rnnoise"));
      if (bits & (1 << VOICEFX_DEEPFILTER)) modes.push_back(flutter::EncodableValue("deepfilter"));
      result->Success(flutter::EncodableValue(modes));
      return;
    }
    if (call.method_name() == "configure") {
      int mode = VOICEFX_OFF;
      double gain = 1.0;
      if (const auto* args = std::get_if<flutter::EncodableMap>(call.arguments())) {
        auto m = args->find(flutter::EncodableValue("mode"));
        if (m != args->end()) {
          if (const auto* name = std::get_if<std::string>(&m->second)) mode = *name == "rnnoise" ? VOICEFX_RNNOISE : *name == "deepfilter" ? VOICEFX_DEEPFILTER : VOICEFX_OFF;
        }
        auto g = args->find(flutter::EncodableValue("gain"));
        if (g != args->end()) {
          if (const auto* v = std::get_if<double>(&g->second)) gain = *v;
        }
      }
      voicefx_configure(g_processor->fx(), mode, static_cast<float>(gain));
      result->Success(flutter::EncodableValue(Attach()));
      return;
    }
    result->NotImplemented();
  });
}
