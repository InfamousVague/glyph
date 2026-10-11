package com.mattssoftware.glyph.recordings

/**
 * The door into Rust for a meeting's write-up (src-tauri/src/recording_jobs.rs).
 * Loaded here, as UpdateCheck is: WorkManager may start the process with no
 * activity, and so with no generated `Rust.kt` having loaded anything. A second
 * `loadLibrary` when the activity has already loaded it is a no-op.
 *
 * Every answer is JSON (src-tauri/src/write_up.rs `Answer::to_json`), and every
 * call is made off the main thread: `run` blocks for the whole write-up, and
 * `cancel` may wait up to five seconds for a run to let go. A Rust test reads
 * this file for the three `external fun` lines and the package, so the names
 * here and the `Java_com_mattssoftware_glyph_recordings_RecordingJob_*` symbols
 * in recording_jobs.rs move together or not at all.
 */
internal object RecordingJob {
  init {
    System.loadLibrary("glyph_lib")
  }

  /** Stop's bookkeeping: the header patched from the file's length, the note's tape recorded. `{"recordedMs": n}` or `{"error": s}`. */
  @JvmStatic external fun finish(dataDir: String, noteId: String, title: String): String?

  /** The write-up itself, blocking. `options` is write_up.rs's `Options` as JSON (WriteUp.options); the answer is one of `Answer`'s shapes. */
  @JvmStatic external fun run(dataDir: String, noteId: String, options: String): String?

  /** Raise the run's abort with `reason` ("cancel", "thermal", "timeout", "meeting"); `{"cancelled": bool}`. */
  @JvmStatic external fun cancel(dataDir: String, noteId: String, reason: String): String?
}
