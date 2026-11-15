/* VoiceFx.kt's native half: voicefx (native/voicefx) over WebRTC's capture buffer, which is a direct ByteBuffer of
 * floats on the 16-bit scale (webrtc-sdk's ExternalAudioProcessingJni). */
#include <jni.h>
#include <stdint.h>

#include "voicefx.h"

#define FN(name) Java_com_infamousvague_ghostmessaging_VoiceFx_##name

JNIEXPORT jlong JNICALL FN(nativeCreate)(JNIEnv *env, jobject self) { return (jlong)(intptr_t)voicefx_create(); }

JNIEXPORT jint JNICALL FN(nativeModes)(JNIEnv *env, jobject self, jlong fx) { return voicefx_modes((VoiceFx *)(intptr_t)fx); }

JNIEXPORT void JNICALL FN(nativeConfigure)(JNIEnv *env, jobject self, jlong fx, jint mode, jfloat gain) {
  voicefx_configure((VoiceFx *)(intptr_t)fx, mode, gain);
}

JNIEXPORT void JNICALL FN(nativeProcess)(JNIEnv *env, jobject self, jlong fx, jobject buffer, jint frames, jint rate) {
  float *samples = (float *)(*env)->GetDirectBufferAddress(env, buffer);
  jlong bytes = (*env)->GetDirectBufferCapacity(env, buffer);
  if (!samples || bytes < (jlong)frames * (jlong)sizeof(float)) return;
  voicefx_process((VoiceFx *)(intptr_t)fx, samples, frames, rate);
}
