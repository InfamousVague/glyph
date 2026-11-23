/* VoiceFx.kt's native half: voicefx (native/voicefx) over WebRTC's capture buffer, which is a direct ByteBuffer of
 * floats on the 16-bit scale (webrtc-sdk's ExternalAudioProcessingJni). */
#include <jni.h>
#include <stdint.h>
#include <stdlib.h>

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

/* The voice effect by its name (voicefx_effect_id); none for null or a name that is no effect's. */
JNIEXPORT void JNICALL FN(nativeEffect)(JNIEnv *env, jobject self, jlong fx, jstring name) {
  const char *n = name ? (*env)->GetStringUTFChars(env, name, NULL) : NULL;
  voicefx_effect((VoiceFx *)(intptr_t)fx, voicefx_effect_id(n));
  if (n) (*env)->ReleaseStringUTFChars(env, name, n);
}
JNIEXPORT void JNICALL FN(nativeLive)(JNIEnv *env, jobject self, jlong fx, jboolean on) { voicefx_live((VoiceFx *)(intptr_t)fx, on ? 1 : 0); }

/* What was said since last asked: 16-bit little-endian samples at 16 kHz, as bytes. */
JNIEXPORT jbyteArray JNICALL FN(nativeTake)(JNIEnv *env, jobject self, jlong fx, jint most) {
  if (most <= 0) most = 1;
  int16_t *buf = malloc(sizeof(int16_t) * (size_t)most);
  int n = buf ? voicefx_take((VoiceFx *)(intptr_t)fx, buf, most) : 0;
  jbyteArray out = (*env)->NewByteArray(env, n * 2);
  if (out && n > 0) (*env)->SetByteArrayRegion(env, out, 0, n * 2, (const jbyte *)buf);
  free(buf);
  return out;
}

/* The changed voice to play into the call: 16-bit little-endian samples at [rate], as bytes. Read, never written
 * back (JNI_ABORT). */
JNIEXPORT void JNICALL FN(nativeFeed)(JNIEnv *env, jobject self, jlong fx, jbyteArray pcm, jint rate) {
  jsize bytes = (*env)->GetArrayLength(env, pcm);
  if (bytes < 2) return;
  jbyte *data = (*env)->GetByteArrayElements(env, pcm, NULL);
  if (!data) return;
  voicefx_feed((VoiceFx *)(intptr_t)fx, (const int16_t *)data, bytes / 2, rate);
  (*env)->ReleaseByteArrayElements(env, pcm, data, JNI_ABORT);
}

JNIEXPORT jint JNICALL FN(nativeQueued)(JNIEnv *env, jobject self, jlong fx) { return voicefx_queued_ms((VoiceFx *)(intptr_t)fx); }
