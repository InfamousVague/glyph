package com.mattssoftware.ghost_md.watch

import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.ChannelClient
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import com.mattssoftware.ghost_md.watchlink.WatchLink
import java.util.concurrent.TimeUnit

/**
 * A take from the watch, heard with the app open or closed (the manifest's CHANNEL_EVENT filter for
 * [WatchLink.TAKE_PATH]; docs/WATCH.md, "On the phone"). The channel's stream goes into the inbox (WatchInbox), and
 * only once it is kept there is the watch answered ([WatchLink.ACK_PATH]), so the watch lets its copy go only when
 * the phone has one. A take the inbox already had is answered too, and kept once.
 *
 * Then the app is told: a running app, open or behind another, makes the note at once (WatchBridge's event,
 * lib/watch/watch_notes.dart); with the app not running, a notification says a voice note came from the watch, and
 * opening it, or the app, makes the note. The words are always the phone's own Whisper's, as a note recorded here.
 * Play services calls this on a thread of its own, so the stream is read here, blocking, to its end.
 */
class WatchListenerService : WearableListenerService() {
    override fun onChannelOpened(channel: ChannelClient.Channel) {
        if (channel.path != WatchLink.TAKE_PATH) return
        val channels = Wearable.getChannelClient(this)
        try {
            val received = Tasks.await(channels.getInputStream(channel), 30, TimeUnit.SECONDS).use { WatchBridge.inbox(this).receive(it) }
            val meta = when (received) {
                is WatchInbox.Received.Kept -> received.meta
                is WatchInbox.Received.Again -> received.meta
            }
            try {
                Tasks.await(Wearable.getMessageClient(this).sendMessage(channel.nodeId, WatchLink.ACK_PATH, meta.id.toByteArray(Charsets.UTF_8)), 20, TimeUnit.SECONDS)
            } catch (failure: Exception) {
                // Kept all the same: the watch sends it again, and is answered then.
                Log.w(TAG, "the watch was not answered", failure)
            }
            if (received is WatchInbox.Received.Kept && !WatchBridge.tell(meta.id)) WatchNotice.post(this)
        } catch (failure: Exception) {
            Log.w(TAG, "a take from the watch was not kept", failure)
        } finally {
            try {
                Tasks.await(channels.close(channel), 10, TimeUnit.SECONDS)
            } catch (_: Exception) {
                // Closed by the watch already.
            }
        }
    }

    private companion object {
        const val TAG = "GhostWatch"
    }
}
