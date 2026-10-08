package com.mattssoftware.ghost_md

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Where the app keeps its files, for the Rust core's `init` (lib/core/native/device_paths.dart). The data
        // directory is the one the Tauri app's `app_data_dir` is (Tauri's PathPlugin.getDataDir, line for line):
        // `dataDir`, the parent of `filesDir`, so `Library/` sits where ../glyph's Kotlin and backup rules expect.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ghost_md/device_paths").setMethodCallHandler { call, result ->
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
        SecureStore(applicationContext).register(flutterEngine.dartExecutor.binaryMessenger)
    }
}
