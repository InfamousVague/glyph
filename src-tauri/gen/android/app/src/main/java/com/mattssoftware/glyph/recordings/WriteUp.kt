package com.mattssoftware.glyph.recordings

import android.content.Context
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ProcessLifecycleOwner
import com.mattssoftware.glyph.MainActivity
import org.json.JSONObject
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/** What one call of `RecordingJob.run` came back with (src-tauri/src/write_up.rs `Answer`). */
internal sealed class Outcome {
  data class Done(val title: String?, val line: String?, val summary: Boolean) : Outcome()
  object AlreadyDone : Outcome()
  data class Retry(val reason: String) : Outcome()
  data class NeedsModel(val again: Boolean) : Outcome()
  data class Failed(val again: Boolean) : Outcome()
  object Cancelled : Outcome()
  object Gone : Outcome()
}

/**
 * One run of a meeting's write-up, the way the service runs it after Stop and
 * the worker runs it as the retry path: the phone's readings gathered into the
 * options Rust decides the battery rule from, `RecordingJob.run` blocking on
 * the caller's thread, and a watcher beside it that reads `jobs/<id>.progress`
 * every two seconds for the notification's line and polls the phone's heat
 * every thirty, cancelling the run with "thermal" once it is severe. Rust obeys
 * within one graph computation and answers a retry the chain picks up later.
 *
 * `settle` is the other half of the contract's table: what is posted and what
 * the page is told for each outcome. Nothing is posted for an outcome that was
 * already said (`again`), for a run that found the job done, or for one that
 * was cancelled or found nothing to do.
 */
internal object WriteUp {
  private const val TAG = "GlyphRecordings"
  private const val PROGRESS_EVERY_MS = 2_000L
  private const val THERMAL_EVERY_MS = 30_000L

  /** The phases of a `.progress` file that the sweep leaves alone. */
  val TERMINAL_PHASES = setOf("done", "needsModel", "failed", "cancelled")

  /**
   * Runs the job once. `progress`, when given, is told the notification's new
   * line each time it changes.
   */
  fun runOnce(context: Context, noteId: String, title: String?, now: Boolean, fresh: Boolean, progress: ((String) -> Unit)?): Outcome {
    val dataDir = context.dataDir.absolutePath
    val ended = AtomicBoolean(false)
    val watcher = Thread({
      var lastLine: String? = null
      var lastThermal = SystemClock.elapsedRealtime()
      var cooled = true
      while (!ended.get()) {
        try {
          Thread.sleep(PROGRESS_EVERY_MS)
        } catch (_: InterruptedException) {
          return@Thread
        }
        if (ended.get()) return@Thread
        if (progress != null) {
          val state = readProgress(context, noteId)
          val line = RecordingAlerts.progressLine(state?.optString("phase"), state?.optInt("percent", 0) ?: 0)
          if (line != lastLine) {
            lastLine = line
            progress(line)
          }
        }
        val at = SystemClock.elapsedRealtime()
        if (at - lastThermal >= THERMAL_EVERY_MS) {
          lastThermal = at
          if (cooled && thermalSevere(context)) {
            cooled = false
            try {
              RecordingJob.cancel(dataDir, noteId, "thermal")
            } catch (error: Throwable) {
              Log.w(TAG, "thermal cancel failed", error)
            }
          }
        }
      }
    }, "glyph-write-up-watch")
    watcher.isDaemon = true
    watcher.start()
    val answer = try {
      RecordingJob.run(dataDir, noteId, options(context, now, fresh, title))
    } catch (error: Throwable) {
      Log.w(TAG, "write-up threw", error)
      JSONObject().put("error", error.toString()).toString()
    } finally {
      ended.set(true)
      watcher.interrupt()
    }
    return outcomeOf(answer)
  }

