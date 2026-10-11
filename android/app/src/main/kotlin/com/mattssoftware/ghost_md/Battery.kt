package com.mattssoftware.ghost_md

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * The phone's battery, for the AI card's Battery reading (`ghost_md/battery`; lib/core/phone_battery.dart).
 *
 * The page asked its WebView (`navigator.getBattery()`: `charging`, `level`, and the `chargingchange` and
 * `levelchange` events), which Chromium answers from Android's sticky ACTION_BATTERY_CHANGED broadcast: on charge
 * is "plugged into anything", and the level is `level / scale`, to a hundredth. Read the same way here. `watch`
 * answers how things stand now and listens from then on; the app is told `changed` with the same two only when one
 * of them moved, since the broadcast also comes for every change of voltage and temperature.
 *
 * No permission: the broadcast is anyone's. The receiver is let go with the activity.
 */
class Battery(private val context: Context) {
    private var channel: MethodChannel? = null
    private var watching = false
    private var last: Map<String, Any>? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val now = read(intent) ?: return
            if (now == last) return
            last = now
            // A registered receiver is called on the main thread, which is the channel's.
            channel?.invokeMethod("changed", now)
        }
    }

    /** `{charging, level}` out of a battery broadcast, or null where it does not say how full. */
    private fun read(intent: Intent?): Map<String, Any>? {
        if (intent == null) return null
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level < 0 || scale <= 0) return null
        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
        return mapOf("charging" to (plugged != 0), "level" to Math.round(level * 100.0 / scale) / 100.0)
    }

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "ghost_md/battery").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "watch" -> result.success(watch())
                    else -> result.notImplemented()
                }
            }
        }
    }

    /** How things stand now, listening from here on. The broadcast is sticky: registering answers the last one. */
    private fun watch(): Map<String, Any>? {
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val now = if (watching) context.registerReceiver(null, filter) else context.registerReceiver(receiver, filter)
        watching = true
        return read(now)?.also { last = it }
    }

    fun release() {
        if (watching) {
            try {
                context.unregisterReceiver(receiver)
            } catch (_: IllegalArgumentException) {
                // Never registered after all.
            }
        }
        watching = false
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
