package com.mattssoftware.glyph.capture

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
