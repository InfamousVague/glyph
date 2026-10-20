package com.mattssoftware.ghost_md.wear

import android.Manifest
import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import com.mattssoftware.ghost_md.watchlink.WatchLink
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.util.UUID

/** What the microphone is doing, for the screen. */
data class Recording(
    /** The take being recorded, or null when nothing is. */
    val id: String? = null,
    /** `SystemClock.elapsedRealtime()` at its start, for the clock on the screen. */
    val startedAt: Long = 0,
    /** How loud the last read was, 0 to 1 (Levels.of). */
    val level: Float = 0f,
    /** Why the last take could not start, in a person's words; null when it did. */
    val problem: String? = null,
)

/**
 * The one microphone the watch app holds (docs/WATCH.md): a foreground service of type `microphone`, started from the
 * screen while it is in front (the only moment Android lets that type start), so a take keeps going when the wrist
 * drops and the screen goes off. It reads 16 kHz mono PCM16 with `AudioRecord` and writes the WAV as it goes
 * (WavWriter), holds a partial wake lock for the take and no longer, and shows itself as an ongoing activity, so the
 * watch face carries a chip back to it.
 *
 * NO ALWAYS-ON MICROPHONE. It opens at [ACTION_START], which only the screen sends, and only after a tap (the button,
 * the tile, the complication or the shortcut, each of which opens the screen); it closes at [ACTION_STOP], at the
 * notification's Stop, at [WatchLink.MAX_TAKE_MS], or when a read fails. Nothing listens between takes.
 */
class RecordService : Service() {
    companion object {
        const val ACTION_START = "com.mattssoftware.ghost_md.wear.START"
        const val ACTION_STOP = "com.mattssoftware.ghost_md.wear.STOP"
        private const val TAG = "GhostWear"
        private const val CHANNEL = "ghost_wear_recording"
        private const val NOTIFICATION = 4201

        private val state = MutableStateFlow(Recording())
        val recording: StateFlow<Recording> = state

        /** The take now, for a recovery that must not close it under the microphone. */
        val recordingId: String? get() = state.value.id

        fun start(context: Context) {
            ContextCompat.startForegroundService(context, Intent(context, RecordService::class.java).setAction(ACTION_START))
        }

        fun stop(context: Context) {
            if (state.value.id == null) return
            context.startService(Intent(context, RecordService::class.java).setAction(ACTION_STOP))
        }
    }

    @Volatile private var reading = false
    private var reader: Thread? = null
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> begin()
            ACTION_STOP -> end()
            else -> if (state.value.id == null) stopSelf()
        }
        return START_NOT_STICKY
    }

    @SuppressLint("MissingPermission")
    private fun begin() {
        if (state.value.id != null) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            state.value = Recording(problem = "Ghost.md needs the microphone.")
            stopSelf()
            return
        }
        val id = UUID.randomUUID().toString()
        val started = SystemClock.elapsedRealtime()
        try {
            // The type from Android 10 on; Wear OS 2 (API 28) has none and takes it plain.
            ServiceCompat.startForeground(this, NOTIFICATION, notification(started), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } catch (failure: Exception) {
            Log.w(TAG, "the recording could not come to the front", failure)
            state.value = Recording(problem = "The watch would not let the recording start.")
            stopSelf()
            return
        }
        val rate = WatchLink.SAMPLE_RATE
        val min = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val recorder = try {
            AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(min, rate / 5 * 2) * 2)
        } catch (failure: Exception) {
            null
        }
        if (recorder == null || recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder?.release()
            state.value = Recording(problem = "The microphone would not open.")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        val takes = WatchApp.takes(this)
        val now = System.currentTimeMillis()
        takes.begin(id, now)
        val writer = try {
            WavWriter(takes.wav(id))
        } catch (failure: Exception) {
            recorder.release()
            takes.finish(id, 0)
            state.value = Recording(problem = "There is no room on the watch for a recording.")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        wakeLock = (getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ghost:wear-take").apply {
            setReferenceCounted(false)
            acquire(WatchLink.MAX_TAKE_MS + 60_000)
        }
        state.value = Recording(id = id, startedAt = started)
        reading = true
        recorder.startRecording()
        reader = Thread({ read(id, recorder, writer, started) }, "ghost-wear-take").also { it.start() }
    }

    /** The reading loop, on its own thread: each read into the WAV and its level onto the screen. */
    private fun read(id: String, recorder: AudioRecord, writer: WavWriter, started: Long) {
        val samples = ShortArray(WatchLink.SAMPLE_RATE / 10)
        var failed = false
        try {
            while (reading) {
                val count = recorder.read(samples, 0, samples.size)
                if (count < 0) {
                    failed = true
                    break
                }
                writer.write(samples, count)
                val level = Levels.of(samples, count)
                val now = state.value
                if (now.id == id) state.value = now.copy(level = level)
                if (SystemClock.elapsedRealtime() - started >= WatchLink.MAX_TAKE_MS) break
            }
        } catch (failure: Exception) {
            Log.w(TAG, "the take stopped reading", failure)
            failed = true
        } finally {
            try {
                recorder.stop()
            } catch (_: Exception) {
            }
            recorder.release()
            val ms = try {
                writer.durationMs.also { writer.close() }
            } catch (_: Exception) {
                WavWriter.repair(WatchApp.takes(this).wav(id)) ?: 0
            }
            val take = WatchApp.takes(this).finish(id, ms)
            state.value = Recording(problem = if (failed && take == null) "The microphone stopped." else null)
            if (take != null) {
                Sender.kick(applicationContext)
                Confirmation.show(take)
            }
            wakeLock?.let { if (it.isHeld) it.release() }
            wakeLock = null
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun end() {
        if (!reading) {
            if (state.value.id == null) stopSelf()
            return
        }
        reading = false
    }

    override fun onDestroy() {
        reading = false
        super.onDestroy()
    }

    private fun notification(started: Long): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(CHANNEL) == null) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Recording", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 1, Intent(this, RecordService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ghost_ic_mic)
            .setContentTitle("Recording a note")
            .setContentText("Tap to open, or Stop to send it to your phone.")
            .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(open)
            .addAction(R.drawable.ghost_ic_stop, "Stop", stop)
        // The chip on the watch face and in the recents, which opens the screen: a count-up from the take's start.
        val ongoing = OngoingActivity.Builder(this, NOTIFICATION, builder)
            .setStaticIcon(R.drawable.ghost_ic_mic)
            .setAnimatedIcon(R.drawable.ghost_ic_mic)
            .setTouchIntent(open)
            .setStatus(Status.Builder().addTemplate("#time#").addPart("time", Status.StopwatchPart(started)).build())
            .build()
        ongoing.apply(this)
        return builder.build()
    }
}
