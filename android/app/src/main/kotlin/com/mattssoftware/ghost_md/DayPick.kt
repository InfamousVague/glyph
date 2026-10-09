package com.mattssoftware.ghost_md

import android.app.Activity
import android.app.DatePickerDialog
import android.content.res.Configuration
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar
import java.util.Locale

/**
 * A day picked from the phone's own calendar (lib/core/phone_day.dart, the phone's half of `ghost_md/day`): what a
 * hidden `<input type="date">` and its `showPicker()` were to the web app's Pick a date (`editor/fieldMenu.ts`
 * `pickDay`), where the WebView answered with Android's date dialog.
 *
 * - `pick {current}` -> the day chosen as `YYYY-MM-DD`, or null when the dialog was left without one. `current` is
 *   the day the dialog opens on, in the same form; today where it is missing or is not a day.
 *
 * The dialog is the platform's `DatePickerDialog` in the phone's own theme, dark where the phone is. It has no
 * Clear, which the WebView's had: a field's own cross clears it.
 */
class DayPick(private val activity: Activity) {
  private var open: DatePickerDialog? = null

  fun register(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "pick" -> pick(call.argument<String>("current"), result)
        else -> result.notImplemented()
      }
    }
  }

  private fun pick(current: String?, result: MethodChannel.Result) {
    // One calendar at a time: a second ask puts the first away, unanswered.
    open?.dismiss()
    val start = Calendar.getInstance()
    DAY.matchEntire(current ?: "")?.destructured?.let { (year, month, day) ->
      start.set(year.toInt(), month.toInt() - 1, day.toInt())
    }
    var answered = false
    // The phone's own calendar, in the phone's light or dark: the activity's theme is Flutter's bare window, under
    // which the dialog is the oldest one Android still carries (three spinners).
    val night = (activity.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    val theme = if (night) android.R.style.Theme_DeviceDefault_Dialog_Alert else android.R.style.Theme_DeviceDefault_Light_Dialog_Alert
    val dialog = DatePickerDialog(
      activity,
      theme,
      { _, year, month, day ->
        if (!answered) {
          answered = true
          result.success(String.format(Locale.US, "%04d-%02d-%02d", year, month + 1, day))
        }
      },
      start.get(Calendar.YEAR),
      start.get(Calendar.MONTH),
      start.get(Calendar.DAY_OF_MONTH),
    )
    // Cancel, Back and a tap outside all end here; a day set has already been answered.
    dialog.setOnDismissListener {
      if (open === dialog) open = null
      if (!answered) {
        answered = true
        result.success(null)
      }
    }
    open = dialog
    dialog.show()
  }

  companion object {
    const val CHANNEL = "ghost_md/day"
    private val DAY = Regex("""(\d{4})-(\d{2})-(\d{2})""")
  }
}
