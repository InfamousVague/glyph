package com.mattssoftware.glyph.recordings

import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.Operation
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.mattssoftware.glyph.capture.MeetingService
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * The retry path for a meeting's write-up. The service that recorded the
 * meeting writes it up itself (capture/MeetingService.kt); this worker is for
 * everything that path could not finish: the process killed mid-way, a phone
 * too hot or too low, a write-up refused because a dictation had the cores, a
 * meeting left unfinished at launch, "Write up now" from the shelf.
 *
 * One chain, `glyph-write-ups`, under APPEND_OR_REPLACE, so write-ups queue and
 * never run two at once; each request is tagged with its note id so the sweep
 * can tell what is already waiting. A second unique work,
 * `glyph-write-ups-charging`, sweeps every unfinished job into the chain when
 * the charger connects: that is how a job the battery rule held is retried,
 * with no polling. Nothing here cancels one member of the chain through
 * WorkManager, because cancelling a chain member cancels everything appended
 * after it; a single write-up is cancelled through `RecordingJob.cancel`, and
 * the worker that later reaches that id finds the job cancelled and answers
 * success. Only Reset cancels the unique works whole.
 *
 * `Result.retry()` only for a partial; every terminal outcome is
 * `Result.success()`, so a job that failed for good does not back off forever.
 */
class RecordingWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
  override fun doWork(): Result {
    val context = applicationContext
    if (inputData.getBoolean(KEY_SWEEP, false)) {
      sweep(context)
      return Result.success()
    }
    val noteId = inputData.getString(KEY_NOTE_ID) ?: return Result.success()
    val fresh = inputData.getBoolean(KEY_FRESH, false)
    // When a fresh request was made, so a cancel made after it (the trash) wins over it on every retry.
    val requestedAt = inputData.getLong(KEY_REQUESTED_AT, 0L).takeIf { fresh && it > 0L }
    val now = inputData.getBoolean(KEY_NOW, false)
    if (MeetingService.isRecording() || MeetingService.writingUp == noteId) return Result.retry()
    val progress = WriteUp.readProgress(context, noteId)
    // No progress file and nothing fresh asked for: the page took the result, or the service's own run finished
    // before this request's turn came. There is nothing to write up, and running would write it up twice.
    if (progress == null && !fresh) return Result.success()
    if (progress?.optString("phase") == "done") return Result.success()
    val title = inputData.getString(KEY_TITLE) ?: progress?.optString("title")?.takeIf { it.isNotEmpty() }

    // Foreground when Android allows it (from the background on Android 12+ it does not, and the call throws:
    // then the job runs without, resumable by span, and a ten-minute stop loses at most the span in hand).
    val foregrounded = try {
      setForegroundAsync(foregroundInfo(context, title, RecordingAlerts.progressLine(progress?.optString("phase"), 0))).get()
      true
    } catch (error: Exception) {
      Log.i(TAG, "write-up runs without a foreground notification: $error")
      false
    }
    running = noteId
    val outcome = try {
      WriteUp.runOnce(context, noteId, title, now, fresh, requestedAt, if (foregrounded) { line -> setForegroundAsync(foregroundInfo(context, title, line)) } else null)
    } finally {
      running = null
    }
    WriteUp.settle(context, noteId, title, outcome)
    return if (outcome is Outcome.Retry && outcome.reason != "battery") Result.retry() else Result.success()
  }

  /**
   * WorkManager stopping this worker (Reset's cancel, or the ten-minute limit
   * on work with no foreground): the run in hand is asked to let go as a
   * timeout, which leaves the job resumable, since what stopped it was not a
   * decision about the job.
   */
  override fun onStopped() {
    val noteId = running ?: return
    val dataDir = applicationContext.dataDir.absolutePath
    Thread({
      try {
        RecordingJob.cancel(dataDir, noteId, "timeout")
      } catch (error: Throwable) {
        Log.w(TAG, "could not stop the write-up", error)
      }
    }, "glyph-write-up-stop").start()
  }

  private fun foregroundInfo(context: Context, title: String?, line: String): ForegroundInfo {
    val notification = RecordingAlerts.writeUp(context, title, line)
    return when {
      Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM ->
        ForegroundInfo(RecordingAlerts.WORKER_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING)
      Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
        ForegroundInfo(RecordingAlerts.WORKER_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
      else -> ForegroundInfo(RecordingAlerts.WORKER_ID, notification)
    }
  }

  companion object {
    private const val TAG = "GlyphRecordings"
    const val CHAIN = "glyph-write-ups"
    const val CHARGING = "glyph-write-ups-charging"
    private const val KEY_NOTE_ID = "noteId"
    private const val KEY_TITLE = "title"
    private const val KEY_NOW = "now"
    private const val KEY_FRESH = "fresh"
    private const val KEY_SWEEP = "sweep"
    private const val KEY_REQUESTED_AT = "requestedAt"

    /** The note id a worker is running `RecordingJob.run` for right now, for Reset's cancel. */
    @Volatile var running: String? = null
      private set

    /** Where Rust keeps a write-up's progress and result: `JOBS` in src-tauri/src/paths.rs. Rename both together. */
    fun jobsDir(context: Context): File = File(context.dataDir, "jobs")

    private fun tag(noteId: String) = "glyph-write-up:$noteId"

    /**
     * One request for `noteId` at the end of the chain. `fresh` restarts a cancelled, failed or model-less job; `now`
     * skips the battery rule. The answer is WorkManager's operation, for a caller that must know the request is
     * written down before the process may die (`MeetingService.finishRecording`).
     *
     * A fresh request carries when it was made, and Rust honours it over a `cancelled` file only when the cancel is
     * older: the request is retried with the same input after every hold, and a meeting put in the trash while it
     * waited must stay cancelled rather than be written up by the retry.
     */
    fun enqueue(context: Context, noteId: String, title: String?, now: Boolean, fresh: Boolean): Operation {
      val data = Data.Builder()
        .putString(KEY_NOTE_ID, noteId)
        .putString(KEY_TITLE, title)
        .putBoolean(KEY_NOW, now)
        .putBoolean(KEY_FRESH, fresh)
        .putLong(KEY_REQUESTED_AT, System.currentTimeMillis())
        .build()
      val request = OneTimeWorkRequestBuilder<RecordingWorker>()
        .setInputData(data)
        .addTag(tag(noteId))
        .setBackoffCriteria(BackoffPolicy.LINEAR, 2, TimeUnit.MINUTES)
        .build()
      return WorkManager.getInstance(context).enqueueUniqueWork(CHAIN, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
    }

    /** The sweep that runs when the charger connects: every unfinished job back into the chain. KEEP: one is enough. */
    fun enqueueWhenCharging(context: Context) {
      val request = OneTimeWorkRequestBuilder<RecordingWorker>()
        .setInputData(Data.Builder().putBoolean(KEY_SWEEP, true).build())
        .setConstraints(Constraints.Builder().setRequiresCharging(true).build())
        .build()
      WorkManager.getInstance(context).enqueueUniqueWork(CHARGING, ExistingWorkPolicy.KEEP, request)
    }

    /** Reset: both unique works, whole. */
    fun cancelAll(context: Context) {
      val work = WorkManager.getInstance(context)
      work.cancelUniqueWork(CHAIN)
      work.cancelUniqueWork(CHARGING)
    }

    /** Whether a request for `noteId` is already waiting in the chain or running. Blocks briefly; never on the main thread. */
    fun isQueued(context: Context, noteId: String): Boolean = try {
      WorkManager.getInstance(context).getWorkInfosByTag(tag(noteId)).get().any {
        it.state == WorkInfo.State.ENQUEUED || it.state == WorkInfo.State.RUNNING || it.state == WorkInfo.State.BLOCKED
      }
    } catch (error: Exception) {
      Log.w(TAG, "could not read the chain", error)
      false
    }

    /**
     * Every `<id>.progress` in the jobs folder that is not finished, into the chain, skipping the
     * ids already there. Called at launch (MeetingService.recover) and by the
     * charging sweep. Only the phase and the title are read; Rust owns the file.
     */
    fun sweep(context: Context) {
      val files = jobsDir(context).listFiles { file -> file.isFile && file.name.endsWith(".progress") } ?: return
      for (file in files) {
        val noteId = file.name.removeSuffix(".progress")
        val progress = WriteUp.readProgress(context, noteId) ?: continue
        if (progress.optString("phase") in WriteUp.TERMINAL_PHASES) continue
        if (isQueued(context, noteId)) continue
        enqueue(context, noteId, progress.optString("title").takeIf { it.isNotEmpty() }, now = false, fresh = false)
      }
    }
  }
}
