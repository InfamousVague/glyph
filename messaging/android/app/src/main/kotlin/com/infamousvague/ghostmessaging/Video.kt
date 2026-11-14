package com.infamousvague.ghostmessaging

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.MediaController
import android.widget.TextView
import android.widget.VideoView
import java.io.ByteArrayOutputStream

/**
 * A video in a picture message (Matt, 2026-11-14: "mp4 files are not loading it just shows up as a string of text
 * for the filename"): a picture of where it starts and how long it runs, for the conversation to draw, and a screen
 * that plays it. A video was drawn as its file's name and nothing else.
 */
object Video {
    private const val TAG = "GhostMessaging"

    /** The longer side of the picture made of a video, in pixels: enough for a bubble on any screen. */
    const val SIDE = 720

    /** How large a picture [width] by [height] is drawn so that its longer side is [SIDE] at most, never enlarged. */
    fun fitted(width: Int, height: Int): Pair<Int, Int> {
        val longer = maxOf(width, height)
        if (longer <= SIDE || longer <= 0) return width to height
        val scale = SIDE.toDouble() / longer
        return maxOf(1, Math.round(width * scale).toInt()) to maxOf(1, Math.round(height * scale).toInt())
    }

    /**
     * The video in the message part [part]: `picture` (a JPEG of where it starts, or null where none can be made:
     * a kind this phone cannot read, or sound alone), `millis` (how long it runs, 0 where unknown), and the picture's
     * `width` and `height`.
     */
    fun preview(context: Context, part: Long): Map<String, Any?> {
        val m = MediaMetadataRetriever()
        return try {
            m.setDataSource(context.applicationContext, Uri.parse("content://mms/part/$part"))
            val millis = m.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            // The first frame that can be drawn by itself: where the video starts, or just after.
            val frame = try { m.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC) } catch (e: Exception) { null }
            var picture: ByteArray? = null
            var width = 0
            var height = 0
            if (frame != null) {
                val (w, h) = fitted(frame.width, frame.height)
                val small = if (w != frame.width || h != frame.height) Bitmap.createScaledBitmap(frame, w, h, true) else frame
                val out = ByteArrayOutputStream()
                small.compress(Bitmap.CompressFormat.JPEG, 82, out)
                picture = out.toByteArray()
                width = w
                height = h
            }
            mapOf("picture" to picture, "millis" to millis, "width" to width, "height" to height)
        } catch (e: Exception) {
            Log.w(TAG, "video preview", e)
            mapOf("picture" to null, "millis" to 0L, "width" to 0, "height" to 0)
        } finally {
            try { m.release() } catch (_: Exception) {}
        }
    }
}

/**
 * Plays the video in a message's part, the whole screen: Android's own player and its own controls (play, pause,
 * where it has got to), over black. It is read from where the message keeps it; nothing is copied anywhere.
 */
class VideoActivity : Activity() {
    companion object {
        const val PART = "part"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val part = intent.getLongExtra(PART, -1)
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        setContentView(root)
        if (part < 0) { finish(); return }
        val video = VideoView(this)
        root.addView(video, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT, Gravity.CENTER))
        val controls = MediaController(this)
        controls.setAnchorView(video)
        video.setMediaController(controls)
        video.setOnPreparedListener {
            video.start()
            // The controls show as it starts, so there is something to hold: they hide themselves after a moment.
            controls.show(2500)
        }
        video.setOnErrorListener { _, what, extra ->
            Log.w("GhostMessaging", "video play: $what/$extra")
            root.removeView(video)
            root.addView(TextView(this).apply {
                text = "This video can't be played on this phone."
                setTextColor(Color.WHITE)
                textSize = 16f
                gravity = Gravity.CENTER
            }, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
            true
        }
        video.setVideoURI(Uri.parse("content://mms/part/$part"))
    }
}
