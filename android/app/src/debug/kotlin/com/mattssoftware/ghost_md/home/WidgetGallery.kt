package com.mattssoftware.ghost_md.home

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * The widgets drawn at each size, side by side, for their pictures (docs/WIDGETS_ANDROID.md, "Pictures"): debug builds
 * only. Each widget's RemoteViews, made exactly as a launcher is handed them (WidgetViews.build) for the size the
 * Pixel launcher gives a placed widget of so many cells, applied here into a box of that size on a wallpaper's grey,
 * so every size of a widget is one picture and none needs placing by hand.
 *
 *   adb shell am start -n <app id>/com.mattssoftware.ghost_md.home.WidgetGallery --es kind NOTE --es sizes 74x82,159x181 --ei id 9001
 */
class WidgetGallery : Activity() {
  override fun onCreate(saved: Bundle?) {
    super.onCreate(saved)
    val kind = WidgetKind.valueOf(intent.getStringExtra("kind") ?: "VOICE")
    val id = intent.getIntExtra("id", 9001)
    val sizes = (intent.getStringExtra("sizes") ?: "74x82,159x82,329x82,159x181,329x181").split(',').map { it.split('x').let { (w, h) -> w.toInt() to h.toInt() } }
    val density = resources.displayMetrics.density
    val flow = Flow(this, (8 * density).toInt())
    flow.setBackgroundColor(Color.rgb(0x2B, 0x33, 0x44))
    flow.setPadding((8 * density).toInt(), (52 * density).toInt(), (8 * density).toInt(), (8 * density).toInt())
    for ((wide, tall) in sizes) {
      val views = WidgetViews.build(this, kind, id, wide, tall)
      val box = FrameLayout(this)
      box.addView(views.apply(this, box))
      box.layoutParams = ViewGroup.LayoutParams((wide * density).toInt(), (tall * density).toInt())
      flow.addView(box)
    }
    val label = TextView(this).apply {
      text = "${kind.name} " + sizes.joinToString("  ") { "${it.first}×${it.second}" }
      setTextColor(Color.argb(0x99, 0xFF, 0xFF, 0xFF))
      textSize = 10f
      setPadding((8 * density).toInt(), (32 * density).toInt(), 0, 0)
    }
    val frame = FrameLayout(this).apply {
      addView(ScrollView(this@WidgetGallery).apply { addView(flow) })
      addView(label)
    }
    setContentView(frame)
  }

  /** Its children left to right, onto the next row where one does not fit. */
  private class Flow(context: Context, private val gap: Int) : ViewGroup(context) {
    override fun onMeasure(widthSpec: Int, heightSpec: Int) {
      val width = MeasureSpec.getSize(widthSpec)
      var x = paddingLeft
      var y = paddingTop
      var row = 0
      for (child in (0 until childCount).map(::getChildAt)) {
        val params = child.layoutParams
        child.measure(MeasureSpec.makeMeasureSpec(params.width, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(params.height, MeasureSpec.EXACTLY))
        if (x + child.measuredWidth > width - paddingRight && x > paddingLeft) {
          x = paddingLeft
          y += row + gap
          row = 0
        }
        x += child.measuredWidth + gap
        row = maxOf(row, child.measuredHeight)
      }
      setMeasuredDimension(width, y + row + paddingBottom)
    }

    override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
      var x = paddingLeft
      var y = paddingTop
      var row = 0
      for (child in (0 until childCount).map(::getChildAt).filter { it.visibility != View.GONE }) {
        if (x + child.measuredWidth > (r - l) - paddingRight && x > paddingLeft) {
          x = paddingLeft
          y += row + gap
          row = 0
        }
        child.layout(x, y, x + child.measuredWidth, y + child.measuredHeight)
        x += child.measuredWidth + gap
        row = maxOf(row, child.measuredHeight)
      }
    }
  }
}
