package com.mattssoftware.glyph.updates

/**
 * The door into Rust for the background update check (src-tauri/src/update_alerts.rs).
 *
 * The library is loaded HERE, not left to the activity: WorkManager can start
 * this app's process just to run a job, with no MainActivity and so no
 * generated `Rust.kt` having loaded anything. A second `loadLibrary` when the
 * activity has already loaded it is a no-op.
 */
internal object UpdateCheck {
  init {
    System.loadLibrary("glyph_lib")
  }

  /** The published update as JSON, verified in Rust; see `ota::Peek`. */
  @JvmStatic external fun run(otaDir: String): String?
}
