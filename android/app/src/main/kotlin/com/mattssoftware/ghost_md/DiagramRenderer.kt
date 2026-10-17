package com.mattssoftware.ghost_md

import android.annotation.SuppressLint
import android.app.Activity
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.sqrt
import org.json.JSONObject

/**
 * A note's diagrams, drawn (lib/editor/diagrams/bridge.dart, the phone's half of `ghost_md/diagrams`).
 *
 * There is no Mermaid but Mermaid, so a ```mermaid fence is drawn by Mermaid itself: the release the web app pins,
 * on a page of the app's own (assets/diagrams/index.html), in ONE web view that is made the first time a diagram is
 * asked for and is never put on the screen. It is not a child of any window. The page draws the diagram where a
 * note would have it and says where that is; the web view is then drawn into a bitmap, there, by the software
 * path (`View.draw` on a bitmap's canvas, which composes the page as it stands without a window), and the bitmap
 * goes back as a PNG. The app shows the picture: nothing of a web view is ever in the scrolling note.
 *
 * Why a photograph of the web view and not the page drawing its own SVG onto a `<canvas>`: a flowchart's words are
 * HTML inside the SVG (`foreignObject`), in the note's own face, inherited from the page round it. An SVG drawn as
 * an image inherits nothing and loads no fonts, and WebKit refuses to hand back a canvas an SVG with HTML in it was
 * drawn on; the way round both is Mermaid's `htmlLabels: false`, which is another drawing. The web view's own paint
 * of the web app's own nest of boxes is the picture the web app shows.
 *
 * - `draw` `{n, viewport, ask}` -> `{png, blockWidth, blockHeight, x, y, width, height, scale}`, or `{failed}`:
 *   Mermaid's words for a diagram written wrong, and "" when the fault is not the person's (no web view on this
 *   phone, a page that did not load, a picture that never came).
 *
 * NOTHING IS FETCHED. The page and what it loads are files inside the app; the web view is told to load nothing
 * from a network, to read no file and no content address but the app's own assets, and to keep nothing; and the
 * page's own policy lets in nothing but its folder. A diagram that names a picture on the internet draws without it.
 *
 * One diagram at a time, as Dart asks them. The page says which picture it has drawn by painting the picture's
 * number as a colour in its corner in the same breath as the diagram, and the photograph is taken only once that
 * colour is there: a frame of the diagram before can never be taken for this one.
 */
class DiagramRenderer(private val activity: Activity) {
  private class Ask(val n: Int, val viewport: Double, val json: String, val result: MethodChannel.Result)

