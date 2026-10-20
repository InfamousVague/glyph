package com.mattssoftware.ghost_md.wear

import android.content.Context
import android.provider.Settings
import android.os.Build
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** The process's one queue of takes, made on first use, with what a killed process left put right (TakeQueue.recover). */
object WatchApp {
    @Volatile private var queue: TakeQueue? = null

    fun takes(context: Context): TakeQueue = queue ?: synchronized(this) {
        queue ?: TakeQueue(context.applicationContext.filesDir).also {
            it.recover(RecordService.recordingId)
            queue = it
        }
    }

    /** The watch's own name for the phone's Settings: the one its owner gave it, else its model. */
    fun watchName(context: Context): String =
        Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)?.takeIf { it.isNotBlank() } ?: Build.MODEL ?: "Watch"
}

/** The take that has just stopped, for the screen's word on where it went; null once that has been said. */
object Confirmation {
    private val last = MutableStateFlow<String?>(null)
    val take: StateFlow<String?> = last

    fun show(take: Take) {
        last.value = take.id
    }

    fun dismiss() {
        last.value = null
    }
}

/** Whether the phone was found the last time a send was tried: null before any try. */
object PhoneNear {
    val near = MutableStateFlow<Boolean?>(null)
}
