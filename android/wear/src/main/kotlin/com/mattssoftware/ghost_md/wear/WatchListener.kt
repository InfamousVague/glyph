package com.mattssoftware.ghost_md.wear

import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import com.mattssoftware.ghost_md.watchlink.WatchLink

/**
 * What the phone says to the watch, heard with the app closed (the manifest's filters): a take's answer
 * ([WatchLink.ACK_PATH]: the phone has it, the watch's copy goes), and the phone's Ghost.md coming within reach
 * ([WatchLink.PHONE_CAPABILITY] changing), which sends what waited.
 */
class WatchListener : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != WatchLink.ACK_PATH) return
        val id = String(event.data, Charsets.UTF_8)
        if (WatchLink.plainId(id)) WatchApp.takes(this).acked(id)
    }

    override fun onCapabilityChanged(info: CapabilityInfo) {
        if (info.name == WatchLink.PHONE_CAPABILITY && info.nodes.isNotEmpty()) Sender.kick(this)
    }
}
