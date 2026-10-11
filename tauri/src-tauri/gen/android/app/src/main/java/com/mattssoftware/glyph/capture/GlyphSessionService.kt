package com.mattssoftware.glyph.capture

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.service.voice.VoiceInteractionSession
import android.service.voice.VoiceInteractionSessionService
import android.util.Log
import com.mattssoftware.glyph.MainActivity

/** Hands the system a session each time the assistant is invoked. */
class GlyphSessionService : VoiceInteractionSessionService() {
  override fun onNewSession(args: Bundle?): VoiceInteractionSession = GlyphSession(this)
}

/**
 * One press of the side key: open Glyph straight into recording, then get out
 * of the way.
 *
 * An assistant session normally draws its own overlay - that is what Gemini's
 * sheet is. Glyph deliberately does not. The live note has to render as
 * markdown while Matt talks, and the only thing in this app that renders
 * markdown is the editor in the webview; a native overlay would need a second
 * markdown renderer that drifts from the first. So the session launches the
 * main activity with a capture action and hides itself immediately, and the
 * overlay window the system created for it is never shown.
 *
 * `startActivity` rather than `startAssistantActivity`, and the difference is
 * load-bearing. `startAssistantActivity` launches with the ASSISTANT activity
 * type, which places the activity in a separate assistant task; the main
 * activity is `singleTask` and hosts the only Tauri runtime in the process, so
 * a second instance in a second task would try to start a second runtime. A
 * plain launch reuses the existing task (arriving as `onNewIntent` when Glyph is
 * already open). Launching from here is permitted without the app being in the
 * foreground because Android exempts a system-bound voice interaction service
 * from the background activity start restrictions.
 *
 * The OS already buzzes when the side key is held (`PhoneWindowManager` fires
 * the assistant-button haptic before invoking us), so nothing here or on the
 * page adds a second tap on open.
 */
class GlyphSession(context: Context) : VoiceInteractionSession(context) {
  override fun onShow(args: Bundle?, showFlags: Int) {
    super.onShow(args, showFlags)
    val intent = Intent(context, MainActivity::class.java).apply {
      action = MainActivity.ACTION_CAPTURE
      // The system tells us how we were invoked; the page records it so a note
      // can say it came from the side key.
      putExtra(MainActivity.EXTRA_SOURCE, args?.getInt("invocation_type", -1) ?: -1)
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    try {
      context.startActivity(intent)
    } catch (error: RuntimeException) {
      // Logged rather than surfaced: a session has no UI to surface it in, and
      // the failure is only diagnosable from logcat anyway.
      Log.e("GlyphCapture", "could not open the capture screen", error)
    }
    hide()
  }
}
