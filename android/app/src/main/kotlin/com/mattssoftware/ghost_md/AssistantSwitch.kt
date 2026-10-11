package com.mattssoftware.ghost_md

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build

/**
 * The phone assistant, the side key and the launcher's "Record note", switched on for THIS phone by a developer
 * (Settings > Developer > Work in progress > Voice assistant; lib/core/wip.dart).
 *
 * They are off in every build unless the build turns them on (`@bool/ghost_assistant`, android/app/build.gradle.kts):
 * the three services and the activity's capture doors are in the manifest, disabled, so the app is not offered as a
 * digital assistant and nothing outside it can start a capture. The switch is the way Ghost.md's own unmerged branch
 * `voice/assistant-flag` has it (its docs/DESIGN.md §146): a flag of the device's, never of the account's, off on
 * every device after the update. That branch could only decline the key in the page, since "a manifest shortcut
 * cannot be disabled at runtime"; here the switch does what it says:
 *
 * - the four manifest components are enabled for this phone, or put back to what the manifest says;
 * - "Record note" is published as a dynamic shortcut under the id the manifest's has (`capture`), or removed, so one
 *   pinned to a home screen comes back to life with the switch and goes grey without it;
 * - [on] is what MeetingBridge.kt asks before it will read a launch as a capture.
 *
 * Switching it on does not make the app the phone's assistant: a person still picks it under Settings > Apps >
 * Default apps > Digital assistant app.
 */
object AssistantSwitch {
    private const val PREFS = "glyph_wip"
    private const val KEY = "assistant"
    private const val SHORTCUT = "capture"

    /** The manifest's four, by the names it gives them. */
    private val components = listOf(
        "com.mattssoftware.ghost_md.CaptureDoor",
        "com.mattssoftware.glyph.capture.GlyphInteractionService",
        "com.mattssoftware.glyph.capture.GlyphSessionService",
        "com.mattssoftware.glyph.capture.GlyphRecognitionService",
    )

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Whether this phone's switch is on. */
    fun on(context: Context): Boolean = prefs(context).getBoolean(KEY, false)

    /** Whether the assistant is there at all: the build's own switch, or this phone's. */
    fun enabled(context: Context): Boolean = context.resources.getBoolean(R.bool.ghost_assistant) || on(context)

    /** Switches it for this phone. Kept first, so a phone that refuses a component is still told the truth by [on]. */
    fun set(context: Context, on: Boolean) {
        val app = context.applicationContext
        prefs(app).edit().putBoolean(KEY, on).apply()
        val state = if (on) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DEFAULT
        for (name in components) {
            try {
                app.packageManager.setComponentEnabledSetting(ComponentName(app.packageName, name), state, PackageManager.DONT_KILL_APP)
            } catch (failure: Exception) {
                // A phone that will not have it: the others still go, and the capture launch is still read.
                android.util.Log.w("GhostAssistant", "could not switch $name: $failure")
            }
        }
        shortcut(app, on)
    }

    /** "Record note" on a long press of the icon, where the build's manifest does not already carry it. */
    private fun shortcut(app: Context, on: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return
        if (app.resources.getBoolean(R.bool.ghost_assistant)) return
        try {
            val manager = app.getSystemService(ShortcutManager::class.java) ?: return
            if (!on) {
                manager.removeDynamicShortcuts(listOf(SHORTCUT))
                return
            }
            val intent = Intent(MainActivity.ACTION_CAPTURE).setComponent(ComponentName(app.packageName, components[0]))
            val made = ShortcutInfo.Builder(app, SHORTCUT)
                .setShortLabel(app.getString(R.string.ghost_capture_short))
                .setLongLabel(app.getString(R.string.ghost_capture_long))
                .setIcon(Icon.createWithResource(app, R.mipmap.ic_launcher))
                .setIntent(intent)
                .build()
            manager.addDynamicShortcuts(listOf(made))
        } catch (failure: Exception) {
            android.util.Log.w("GhostAssistant", "could not publish the shortcut: $failure")
        }
    }
}
