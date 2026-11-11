package com.mattssoftware.glyph.capture

import com.mattssoftware.glyph.capture.ForegroundTypes.MEDIA_PROCESSING
import com.mattssoftware.glyph.capture.ForegroundTypes.MEDIA_PROJECTION
import com.mattssoftware.glyph.capture.ForegroundTypes.MICROPHONE
import com.mattssoftware.glyph.capture.ForegroundTypes.SPECIAL_USE
import com.mattssoftware.glyph.capture.ForegroundTypes.UNTYPED
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The foreground types each build may pass (ForegroundTypes.kt), from what its manifest declares: the sideload APK's
 * (src/main) and Google Play's (src/play over it; docs/store/play/forms.md). An undeclared type throws on the phone,
 * so these pin that Play's never asks for specialUse or mediaProjection, and its worker never comes to the front.
 */
class ForegroundTypesTest {
  private val sideMeeting = MICROPHONE or MEDIA_PROJECTION or MEDIA_PROCESSING or SPECIAL_USE
  private val playMeeting = MICROPHONE
  private val playMeetingNov9 = MICROPHONE or MEDIA_PROCESSING
  private val sideWorker = MEDIA_PROCESSING or SPECIAL_USE
  private val playWorker = UNTYPED

  @Test
  fun recordingIsTheMicrophoneInBothBuilds() {
    for (sdk in listOf(30, 34, 35, 36)) {
      assertEquals(MICROPHONE, ForegroundTypes.recordingTypes(sdk, sideMeeting, projection = false))
      assertEquals(MICROPHONE, ForegroundTypes.recordingTypes(sdk, playMeeting, projection = false))
    }
    // Android 10 had no microphone type: the untyped call, as always.
    assertEquals(UNTYPED, ForegroundTypes.recordingTypes(29, playMeeting, projection = false))
  }

  @Test
  fun otherAppsSoundOnlyWhereMediaProjectionIsDeclared() {
    assertEquals(MICROPHONE or MEDIA_PROJECTION, ForegroundTypes.recordingTypes(34, sideMeeting, projection = true))
    assertEquals(MEDIA_PROJECTION, ForegroundTypes.recordingTypes(29, sideMeeting, projection = true))
    assertNull(ForegroundTypes.recordingTypes(28, sideMeeting, projection = true))
    for (sdk in listOf(29, 34, 35, 36)) assertNull(ForegroundTypes.recordingTypes(sdk, playMeeting, projection = true))
  }

  @Test
  fun theWriteUpIsMediaProcessingFrom15AndSpecialUseOn14OnlyInTheSideloadApk() {
    assertEquals(MEDIA_PROCESSING, ForegroundTypes.writeUpType(35, sideMeeting))
    assertEquals(SPECIAL_USE, ForegroundTypes.writeUpType(34, sideMeeting))
    assertEquals(UNTYPED, ForegroundTypes.writeUpType(33, sideMeeting))
    // Google Play's build declares the microphone alone since 2026-11-11: never a foreground write-up, on any
    // Android that reads types; the chain's ordinary work does it.
    for (sdk in listOf(29, 30, 33, 34, 35, 36)) assertNull("sdk $sdk", ForegroundTypes.writeUpType(sdk, playMeeting))
    // Below Android 10 types cannot be read: the untyped call, as always.
    assertEquals(UNTYPED, ForegroundTypes.writeUpType(28, UNTYPED))
    // The 2026-11-09 Play build (microphone and media processing) kept the foreground write-up from Android 15.
    assertEquals(MEDIA_PROCESSING, ForegroundTypes.writeUpType(36, playMeetingNov9))
  }

  @Test
  fun thePlayWorkerNeverComesToTheFront() {
    for (sdk in listOf(24, 28, 29, 33, 34, 35, 36)) assertNull("sdk $sdk", ForegroundTypes.workerType(sdk, playWorker, specialUseDeclared = false))
    assertNull(ForegroundTypes.workerType(35, null, specialUseDeclared = false))
  }

  @Test
  fun theSideloadWorkerIsAsItWas() {
    assertEquals(MEDIA_PROCESSING, ForegroundTypes.workerType(35, sideWorker, specialUseDeclared = true))
    assertEquals(SPECIAL_USE, ForegroundTypes.workerType(34, sideWorker, specialUseDeclared = true))
    for (sdk in listOf(24, 29, 33)) assertEquals(UNTYPED, ForegroundTypes.workerType(sdk, sideWorker, specialUseDeclared = true))
  }

  @Test
  fun theConstantsAreAndroids() {
    // android.content.pm.ServiceInfo's values, spelt out in ForegroundTypes for these tests.
    assertEquals(0x80, MICROPHONE)
    assertEquals(0x20, MEDIA_PROJECTION)
    assertEquals(0x40000000, SPECIAL_USE)
    assertEquals(0x2000, MEDIA_PROCESSING)
  }
}
