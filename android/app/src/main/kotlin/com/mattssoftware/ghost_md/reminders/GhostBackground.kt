package com.mattssoftware.ghost_md.reminders

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.work.Data
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.mattssoftware.glyph.files.LibraryTree
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Done from outside the app's window (a reminder's notification, the Today widget), written through the app's own
 * library and its one save, never by this side writing the note's file:
 *
 * - **The app is running** (an engine with its reminders' channel: Reminders.live): it is told `tick`, and writes it
 *   (lib/root/phone_extras.dart), into the editor where that note is open on screen. Five seconds with no answer, or
 *   an engine that has no listener yet, and the second road is taken.
 * - **It is not**: a [BackgroundTick] job, which starts an engine of its own with no window on
 *   `lib/reminders/background_tick.dart`, opens the library there, writes the tick and lets the engine go. A job and
 *   not a service, which Android would refuse an app the person is not looking at.
 */
object GhostBackground {
  private const val TAG = "GhostBackground"

  fun tick(context: Context, note: String, line: Int, words: String) {
    val app = context.applicationContext
    val channel = Reminders.live
    if (channel == null) return later(app, note, line, words)
    val main = Handler(Looper.getMainLooper())
    val settled = AtomicBoolean(false)
    fun fallBack() {
      if (settled.compareAndSet(false, true)) later(app, note, line, words)
    }
    main.post {
      channel.invokeMethod(
        "tick",
        mapOf("note" to note, "line" to line, "words" to words),
        object : MethodChannel.Result {
          // True or false, the app has answered: false is a line ticked already, or gone, which the job would
          // find the same.
          override fun success(result: Any?) {
            settled.set(true)
          }

          override fun error(code: String, message: String?, details: Any?) = fallBack()

          override fun notImplemented() = fallBack()
        },
      )
    }
    main.postDelayed({ fallBack() }, 5_000)
  }

  private fun later(context: Context, note: String, line: Int, words: String) {
    val data = Data.Builder().putString("note", note).putInt("line", line).putString("words", words).build()
    WorkManager.getInstance(context).enqueue(OneTimeWorkRequestBuilder<BackgroundTick>().setInputData(data).addTag("ghost-tick").build())
  }
}

/** A tick written with the app closed: an engine of its own on `background_tick.dart`, for as long as it takes. */
class BackgroundTick(context: Context, params: WorkerParameters) : Worker(context, params) {
  override fun doWork(): Result {
    val app = applicationContext
    val note = inputData.getString("note") ?: return Result.success()
    val line = inputData.getInt("line", 0)
    val words = inputData.getString("words") ?: ""
    val data = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) app.dataDir.absolutePath else app.applicationInfo.dataDir
    val job = JSONObject().put("dataDir", data).put("cacheDir", app.cacheDir.absolutePath).put("note", note).put("line", line).put("words", words).toString()
    val finished = CountDownLatch(1)
    var engine: FlutterEngine? = null
    val main = Handler(Looper.getMainLooper())
    main.post {
      try {
        // The library may be in a folder chosen through Android's picker, which Rust reaches through this class.
        LibraryTree.install(app)
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(app)
        loader.ensureInitializationComplete(app, null)
        val made = FlutterEngine(app)
        engine = made
        MethodChannel(made.dartExecutor.binaryMessenger, "ghost_md/background").setMethodCallHandler { call, result ->
          if (call.method == "finished") {
            if (call.argument<Boolean>("ok") != true) Log.i(TAG, "nothing was ticked: ${call.argument<String>("why") ?: "the line is ticked already, or gone"}")
            result.success(null)
            finished.countDown()
          } else {
            result.notImplemented()
          }
        }
        made.dartExecutor.executeDartEntrypoint(
          DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "package:ghost_md/reminders/background_tick.dart", "ghostBackground"),
          listOf(job),
        )
      } catch (error: Throwable) {
        Log.w(TAG, "the tick could not start", error)
        finished.countDown()
      }
    }
    finished.await(90, TimeUnit.SECONDS)
    val let = CountDownLatch(1)
    main.post {
      engine?.destroy()
      let.countDown()
    }
    let.await(5, TimeUnit.SECONDS)
    return Result.success()
  }

  private companion object {
    const val TAG = "GhostBackground"
  }
}
