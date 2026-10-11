package com.mattssoftware.ghost_md

import android.icu.text.DateFormat
import android.icu.text.DateFormatSymbols
import android.icu.text.DateTimePatternGenerator
import android.icu.text.NumberingSystem
import android.icu.text.SimpleDateFormat
import android.icu.util.Calendar
import android.icu.util.ULocale
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * A date's words in the phone's own language: the phone's half of lib/core/phone_dates.dart (`ghost_md/dates`).
 *
 * Ghost.md's page asks its WebView for every date a person reads (`new Intl.DateTimeFormat(undefined, …)`), which
 * answers from the CLDR its ICU carries, in the phone's language. This app draws its own text and has no `Intl`,
 * so it asks Android's ICU (`android.icu`, the same library with the phone's own CLDR) for what a date is written
 * from, once, and writes the dates itself (lib/core/locale_dates.dart).
 *
 * - `words {skeletons: {form: skeleton}, locale?}` -> for the phone's locale, or the one named by its tag:
 *   - `locale`: its tag;
 *   - `patterns`: for each form, the pattern ICU's generator makes of its skeleton, the hour's length kept
 *     (`MATCH_HOUR_FIELD_LENGTH`, as V8 asks: `{hour: '2-digit'}` is "04", `{hour: 'numeric'}` is "4"); and
 *     `medShort`, the locale's medium date and short time together (`dateStyle: 'medium', timeStyle: 'short'`);
 *   - `months`, `shortMonths`, `monthsAlone`, `shortMonthsAlone`: January to December, as a date wears them and
 *     as they stand alone; `weekdays`, `shortWeekdays`, `weekdaysAlone`, `shortWeekdaysAlone`: Monday to Sunday;
 *   - `am`, `pm`; `digits`: the ten figures, nought first;
 *   - `calendar`, the calendar a browser writes the locale in ("gregorian", "buddhist", "persian"), `era`, the name of the era now,
 *     and `yearOffset`, what that calendar's year is ahead of the Gregorian one where the months are the same
 *     (543 in the Buddhist calendar). A calendar with months of its own is answered in the Gregorian one.
 *
 * Worked out off the main thread: a pattern generator reads the locale's data the first time it is asked, and the
 * app is starting.
 */
class Dates {
  private val worker = Executors.newSingleThreadExecutor()
  private val main = Handler(Looper.getMainLooper())

  fun register(messenger: BinaryMessenger) {
    MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "words" -> {
          val skeletons = call.argument<Map<String, String>>("skeletons") ?: emptyMap()
          val tag = call.argument<String>("locale")
          worker.execute {
            val answer = try {
              words(skeletons, tag)
            } catch (failure: Exception) {
              null
            }
            main.post { result.success(answer) }
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  companion object {
    const val CHANNEL = "ghost_md/dates"

    /** CLDR's `calendarPreferenceData`, where a region's first calendar is not the Gregorian one. */
    private val REGIONS = mapOf("TH" to "buddhist", "IR" to "persian", "AF" to "persian")

    /** The calendars whose months are the Gregorian ones, and what their year is ahead by. */
    private val OFFSETS = mapOf("buddhist" to 543, "roc" to -1911)

    fun words(skeletons: Map<String, String>, tag: String?): Map<String, Any?> {
      val asked = if (tag.isNullOrEmpty()) ULocale.getDefault(ULocale.Category.FORMAT) else ULocale.forLanguageTag(tag)
      // The calendar a browser's `Intl` uses for the locale: the one it names (`-u-ca-`), else the first CLDR gives
      // its region. Android's ICU does not carry that list (it answers Gregorian for Thailand, from
      // `Calendar.getInstance` and from `getKeywordValuesForLocale` alike), and the list is three regions long.
      val own = asked.getUnicodeLocaleType("ca")?.let { if (it == "gregory") "gregorian" else it }
        ?: REGIONS[ULocale.addLikelySubtags(asked).country]
        ?: "gregorian"
      val offset = OFFSETS[own]
      // The locale's own calendar where its months are these months; the Gregorian one otherwise.
      val calendar = if (own == "gregorian" || offset != null) own else "gregorian"
      val locale = ULocale.Builder().setLocale(asked).setUnicodeLocaleKeyword("ca", if (calendar == "gregorian") "gregory" else calendar).build()

      val generator = DateTimePatternGenerator.getInstance(locale)
      val patterns = HashMap<String, String>()
      for ((form, skeleton) in skeletons) {
        patterns[form] = generator.getBestPattern(skeleton, DateTimePatternGenerator.MATCH_HOUR_FIELD_LENGTH)
      }
      (DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, locale) as? SimpleDateFormat)?.let { patterns["medShort"] = it.toPattern() }

      val symbols = DateFormatSymbols(Calendar.getInstance(locale), locale)
      fun months(context: Int, width: Int) = symbols.getMonths(context, width).take(12)
      // ICU's week starts its list on Sunday, at 1: Monday to Sunday here.
      fun days(context: Int, width: Int) = symbols.getWeekdays(context, width).let { all -> (2..7).map { all[it] } + all[1] }
      val meridiems = symbols.amPmStrings
      val eras = symbols.eras
      val now = Calendar.getInstance(locale).get(Calendar.ERA)

      return mapOf(
        "locale" to asked.toLanguageTag(),
        "calendar" to own,
        "patterns" to patterns,
        "months" to months(DateFormatSymbols.FORMAT, DateFormatSymbols.WIDE),
        "shortMonths" to months(DateFormatSymbols.FORMAT, DateFormatSymbols.ABBREVIATED),
        "monthsAlone" to months(DateFormatSymbols.STANDALONE, DateFormatSymbols.WIDE),
        "shortMonthsAlone" to months(DateFormatSymbols.STANDALONE, DateFormatSymbols.ABBREVIATED),
        "weekdays" to days(DateFormatSymbols.FORMAT, DateFormatSymbols.WIDE),
        "shortWeekdays" to days(DateFormatSymbols.FORMAT, DateFormatSymbols.ABBREVIATED),
        "weekdaysAlone" to days(DateFormatSymbols.STANDALONE, DateFormatSymbols.WIDE),
        "shortWeekdaysAlone" to days(DateFormatSymbols.STANDALONE, DateFormatSymbols.ABBREVIATED),
        "am" to meridiems.getOrElse(0) { "AM" },
        "pm" to meridiems.getOrElse(1) { "PM" },
        "digits" to (NumberingSystem.getInstance(locale).takeIf { !it.isAlgorithmic }?.description ?: "0123456789"),
        "era" to eras.getOrElse(now) { "" },
        "yearOffset" to (offset ?: 0),
      )
    }
  }
}
