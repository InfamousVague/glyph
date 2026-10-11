package com.mattssoftware.ghost_md

import android.app.Activity
import android.util.Log
import com.mattssoftware.glyph.capture.MeetingService
import com.mattssoftware.glyph.recordings.RecordingJob
import com.mattssoftware.glyph.recordings.RecordingWorker
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The phone's half of starting over (lib/core/reset.dart `ResetNative`, reached through lib/core/reset_native.dart
 * on the channel that file names, `ghost.md/reset`). What the web app's reset asked of its activity
 * (`GlyphHost.cancelWriteUps`, `meetingState`), and the one thing that is new here.
 *
 * - `recording` -> whether the meeting service is recording now. A reset is refused while it is: the service has
 *   the microphone and a file growing under it.
 * - `cancelWriteUps` -> null, once every write-up has let go: the WorkManager chain cancelled, and the run under way
 *   (the service's or the worker's) told to stop and waited for, at most five seconds each (`RecordingJob.cancel`).
 *   Before the core removes their files, never after.
 * - `forgetSecrets` -> null: every value in the secure store gone (SecureStore.kt `clear`), the session and the
 *   account's keys and every plugin's sign-in alike. NEW: the web app kept those in the page's storage and in two
 *   files Rust removed; here they are sealed under the Keystore, where only this side can reach them all.
 *
 * The files themselves (the notes, recordings, pictures, films, write-ups and, when asked, the models) are the
 * core's `reset_local_data` (native/src/kept/reset.rs), which Dart asks after `cancelWriteUps` and before
 * `forgetSecrets`. Nothing here confirms: the page asks twice.
 */
class ResetChannel(private val activity: Activity, private val secrets: SecureStore) {
  /** Off the main thread: a cancel waits for a run to let go. */
  private val door: ExecutorService by lazy { Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "ghost-reset") } }

  fun register(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "recording" -> result.success(MeetingService.isRecording())
        "cancelWriteUps" -> {
          val context = activity.applicationContext
          val dataDir = activity.dataDir.absolutePath
          door.execute {
            try {
              RecordingWorker.cancelAll(context)
              for (id in listOfNotNull(MeetingService.writingUp, RecordingWorker.running).distinct()) {
                try {
                  RecordingJob.cancel(dataDir, id, "cancel")
                } catch (error: Throwable) {
                  Log.w(TAG, "cancelWriteUps failed for $id", error)
                }
              }
            } catch (error: Throwable) {
              // A queue that would not cancel does not stop a reset: its jobs find their files gone and end.
              Log.w(TAG, "cancelWriteUps failed", error)
            }
            activity.runOnUiThread { result.success(null) }
          }
        }
        "forgetSecrets" -> secrets.clear { gone ->
          if (gone) result.success(null) else result.error("secure_store", "A kept sign-in could not be forgotten.", null)
        }
        else -> result.notImplemented()
      }
    }
  }

  companion object {
    /** `resetChannelName` in lib/core/reset.dart: a dot where the app's other channels have an underscore. */
    const val CHANNEL = "ghost.md/reset"
    private const val TAG = "GhostReset"
  }
}
