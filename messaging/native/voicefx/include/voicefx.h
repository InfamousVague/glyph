/*
 * voicefx: what Ghost Messaging does to the microphone before Opus (Matt, 2026-11-15: "build in like krisp noise
 * supression or other fancy noise suppression tools, add a volume slider for input and output volume with
 * overboosting"; RNNoise + DeepFilterNet chosen).
 *
 * The same C for every platform, called from flutter_webrtc's capture post-processing hook: android VoiceFx.kt (JNI),
 * macos VoiceFx.swift, and the patched flutter_webrtc on Windows. One 10 ms block at a time, mono, in place, as
 * WebRTC holds it: floats on the 16-bit scale (-32768 to 32767), at the rate WebRTC processes at (usually 48 kHz).
 *
 *   - Noise: RNNoise (Xiph, BSD; native/voicefx/rnnoise) or DeepFilterNet (where built with VOICEFX_WITH_DEEPFILTER and
 *     given its model), else none.
 *   - Gain: 0 to 2 (200%); over 1 the loudest parts are rounded off rather than clipped (a soft limiter).
 */
#ifndef VOICEFX_H
#define VOICEFX_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define VOICEFX_EXPORT __declspec(dllexport)
#else
#define VOICEFX_EXPORT __attribute__((visibility("default")))
#endif

typedef struct VoiceFx VoiceFx;

enum { VOICEFX_OFF = 0, VOICEFX_RNNOISE = 1, VOICEFX_DEEPFILTER = 2 };

VOICEFX_EXPORT VoiceFx *voicefx_create(void);
VOICEFX_EXPORT void voicefx_destroy(VoiceFx *fx);

/* What this build can run, as bits: 1 << VOICEFX_RNNOISE, 1 << VOICEFX_DEEPFILTER (once its model is given). */
VOICEFX_EXPORT int voicefx_modes(VoiceFx *fx);

/* DeepFilterNet's model (DeepFilterNet3_onnx.tar.gz); 1 if it loaded. A build without it answers 0. */
VOICEFX_EXPORT int voicefx_deepfilter_model(VoiceFx *fx, const char *path);

/* Safe from any thread while voicefx_process runs on WebRTC's: the next block uses them. */
VOICEFX_EXPORT void voicefx_configure(VoiceFx *fx, int mode, float gain);

/* One block of [frames] samples at [rate] Hz, in place. */
VOICEFX_EXPORT void voicefx_process(VoiceFx *fx, float *samples, int frames, int rate);

/* Live voice changing in a call (Matt, 2026-11-20: "I'd like the voice changer to work in spaces calls in real time";
 * ElevenLabs chosen over effects on the device, with its delay). While [on], what the microphone says (after the
 * noise suppression and the gain) is kept for the app to take, and what goes into the call is only what the app feeds
 * back: the changed voice, or silence until some comes. */
VOICEFX_EXPORT void voicefx_live(VoiceFx *fx, int on);

/* What was said since last asked, at 16 kHz, 16-bit, mono: up to [most] samples into [out]; how many. */
VOICEFX_EXPORT int voicefx_take(VoiceFx *fx, int16_t *out, int most);

/* The changed voice to play into the call: [n] samples of 16-bit mono at [rate] Hz, after whatever is queued. */
VOICEFX_EXPORT void voicefx_feed(VoiceFx *fx, const int16_t *pcm, int n, int rate);

/* How much of the changed voice is still to be played, in milliseconds. */
VOICEFX_EXPORT int voicefx_queued_ms(VoiceFx *fx);

#ifdef __cplusplus
}
#endif

#endif
