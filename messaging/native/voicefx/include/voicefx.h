/*
 * voicefx: what Ghost Messaging does to the microphone before Opus (Matt, 2026-11-15: "build in like krisp noise
 * supression or other fancy noise suppression tools, add a volume slider for input and output volume with
 * overboosting"; RNNoise + DeepFilterNet chosen).
 *
 * The same C for every platform, called from flutter_webrtc's capture post-processing hook: android VoiceFx.kt (JNI),
 * macos VoiceFx.swift, and the patched flutter_webrtc on Windows. One 10 ms block at a time, mono, in place, as
 * WebRTC holds it: floats on the 16-bit scale (-32768 to 32767), at the rate WebRTC processes at (usually 48 kHz).
 *
 *   - Noise: RNNoise (Xiph, BSD; native/voicefx/rnnoise) or DeepFilterNet (where built with VOICEFX_DEEPFILTER and
 *     given its model), else none.
 *   - Gain: 0 to 2 (200%); over 1 the loudest parts are rounded off rather than clipped (a soft limiter).
 */
#ifndef VOICEFX_H
#define VOICEFX_H

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

#ifdef __cplusplus
}
#endif

#endif
