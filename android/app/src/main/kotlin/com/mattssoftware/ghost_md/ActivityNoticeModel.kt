package com.mattssoftware.ghost_md

/**
 * A job of the app's record as `activity` tells it (lib/activity/activity_surfaces.dart `surfaceJob`), and what its
 * notification says (ActivityNotices.kt): no Android in here, so the JVM tests read it (app/src/test).
 */
internal data class NoticeJob(
  val id: String,
  val kind: String,
  val look: String,
  val state: String,
  val title: String,
  val line: String,
  val fraction: Double?,
  val steps: String?,
  val colour: Int?,
  val stoppable: Boolean,
  val openable: Boolean,
  val startedAt: Long,
  val cause: String?,
) {
  /** Still to end: an ongoing notification. */
  val live: Boolean get() = state == "running" || state == "waiting" || state == "queued"

  val failed: Boolean get() = state == "failed"

  /** How far, 0 to [NoticeJob.MAX]; null is indeterminate (or waiting, which is drawn still). */
  val progress: Int? get() = fraction?.let { (it.coerceIn(0.0, 1.0) * MAX).toInt() }

  /** Whether the bar goes round: nobody can say how far, and it is not waiting. */
  val indeterminate: Boolean get() = fraction == null

  /**
   * The status bar chip's few letters (Android 16's `setShortCriticalText`): how far, "40%"; nothing for one that
   * cannot say, where the chip shows the glyph alone.
   */
  val chipText: String? get() = when {
    !live -> null
    look == "waiting" -> "Wait"
    fraction != null -> "${(fraction.coerceIn(0.0, 1.0) * 100).toInt()}%"
    else -> null
  }

  /** The line under the title: what it does now, unless that is the title again. */
  val text: String get() = if (line == title) steps ?: "" else line

  /** Which of the glyphs it wears ([ActivityNotices] maps the name to its drawable). */
  val glyph: String get() = when {
    look == "needsYou" -> "needs_you"
    kind in KINDS -> kind
    else -> "ring"
  }

  companion object {
    const val MAX = 1000
    val KINDS = setOf("sync", "ai", "images", "audio", "meetings", "downloads")

    /** Read from the channel's map; null where it says no id. */
    fun from(map: Map<*, *>?): NoticeJob? {
      val id = map?.get("id") as? String ?: return null
      fun word(key: String) = map[key] as? String
      return NoticeJob(
        id = id,
        kind = word("kind") ?: "sync",
        look = word("look") ?: word("kind") ?: "sync",
        state = word("state") ?: "running",
        title = word("title") ?: "Ghost.md",
        line = word("line") ?: "",
        fraction = (map["fraction"] as? Number)?.toDouble(),
        steps = word("steps"),
        colour = (map["colour"] as? Number)?.toLong()?.toInt(),
        stoppable = map["stoppable"] == true,
        openable = map["openable"] == true,
        startedAt = (map["startedAt"] as? Number)?.toLong() ?: 0L,
        cause = word("cause"),
      )
    }
  }
}

/**
 * The notification ids the jobs are shown under: one each, the same for a job for as long as it shows, from
 * [FIRST] up (the recordings' are 4201-4203, the job service's 4301). No tag: a foreground service takes its
 * notification by id alone, and the job service adopts these (BackgroundJobs.kt).
 */
internal class NoticeIds {
  private val ids = HashMap<String, Int>()
  private var next = FIRST

  fun of(job: String): Int = ids.getOrPut(job) { next++.also { if (next > LAST) next = FIRST } }

  fun has(job: String): Boolean = ids.containsKey(job)

  fun release(job: String): Int? = ids.remove(job)

  companion object {
    const val FIRST = 4500
    const val LAST = 4999
  }
}

/** The jobs shown that the app no longer says: their notifications go ([ActivityNotices.told]). */
internal fun noticesGone(shown: Collection<String>, told: Collection<String>): List<String> = shown.filter { it !in told }

/** The group's summary: "3 jobs running", shown only while two or more are. */
internal fun summaryTitle(count: Int): String? = if (count < 2) null else "$count jobs running"
