package com.mattssoftware.ghost_md.wear

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.Wearable
import com.mattssoftware.ghost_md.watchlink.TakeFrame
import com.mattssoftware.ghost_md.watchlink.TakeMeta
import com.mattssoftware.ghost_md.watchlink.WatchLink
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.TimeUnit

/**
 * The takes on their way to the phone (docs/WATCH.md, "The link"). [kick] sends every queued take, one at a time, to
 * the phone that has Ghost.md (the node with [WatchLink.PHONE_CAPABILITY], the one nearby first): a Data Layer
 * channel at [WatchLink.TAKE_PATH], the take's [TakeFrame] header and then its WAV. The take is then SENT, and the
 * phone's answer (WatchListener, [WatchLink.ACK_PATH]) makes it ON_PHONE and lets the watch's copy go.
 *
 * Kicked when a take stops, when the screen comes up, when the phone's capability comes and goes (WatchListener), and
 * by [SendWorker] while anything waits: in two minutes for an answer that has not come, in fifteen for a phone that
 * was not near, with WorkManager's backoff after that. One send at a time, whoever kicks.
 */
object Sender {
    private const val TAG = "GhostWearSend"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val one = Mutex()

    fun kick(context: Context) {
        val app = context.applicationContext
        scope.launch { send(app) }
    }

    /**
     * Sends what waits; answers whether a phone was there to send to (true, too, when nothing waited). [schedule]: a
     * [SendWorker] is asked for while anything still waits (never by the worker itself, whose own retry is the next).
     */
    suspend fun send(context: Context, schedule: Boolean = true): Boolean = one.withLock {
        val takes = WatchApp.takes(context)
        val queued = takes.toSend()
        if (queued.isEmpty()) {
            if (schedule && takes.waiting()) SendWorker.later(context, TimeUnit.MILLISECONDS.toMinutes(TakeQueue.ACK_WAIT_MS))
            return@withLock true
        }
        val phone = phone(context)
        PhoneNear.near.value = phone != null
        if (phone == null) {
            if (schedule) SendWorker.later(context, 15)
            return@withLock false
        }
        val channels = Wearable.getChannelClient(context)
        val name = WatchApp.watchName(context)
        for (take in queued) {
            val file = takes.wav(take.id)
            if (!file.isFile) continue
            takes.sending(take.id)
            try {
                val channel = Tasks.await(channels.openChannel(phone.id, WatchLink.TAKE_PATH), 20, TimeUnit.SECONDS)
                try {
                    Tasks.await(channels.getOutputStream(channel), 20, TimeUnit.SECONDS).use { out ->
                        TakeFrame.write(out, TakeMeta(id = take.id, recordedAt = take.recordedAt, durationMs = take.durationMs, watch = name, bytes = file.length()))
                        file.inputStream().use { it.copyTo(out, 64 * 1024) }
                        out.flush()
                    }
                } finally {
                    try {
                        Tasks.await(channels.close(channel), 10, TimeUnit.SECONDS)
                    } catch (_: Exception) {
                        // Closed from the phone's side already.
                    }
                }
                // Unless the answer came first, over a fast link.
                if (takes.get(take.id)?.state == TakeState.SENDING) takes.sent(take.id)
            } catch (failure: Exception) {
                Log.w(TAG, "a take did not reach the phone", failure)
                takes.unsent(take.id)
            }
        }
        if (schedule) SendWorker.later(context, TimeUnit.MILLISECONDS.toMinutes(TakeQueue.ACK_WAIT_MS))
        true
    }

    /** The phone with Ghost.md on it, nearby first; null where none is connected. */
    private fun phone(context: Context): Node? = try {
        val capability = Tasks.await(Wearable.getCapabilityClient(context).getCapability(WatchLink.PHONE_CAPABILITY, CapabilityClient.FILTER_REACHABLE), 10, TimeUnit.SECONDS)
        capability.nodes.firstOrNull { it.isNearby } ?: capability.nodes.firstOrNull()
    } catch (failure: Exception) {
        Log.w(TAG, "the phone could not be looked for", failure)
        null
    }
}

/** A later [Sender.kick], while takes wait: one at a time, replaced by the newest ask. */
class SendWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    companion object {
        private const val NAME = "ghost-wear-send"

        fun later(context: Context, minutes: Long) {
            val request = OneTimeWorkRequestBuilder<SendWorker>()
                .setInitialDelay(minutes.coerceAtLeast(1), TimeUnit.MINUTES)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 15, TimeUnit.MINUTES)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(NAME, ExistingWorkPolicy.REPLACE, request)
        }
    }

    override suspend fun doWork(): Result {
        Sender.send(applicationContext, schedule = false)
        // Sent and waiting for the phone's answer, or no phone near: looked at again with WorkManager's backoff.
        return if (WatchApp.takes(applicationContext).waiting()) Result.retry() else Result.success()
    }
}
