package com.mattssoftware.ghost_md

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

/**
 * The hinge, streamed to the app while it is up (`ghost_md/hinge`; lib/core/unfold.dart).
 *
 * The note screen draws its unfold from the angle, so it needs the angle as it changes, not the fold state after
 * the fact. The sensor is Android's own (TYPE_HINGE_ANGLE, degrees, 0 closed to 180 flat): no permission, and a
 * phone without one - every slab - answers null and nothing here runs. Registered in onResume and dropped in
 * onPause, so a backgrounded app is not woken fifty times a second by a hand opening the phone for something else.
 * The Tauri activity's own (MainActivity.kt `hingeListener`), saying `angle` on a method channel where it called
 * `window.__glyph.hinge(degrees)`; a word nobody is listening for yet is dropped, as the page's was.
 */
class Hinge(private val context: Context) {
    private val manager: SensorManager? by lazy { context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager }
    private val sensor: Sensor? by lazy { manager?.getDefaultSensor(Sensor.TYPE_HINGE_ANGLE) }
    private var last = Float.NaN
    private var channel: MethodChannel? = null

    private val listener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            val angle = event.values[0]
            // Half a degree is below anything the note draws; a sensor that chatters in hundredths would otherwise
            // post a message per tick.
            if (!last.isNaN() && abs(angle - last) < 0.5f) return
            last = angle
            // Sensor events arrive on the main thread, which is the channel's.
            channel?.invokeMethod("angle", angle.toDouble())
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
    }

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "ghost_md/hinge")
    }

    /** Registered whether or not anything listens yet: on a cold start it may not, and readings are dropped until it does. */
    fun onResume() {
        val hinge = sensor ?: return
        last = Float.NaN
        manager?.registerListener(listener, hinge, SensorManager.SENSOR_DELAY_GAME)
    }

    fun onPause() {
        manager?.unregisterListener(listener)
    }
}
