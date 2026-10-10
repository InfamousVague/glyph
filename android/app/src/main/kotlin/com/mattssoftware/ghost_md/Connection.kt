package com.mattssoftware.ghost_md

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Whether the phone has a connection, and the moment one comes back (`ghost_md/connection`;
 * lib/core/phone_connection.dart).
 *
 * The page asked its WebView: `navigator.onLine`, and the window's `online` event, which Chromium answers from
 * ConnectivityManager's default network. Asked of the same place here. `online` answers whether there is a default
 * network now; and the app is told `online` each time one becomes the default after there was none, and `offline`
 * when the last one goes, so what it holds is as fresh as the page's was. A blank left "Waiting for a connection"
 * goes on from that word (lib/ai/fills/queue.dart `resumeParked`).
 *
 * ACCESS_NETWORK_STATE is a normal permission: nothing is asked of the person. A phone that refuses the question
 * all the same is answered as a WebView without the permission answers: online, and never a word of a change.
 * Nothing is sent anywhere by asking: the answer is the phone's own.
 */
class Connection(private val context: Context) {
    private val manager: ConnectivityManager? by lazy { context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager }
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var watching = false

    /** As last heard: the callback's threads write it, the channel's reads it. */
    @Volatile private var up = true

    private val callback = object : ConnectivityManager.NetworkCallback() {
        // A default network: the first after there was none is the connection coming back. One taking another's
        // place (Wi-Fi for mobile data) arrives here with no loss between, and is not a return.
        override fun onAvailable(network: Network) {
            val was = up
            up = true
            if (!was) say("online")
        }

        // Called for the default network only once nothing takes its place.
        override fun onLost(network: Network) {
            up = false
            say("offline")
        }
    }

    private fun say(word: String) {
        main.post { channel?.invokeMethod(word, null) }
    }

    private fun onLine(): Boolean = try {
        val now = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) manager?.activeNetwork != null else true
        up = now
        now
    } catch (_: SecurityException) {
        true
    }

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "ghost_md/connection").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "online" -> result.success(onLine())
                    else -> result.notImplemented()
                }
            }
        }
        if (watching || Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        try {
            manager?.registerDefaultNetworkCallback(callback)
            watching = manager != null
        } catch (_: SecurityException) {
            // Not allowed to ask: online, as far as anyone here can tell.
        } catch (_: RuntimeException) {
            // Too many callbacks registered in this process: the question is still answered when asked.
        }
    }

    /** With the activity: the callback holds this, and through it the channel. */
    fun release() {
        if (watching) {
            try {
                manager?.unregisterNetworkCallback(callback)
            } catch (_: IllegalArgumentException) {
                // Never registered after all.
            }
        }
        watching = false
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