  private val main = Handler(Looper.getMainLooper())
  private val debuggable = (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
  private var web: WebView? = null

  /** The page has loaded and said so. */
  private var ready = false

  /** The phone's web view has been found and loaded ([warm]), or is being. */
  private var warmed = false
  private var warming = false

  /** The one the page is drawing, and the ones behind it. */
  private var asking: Ask? = null
  private val line = ArrayDeque<Ask>()

  /** Patience ran out. A page that never loaded is let go with it, so the next diagram asks a new one. */
  private val giveUp = Runnable {
    if (ready) {
      // Said, as every other way a diagram goes undrawn is: quiet, this was the one a phone could not be asked about.
      asking?.let {
        Log.w(TAG, "a diagram was given up on: the page took too long")
        finish(it, failed(""))
      }
    } else {
      lost()
    }
  }
  private val rest = Runnable { if (asking == null && line.isEmpty()) close() }

  fun register(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "draw" -> {
          val n = call.argument<Number>("n")?.toInt()
          val viewport = call.argument<Number>("viewport")?.toDouble()
          val json = call.argument<String>("ask")
          if (n == null || viewport == null || json == null || viewport <= 0) {
            result.success(failed(""))
          } else {
            line.addLast(Ask(n, viewport, json, result))
            next()
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  /** The activity is going: the web view with it, and whoever waits is told there is no picture. */
  fun destroy() {
    asking?.let { finish(it, failed(""), then = false) }
    while (line.isNotEmpty()) line.removeFirst().result.success(failed(""))
    close()
  }

  private fun next() {
    if (asking != null) return
    val ask = line.removeFirstOrNull() ?: return
    asking = ask
    main.removeCallbacks(rest)
    main.removeCallbacks(giveUp)
    main.postDelayed(giveUp, PATIENCE_MS)
    serve(ask)
  }

  private fun serve(ask: Ask) {
    if (web == null && !warmed) {
      warm()
      return
    }
    val view = open()
    if (view == null) {
      finish(ask, failed(""))
      return
    }
    if (ready) begin(view, ask)
  }

  /**
   * The phone's web view, found and loaded off the main thread before the first one is made on it: most of what a
   * first web view costs is the loading of its library, and that would otherwise be a stopped frame or several in
   * the note the first diagram is in.
   */
  private fun warm() {
    if (warming) return
    warming = true
    Thread {
      try {
        // Asks the phone for its web view, which loads it; and is what must be said before the first one is made:
        // the whole page is drawn, not only what a window would show of it.
        WebView.enableSlowWholeDocumentDraw()
      } catch (error: Throwable) {
        // No web view on this phone: making one says so, below.
      }
      main.post {
        warming = false
        warmed = true
        asking?.let { serve(it) }
      }
    }.start()
  }

  /** The web view, made and its page asked for the first time it is wanted. Null on a phone that has none. */
  @SuppressLint("SetJavaScriptEnabled")
  private fun open(): WebView? {
    web?.let { return it }
    return try {
      val view = WebView(activity)
      view.setBackgroundColor(Color.TRANSPARENT)
      view.isVerticalScrollBarEnabled = false
      view.isHorizontalScrollBarEnabled = false
      view.overScrollMode = View.OVER_SCROLL_NEVER
      view.settings.apply {
        javaScriptEnabled = true
        blockNetworkLoads = true
        blockNetworkImage = true
        // The app's own assets are still read (file:///android_asset): this is every other file.
        allowFileAccess = false
        allowContentAccess = false
        @Suppress("DEPRECATION")
        allowFileAccessFromFileURLs = false
        @Suppress("DEPRECATION")
        allowUniversalAccessFromFileURLs = false
        domStorageEnabled = false
        @Suppress("DEPRECATION")
        databaseEnabled = false
        cacheMode = WebSettings.LOAD_NO_CACHE
        setGeolocationEnabled(false)
        setSupportZoom(false)
        // The phone's font size is the app's to follow (it sends the note's size): the page's pixels are pixels.
        textZoom = 100
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) safeBrowsingEnabled = false
      }
      view.addJavascriptInterface(Host(), "ghostHost")
      view.webViewClient = object : WebViewClient() {
        // Nothing on the page goes anywhere.
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean = true

        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
          if (request.isForMainFrame) {
            Log.w(TAG, "the diagram page did not load: ${error.description}")
            lost()
          }
        }

        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
          Log.w(TAG, "the diagram page's process went")
          lost()
          return true
        }
      }
      web = view
      ready = false
      size(view, 412.0)
      view.loadUrl("file:///android_asset/" + FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(PAGE))
      view
    } catch (error: Throwable) {
      // No web view on this phone, or one being updated under the app.
      Log.w(TAG, "no web view to draw a diagram with", error)
      web = null
      null
    }
  }

  /** The web view has nothing to answer with any more: whoever waits is told, and the next ask makes another. */
  private fun lost() {
    val ask = asking
    close()
    if (ask != null) finish(ask, failed(""))
  }

  private fun close() {
    main.removeCallbacks(rest)
    val view = web ?: return
    web = null
    ready = false
    view.stopLoading()
    view.removeJavascriptInterface("ghostHost")
    view.destroy()
  }

  /**
   * The web view laid out as wide as the app's window and [TALL] high, though it is in no window: the page's width
   * is what a gantt is sized by, and everything a diagram can be is then inside what the page counts as seen.
   */
  private fun size(view: WebView, viewport: Double) {
    val density = activity.resources.displayMetrics.density
    val wide = Math.round(viewport * density).toInt().coerceAtLeast(1)
    val tall = Math.round(TALL * density)
    if (view.width == wide && view.height == tall) return
    view.measure(View.MeasureSpec.makeMeasureSpec(wide, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(tall, View.MeasureSpec.EXACTLY))
    view.layout(0, 0, wide, tall)
  }

  private fun begin(view: WebView, ask: Ask) {
    size(view, ask.viewport)
    // The ask is JSON as Dart wrote it, and JSON is a JavaScript value: nothing of a note is ever run.
    view.evaluateJavascript("ghostDiagram.draw(${ask.json})", null)
  }

  private inner class Host {
    /** What the page says, from the web view's own thread. */
    @JavascriptInterface
    fun said(json: String) {
      main.post { heard(json) }
    }
  }

  private fun heard(json: String) {
    val view = web ?: return
    val said = try {
      JSONObject(json)
    } catch (error: Exception) {
      return
    }
    if (said.optBoolean("ready")) {
      ready = said.optBoolean("mermaid")
      // A page that loaded without Mermaid has nothing to draw with, now or later.
      if (!ready) lost() else asking?.let { begin(view, it) }
      return
    }
    val ask = asking ?: return
    if (said.optInt("n") != ask.n) return
    if (!said.optBoolean("ok")) {
      val why = said.optString("why")
      if (why.isNotEmpty()) Log.w(TAG, "a diagram was not drawn: $why")
      finish(ask, failed(said.optString("failed")))
      return
    }
    if (said.optInt("faces", 1) == 0) Log.w(TAG, "the diagram page has none of the app's fonts")
    // A debug build says what was asked and what the page answered, for a picture to be held to the web app's
    // (tool/diagram_reference.mjs). Never a release: the ask has the note's words in it.
    if (debuggable) Log.d(TAG, "asked ${ask.json} answered $json")
    photograph(view, ask, said, 0)
  }

  /** The page says the diagram is on it: the picture, once the page as painted says so too. */
  private fun photograph(view: WebView, ask: Ask, said: JSONObject, tries: Int) {
    if (asking !== ask || web !== view) return
    try {
      val ratio = said.optDouble("ratio", activity.resources.displayMetrics.density.toDouble())
      // The page's corner wears the picture's number as a colour (page.js): the middle of it, read off the page.
      val corner = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
      Canvas(corner).apply { translate((-MARK / 2 * ratio).toFloat(), (-MARK / 2 * ratio).toFloat()) }.also { view.draw(it) }
      val seen = corner.getPixel(0, 0)
      corner.recycle()
      if (!marked(seen, ask.n)) {
        // Not painted yet: the frame before. Looked at again in a moment, for as long as patience lasts.
        if (tries < LOOKS) {
          main.postDelayed({ photograph(view, ask, said, tries + 1) }, LOOK_MS)
        } else {
          // The page drew it, but no frame of the web view showed it: what a web view off any window may do on a
          // phone, where the emulator it was made on always painted. Said, so a phone that cannot is told apart.
          Log.w(TAG, "a diagram was drawn but never painted: corner ${Integer.toHexString(seen)} after $LOOKS looks")
          finish(ask, failed(""))
        }
        return
      }
      val block = said.getJSONObject("block")
      val origin = said.getJSONObject("origin")
      val picture = said.getJSONObject("picture")
      // The picture's box on the page, out to whole pixels.
      val left = floor(picture.getDouble("x") * ratio)
      val top = floor(picture.getDouble("y") * ratio)
      val wide = ceil((picture.getDouble("x") + picture.getDouble("width")) * ratio) - left
      val tall = ceil((picture.getDouble("y") + picture.getDouble("height")) * ratio) - top
      if (wide < 1 || tall < 1) {
        finish(ask, failed(""))
        return
      }
      // A diagram too big for a picture is made smaller, whole, rather than cut.
      val fit = min(1.0, min(min(SIDE / wide, SIDE / tall), sqrt(PIXELS / (wide * tall))))
      val bitmap = Bitmap.createBitmap(ceil(wide * fit).toInt(), ceil(tall * fit).toInt(), Bitmap.Config.ARGB_8888)
      val answer = hashMapOf<String, Any>(
        "blockWidth" to block.getDouble("width"),
        "blockHeight" to block.getDouble("height"),
        "x" to left / ratio - origin.getDouble("x"),
        "y" to top / ratio - origin.getDouble("y"),
        "width" to wide / ratio,
        "height" to tall / ratio,
        "scale" to ratio * fit,
      )
      strip(view, ask, bitmap, fit.toFloat(), left.toFloat(), top.toFloat(), 0, answer, 0L)
    } catch (error: Throwable) {
      // A bitmap there was no memory for, a page that answered with something else.
      Log.w(TAG, "a diagram's picture was not taken", error)
      finish(ask, failed(""))
    }
  }

  /**
   * The picture, a strip of rows at a time, each its own turn of the main thread. Drawing a web view into a bitmap
   * holds the main thread until the page's process has painted it, and that thread is the app's own: a big diagram
   * drawn in one go is a frame of the note, or several, that is never drawn. A strip is a few milliseconds, and the
   * note's frames go between them. The page does not change under it: it is asked nothing more until this is done.
   */
  private fun strip(view: WebView, ask: Ask, bitmap: Bitmap, fit: Float, left: Float, top: Float, from: Int, answer: HashMap<String, Any>, spent: Long) {
    if (asking !== ask || web !== view) {
      bitmap.recycle()
      return
    }
    val began = System.nanoTime()
    val to = min(bitmap.height, from + (STRIP_PIXELS / bitmap.width).coerceAtLeast(16))
    try {
      val canvas = Canvas(bitmap)
      canvas.clipRect(0, from, bitmap.width, to)
      canvas.scale(fit, fit)
      canvas.translate(-left, -top)
      view.draw(canvas)
    } catch (error: Throwable) {
      Log.w(TAG, "a diagram's picture was not taken", error)
      bitmap.recycle()
      finish(ask, failed(""))
      return
    }
    val took = spent + (System.nanoTime() - began)
    if (to < bitmap.height) {
      main.post { strip(view, ask, bitmap, fit, left, top, to, answer, took) }
      return
    }
    if (debuggable) Log.d(TAG, "drew ${bitmap.width} x ${bitmap.height} in ${took / 1_000_000.0} ms on the main thread")
    // Off the main thread: a PNG of a big diagram is tens of milliseconds.
    Thread {
      val png = try {
        ByteArrayOutputStream(64 * 1024).also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
      } catch (error: Throwable) {
        null
      }
      bitmap.recycle()
      main.post {
        if (png == null) finish(ask, failed("")) else finish(ask, answer.also { it["png"] = png })
      }
    }.start()
  }

  /**
   * Whether a pixel of the page's corner says picture `n` is on the page (page.js `markOf`): opaque, and n's last
   * three digits in base five as a level of red, green and blue each, near enough.
   */
  private fun marked(pixel: Int, n: Int): Boolean {
    val k = ((n % 125) + 125) % 125
    fun near(seen: Int, digit: Int) = kotlin.math.abs(seen - LEVELS[digit % 5]) <= 24
    return Color.alpha(pixel) == 255 && near(Color.red(pixel), k) && near(Color.green(pixel), k / 5) && near(Color.blue(pixel), k / 25)
  }

  private fun finish(ask: Ask, answer: Map<String, Any>, then: Boolean = true) {
    if (asking !== ask) return
    asking = null
    main.removeCallbacks(giveUp)
    ask.result.success(answer)
    if (!then) return
    // Kept for the next diagram, and let go when none has come for a while: Mermaid is a few megabytes of page.
    main.postDelayed(rest, REST_MS)
    next()
  }

  private fun failed(said: String): Map<String, Any> = hashMapOf("failed" to said)

  private companion object {
    const val CHANNEL = "ghost_md/diagrams"
    const val TAG = "GhostDiagram"
    const val PAGE = "assets/diagrams/index.html"

    /** The page's corner mark, across, in its own pixels (page.css `#mark`). */
    const val MARK = 16.0

    /** The levels a mark's red, green and blue are each one of (page.js `markOf`). */
    val LEVELS = intArrayOf(0, 64, 128, 192, 255)

    /** How tall the web view is laid out, in the page's pixels. */
    const val TALL = 8000L

    /** The most a picture is on a side, and in all, in device pixels. */
    const val SIDE = 8192.0
    const val PIXELS = 12_000_000.0

    /** How much of a picture is drawn in one turn of the main thread, in pixels. */
    const val STRIP_PIXELS = 160_000

    /** How long one diagram may take, the page's first load with it. */
    const val PATIENCE_MS = 20_000L

    /** How often, and how many times, the page is looked at for its mark. */
    const val LOOK_MS = 16L
    const val LOOKS = 120

    /** How long the web view is kept with nothing to draw. */
    const val REST_MS = 180_000L
  }
}
