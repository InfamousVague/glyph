// Recording a call, on Windows (call_recorder.cpp).
#ifndef RUNNER_CALL_RECORDER_H_
#define RUNNER_CALL_RECORDER_H_

#include <flutter/binary_messenger.h>

// Answers lib/voice/recorder.dart on "ghost/recorder".
void RegisterCallRecorder(flutter::BinaryMessenger* messenger);

// One block of this device's own voice, cleaned, from voice_fx.cpp's capture hook on WebRTC's audio thread: floats
// on the 16-bit scale.
void CallRecorderMic(const float* samples, int frames, int rate);

// [in] (48 kHz mono 16-bit samples) as AAC in an .m4a at [out], at [bytes_per_second] (12000 to 24000): empty, or why
// it couldn't. Media Foundation must be started on the calling thread (a voice message, desk_sound.cpp).
std::string EncodeAac(const std::string& in, const std::string& out, int bytes_per_second);

#endif
