package com.mattssoftware.ghost_md.watch

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.Wearable
import com.mattssoftware.ghost_md.MainActivity
import com.mattssoftware.ghost_md.R
import com.mattssoftware.ghost_md.watchlink.WatchLink
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * The watch's takes, as the app asks for them (lib/watch/watch_link.dart; docs/WATCH.md, "On the phone").
 *
 * THE CHANNEL `ghost_md/watch`:
 * - `waiting` -> JSON `[{id, recordedAt, durationMs, watch, bytes, wav}]`: the takes in the inbox, oldest first, `wav`
 *   the file's path (gone already when the app had moved it to the note's recording before it was stopped).
 * - `done {id}` -> null: the take is a note; its files go and the notification with them once none waits.
 * - `status` -> JSON `{watches: [{name, nearby}], last: {id, recordedAt, durationMs, watch, receivedAt} | null,
 *   waiting}`: the watches connected now that have Ghost.md, for Settings › Recording › Watch.
 *
 * THE EVENTS on `ghost_md/watch/events`: a take's id, each time one is kept while the app's engine runs (in front or
 * not). With no engine listening, WatchListenerService posts the notification instead.
 */
class WatchBridge(private val context: Context) {
    companion object {
        const val CHANNEL = "ghost_md/watch"
        const val EVENTS = "ghost_md/watch/events"

        @Volatile private var sink: EventChannel.EventSink? = null
        @Volatile private var inbox: WatchInbox? = null
        private val main = Handler(Looper.getMainLooper())
        private val asking = Executors.newSingleThreadExecutor { Thread(it, "ghost-watch-status") }

        /** The process's one inbox: `<dataDir>/watch`, beside the core's `recordings/`. */
        fun inbox(context: Context): WatchInbox = inbox ?: synchronized(this) {
            inbox ?: WatchInbox(File(context.applicationContext.dataDir, "watch")).also { inbox = it }
        }

        /** Tells a running app take [id] has come; false when no engine listens, and nobody was told. */
        fun tell(id: String): Boolean {
            if (sink == null) return false
            main.post { sink?.success(id) }
            return true
        }
    }

    fun register(messenger: BinaryMessenger) {
        EventChannel(messenger, EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sink = events
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(::answer)
    }

    /** The engine is going with the activity: nobody hears a take now, so the next one is a notification. */
    fun detach() {
        sink = null
    }

    private fun answer(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "waiting" -> {
                val list = JSONArray()
                for (take in inbox(context).waiting()) {
                    list.put(WatchInbox.json(take.meta).put("wav", take.wav.absolutePath))
                }
                result.success(list.toString())
            }
            "done" -> {
                val id = call.argument<String>("id") ?: ""
                inbox(context).done(id)
                if (inbox(context).waiting().isEmpty()) WatchNotice.clear(context)
                result.success(null)
            }
            "status" -> asking.execute {
                val status = status()
                main.post { result.success(status) }
            }
            else -> result.notImplemented()
        }
    }

    /** What Settings shows: the watches with Ghost.md connected now, the last take, and how many wait. */
    private fun status(): String {
        val watches = JSONArray()
        try {
            val capability = Tasks.await(Wearable.getCapabilityClient(context).getCapability(WatchLink.WATCH_CAPABILITY, CapabilityClient.FILTER_REACHABLE), 5, TimeUnit.SECONDS)
            for (node in capability.nodes) watches.put(JSONObject().put("name", node.displayName).put("nearby", node.isNearby))
        } catch (_: Exception) {
            // No Play services' wearable API on this phone, or no watch ever paired: none.
        }
        val inbox = inbox(context)
        return JSONObject()
            .put("watches", watches)
            .put("last", inbox.last() ?: JSONObject.NULL)
            .put("waiting", inbox.waiting().size)
            .toString()
    }
}

/**
 * "Recording from your watch", while the app is not running to take it in (docs/WATCH.md). Worded for both ends a take
 * can come to, a voice note or a Claude ask ("Send short watch recordings to Claude"), which only the app knows.
 */
object WatchNotice {
    private const val CHANNEL_ID = "ghost_watch"
    private const val ID = 4310

    fun post(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= 33 && !manager.areNotificationsEnabled()) return
        if (manager.getNotificationChannel(CHANNEL_ID) == null) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Watch", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "A recording from your watch, waiting for Ghost.md to open."
            })
        }
        val count = WatchBridge.inbox(context).waiting().size.coerceAtLeast(1)
        val open = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val tap = PendingIntent.getActivity(context, ID, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = androidx.core.app.NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ghost_ic_mic)
            .setContentTitle(if (count == 1) "Recording from your watch" else "$count recordings from your watch")
            .setContentText(if (count == 1) "Open Ghost.md to finish it." else "Open Ghost.md to finish them.")
            .setAutoCancel(true)
            .setContentIntent(tap)
            .build()
        try {
            manager.notify(ID, notification)
        } catch (_: SecurityException) {
            // Notifications refused: the note is made the next time the app opens.
        }
    }

    fun clear(context: Context) {
        context.getSystemService(NotificationManager::class.java)?.cancel(ID)
    }
}
