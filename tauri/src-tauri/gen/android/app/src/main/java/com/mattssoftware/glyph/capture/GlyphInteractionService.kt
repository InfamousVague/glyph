package com.mattssoftware.glyph.capture

import android.os.Bundle
import android.service.voice.VoiceInteractionService
import android.service.voice.VoiceInteractionSession

/**
 * What makes Glyph eligible to be the phone's digital assistant, and so what a
 * press-and-hold of the Fold's side key reaches.
 *
 * Android offers two ways to qualify for the assistant role: this service, or
 * an activity that answers `ACTION_ASSIST`. Glyph has both, and this is the one
 * that matters. The activity route alone does not reliably appear in Samsung's
 * side-key assistant list, and it cannot be reached from the lock screen - the
 * system only launches an assistant over the keyguard when a voice interaction
 * service says it supports that (see `supportsLaunchVoiceAssistFromKeyguard` in
 * `res/xml/glyph_voice_interaction.xml`). Verified against the device before
 * this was written: the Fold already lists third-party assistant apps as
 * eligible, and they qualify by exactly this kind of service.
 *
 * The service does nothing on its own. The system keeps the chosen assistant's
 * service bound for as long as it holds the role, which has a useful side
 * effect worth knowing about: Glyph's process stays alive, so a press starts
 * the capture screen in a warm process rather than a cold one. All of the
 * actual work happens in `GlyphSession`.
 */
class GlyphInteractionService : VoiceInteractionService() {
  /**
   * The press arrived while the phone was locked. Without this override the
   * system would ask the user to unlock first, which defeats a note started on
   * a whim - the whole point of the button.
   */
  override fun onLaunchVoiceAssistFromKeyguard() {
    showSession(Bundle(), VoiceInteractionSession.SHOW_SOURCE_ASSIST_GESTURE)
  }
}
