package com.mattssoftware.ghost_md

import android.content.Intent
import android.os.Build
import android.os.Bundle
import com.mattssoftware.glyph.capture.DictationMic
import com.mattssoftware.glyph.files.LibraryTree
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

class MainActivity : FlutterActivity() {
    companion object {
        /** Sent by `GlyphSession` when the side key is held, and by the launcher shortcut (8F, off unless built on). */
        const val ACTION_CAPTURE = "com.mattssoftware.glyph.CAPTURE"
        const val EXTRA_SOURCE = "com.mattssoftware.glyph.SOURCE"

        /** On the recording notification's tap: a plain launch that opens the meeting screen. */
        const val EXTRA_MEETING = "com.mattssoftware.glyph.MEETING"

        /**
         * The activity in front, for the meeting service and the write-up to reach the app through. Set in
         * onResume and cleared in onPause, and a WeakReference, never a captured activity: the service outlives
         * the task, and an activity it held on to would be a leaked window.
         */
        @Volatile private var resumed: WeakReference<MainActivity>? = null

        /** Whether the app is in front. */
        fun isInFront(): Boolean = resumed?.get() != null

        /**
         * `{name, argument}` to the app on `ghost_md/meeting/events`, from anywhere in the process, while an
         * activity is resumed: what the Tauri activity's `tell` did by calling `window.__glyph.<name>(argument)`
         * on its page. False when no activity is resumed, and the word is dropped (the app reads `meetingState`
         * when it is next in front).
         */
        internal fun tell(name: String, argument: String?): Boolean = tell(name, argument, null)

        /**
         * As above, and `taken` hears whether anybody was listening: false while the app is still starting, so a
         * word that must not be lost can be kept and said again.
         */
        internal fun tell(name: String, argument: String?, taken: ((Boolean) -> Unit)?): Boolean {
            val activity = resumed?.get() ?: return false
            activity.runOnUiThread {
                val heard = activity.meeting?.say(name, argument) == true
                taken?.invoke(heard)
            }
            return true
        }
    }

    private var meeting: MeetingBridge? = null

    /** Links that open the app, kept until Dart asks (AppLinks.kt). */
    private val links = AppLinks()

    /** The player of a note's recording, let go with the activity (TapePlayer.kt). */
    private var tape: TapePlayer? = null

    /** The system's pickers, each answered when its activity result arrives (FilesBridge.kt). */
    private val files = FilesBridge(this)

    override fun onCreate(savedInstanceState: Bundle?) {
        // Before super: a capture launch decides the window's lock-screen behaviour before the window is shown.
        meeting = MeetingBridge(this).also { it.onCreate(intent) }
        links.onCreate(intent, restored = savedInstanceState != null)
        // Before the engine starts, and so before the core opens the library: the library may be in a folder chosen
        // through Android's picker (files/LibraryTree.kt), and Rust can reach Kotlin only once it has been handed the
        // class. The tidy lets go of grants for folders that are not the library any more.
        LibraryTree.install(applicationContext, tidy = true)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // Where the app keeps its files, for the Rust core's `init` (lib/core/native/device_paths.dart). The data
        // directory is the one the Tauri app's `app_data_dir` is (Tauri's PathPlugin.getDataDir, line for line):
        // `dataDir`, the parent of `filesDir`, so `Library/` sits where ../glyph's Kotlin and backup rules expect.
        MethodChannel(messenger, "ghost_md/device_paths").setMethodCallHandler { call, result ->
            when (call.method) {
                "dirs" -> {
                    val data = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) dataDir.absolutePath else applicationInfo.dataDir
                    result.success(mapOf("dataDir" to data, "cacheDir" to cacheDir.absolutePath))
                }
                else -> result.notImplemented()
            }
        }
        // The session and the account's keys, under a key the Android Keystore holds (SecureStore.kt;
        // lib/account/device_keys.dart).
        val secrets = SecureStore(applicationContext).also { it.register(messenger) }
        // Stage 8: meetings, the write-up and the capture launch (MeetingBridge.kt; lib/capture/meeting_host.dart),
        // and the dictation microphone (DictationMic.kt; lib/capture/device_mic.dart).
        (meeting ?: MeetingBridge(this).also { meeting = it }).register(messenger)
        DictationMic.register(this, messenger)
        // An address handed to the phone's browser, mail, dialler or maps (OpenLink.kt; lib/core/open_link.dart).
        OpenLink(this).register(messenger)
        // Starting over: the phone's half (ResetChannel.kt; lib/core/reset_native.dart).
        ResetChannel(this, secrets).register(messenger)
        // Links that open the app, handed over when asked for (AppLinks.kt; lib/core/phone_links.dart).
        links.register(messenger)
        // A note's recording, played (TapePlayer.kt; lib/tapes/phone_player.dart).
        tape = TapePlayer(applicationContext).also { it.register(messenger) }
        // The phone's pickers: a folder for the library, a drive to back up to, where an export goes
        // (FilesBridge.kt; lib/core/library_folder.dart, lib/core/backup.dart, lib/core/export_all.dart).
        files.register(messenger)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        meeting?.onNewIntent(intent)
        links.onNewIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        resumed = WeakReference(this)
        meeting?.onResume()
    }

    override fun onPause() {
        if (resumed?.get() === this) resumed = null
        meeting?.onPause()
        super.onPause()
    }

    override fun onStop() {
        // No microphone held by an app nobody can see: a dictation still open is let go (a meeting is the
        // service's, and goes on).
        DictationMic.released()
        super.onStop()
    }

    override fun onDestroy() {
        tape?.release()
        meeting?.onDestroy()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (DictationMic.answered(this, requestCode, grantResults)) return
        meeting?.onRequestPermissionsResult(requestCode, grantResults)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (files.onActivityResult(requestCode, resultCode, data)) return
        meeting?.onActivityResult(requestCode, resultCode, data)
    }
}
