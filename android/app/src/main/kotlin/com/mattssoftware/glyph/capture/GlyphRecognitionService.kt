package com.mattssoftware.glyph.capture

// PORTED from tauri/src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph/capture/GlyphRecognitionService.kt, line for line, for the
// Flutter app (docs/STAGES_5_6_8_9.md, stage 8). What differs: nothing in the code, but in the Flutter app this service is
// enabled in the manifest by a switch of the build's (res/values/voice_assistant.xml, `ghost_assistant`;
// android/app/build.gradle.kts says how), off unless the build or this phone's developer switch turns it on (AssistantSwitch.kt), where the Tauri app's has no switch.

import android.content.Intent
import android.os.RemoteException
import android.speech.RecognitionService
import android.speech.SpeechRecognizer

/**
 * A recognition service that recognises nothing, and exists only to be named.
 *
 * Android will not accept a voice interaction service as an assistant unless
 * its metadata names a recognition service too - `VoiceInteractionServiceInfo`
 * rejects it outright with "No recognitionService specified". Glyph does its
 * recognition with Whisper inside the app, and has no wish to be the speech
 * engine other apps call, so this answers every request with "busy" and nothing
 * else. It is not a placeholder for work to come.
 */
class GlyphRecognitionService : RecognitionService() {
  override fun onStartListening(recognizerIntent: Intent?, listener: Callback?) {
    try {
      listener?.error(SpeechRecognizer.ERROR_RECOGNIZER_BUSY)
    } catch (_: RemoteException) {
      // The caller has gone; there is no one left to tell.
    }
  }

  override fun onCancel(listener: Callback?) = Unit

  override fun onStopListening(listener: Callback?) = Unit
}
