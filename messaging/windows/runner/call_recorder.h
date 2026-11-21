// Recording a call, on Windows (call_recorder.cpp).
#ifndef RUNNER_CALL_RECORDER_H_
#define RUNNER_CALL_RECORDER_H_

#include <flutter/binary_messenger.h>

// Answers lib/voice/recorder.dart on "ghost/recorder".
void RegisterCallRecorder(flutter::BinaryMessenger* messenger);

// One block of this device's own voice, cleaned, from voice_fx.cpp's capture hook on WebRTC's audio thread: floats
// on the 16-bit scale.
void CallRecorderMic(const float* samples, int frames, int rate);

#endif