  /** The options `run` takes (the contract's 2.3), from what only Kotlin can read. */
  fun options(context: Context, now: Boolean, fresh: Boolean, title: String?): String {
    val battery = context.getSystemService(BatteryManager::class.java)
    val percent = battery?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 100
    return JSONObject()
      .put("now", now)
      .put("fresh", fresh)
      .put("title", title ?: JSONObject.NULL)
      .put("charging", battery?.isCharging ?: false)
      // A reading outside 0..100 is "unknown" (the emulator, a phone with no battery): treated as full, so the rule holds nothing back on a guess.
      .put("batteryPercent", if (percent in 0..100) percent else 100)
      .put("thermal", thermalWord(context))
      .put("appInFront", ProcessLifecycleOwner.get().lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED))
      .toString()
  }

  /** `PowerManager.currentThermalStatus` as the word Rust reads; "none" before Android 10, which has no reading. */
  fun thermalWord(context: Context): String {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "none"
    val power = context.getSystemService(PowerManager::class.java) ?: return "none"
    return when (power.currentThermalStatus) {
      PowerManager.THERMAL_STATUS_LIGHT -> "light"
      PowerManager.THERMAL_STATUS_MODERATE -> "moderate"
      PowerManager.THERMAL_STATUS_SEVERE -> "severe"
      PowerManager.THERMAL_STATUS_CRITICAL -> "critical"
      PowerManager.THERMAL_STATUS_EMERGENCY -> "emergency"
      PowerManager.THERMAL_STATUS_SHUTDOWN -> "shutdown"
      else -> "none"
    }
  }

  fun thermalSevere(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
    val power = context.getSystemService(PowerManager::class.java) ?: return false
    return power.currentThermalStatus >= PowerManager.THERMAL_STATUS_SEVERE
  }

  /** `jobs/<id>.progress` as Rust wrote it, or null when there is none or it cannot be read. Kotlin only ever reads here. */
  fun readProgress(context: Context, noteId: String): JSONObject? {
    val file = File(RecordingWorker.jobsDir(context), "$noteId.progress")
    if (!file.isFile) return null
    return try {
      JSONObject(file.readText())
    } catch (error: Exception) {
      null
    }
  }

  /**
   * The contract's table for a finished run: the written-up notification and
   * `window.__glyph.recordingDone` for an outcome said for the first time, the
   * charging sweep for a job the battery rule held, nothing for the rest.
   */
  fun settle(context: Context, noteId: String, title: String?, outcome: Outcome) {
    val name = title ?: readProgress(context, noteId)?.optString("title")?.takeIf { it.isNotEmpty() } ?: "Meeting"
    when (outcome) {
      is Outcome.Done -> {
        val text = outcome.line?.takeIf { it.isNotBlank() } ?: "The transcript is in the note."
        RecordingAlerts.postWrittenUp(context, noteId, outcome.title ?: name, text)
        tellPage(noteId, "done")
      }
      is Outcome.NeedsModel -> if (!outcome.again) {
        RecordingAlerts.postWrittenUp(context, noteId, name, "Needs the language model to write up the meeting.")
        tellPage(noteId, "needsModel")
      }
      is Outcome.Failed -> if (!outcome.again) {
        RecordingAlerts.postWrittenUp(context, noteId, name, "The meeting could not be written up.")
        tellPage(noteId, "failed")
      }
      is Outcome.Cancelled, is Outcome.Gone -> tellPage(noteId, "cancelled")
      is Outcome.Retry -> if (outcome.reason == "battery") RecordingWorker.enqueueWhenCharging(context)
      is Outcome.AlreadyDone -> Unit
    }
  }

  private fun tellPage(noteId: String, outcome: String) {
    MainActivity.tell("recordingDone", JSONObject().put("id", noteId).put("outcome", outcome).toString())
  }

  private fun outcomeOf(answer: String?): Outcome {
    val json = try {
      JSONObject(answer ?: return Outcome.Retry("no answer"))
    } catch (error: Exception) {
      return Outcome.Retry("unreadable answer")
    }
    return when {
      json.optBoolean("done") -> Outcome.Done(
        json.optString("title").takeIf { !json.isNull("title") && it.isNotEmpty() },
        json.optString("line").takeIf { !json.isNull("line") && it.isNotEmpty() },
        json.optBoolean("summary", false),
      )
      json.optBoolean("alreadyDone") -> Outcome.AlreadyDone
      json.has("retry") -> Outcome.Retry(json.optString("retry", "retry"))
      json.has("needsModel") -> Outcome.NeedsModel(json.optBoolean("again", false))
      json.has("error") -> {
        Log.w(TAG, "write-up failed: ${json.optString("error")}")
        Outcome.Failed(json.optBoolean("again", false))
      }
      json.optBoolean("cancelled") -> Outcome.Cancelled
      json.optBoolean("gone") -> Outcome.Gone
      else -> Outcome.Retry("unknown answer")
    }
  }
}
