package com.mattssoftware.ghost_md

import android.icu.text.DateFormat
import android.icu.text.DateFormatSymbols
import android.icu.text.DateTimePatternGenerator
import android.icu.text.NumberingSystem
import android.icu.text.SimpleDateFormat
import android.icu.util.Calendar
import android.icu.util.ULocale
import android.os.Build
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
 *     (543 in the Buddhist calendar);
 *   - for the Persian calendar, whose months are its own: everything above is that calendar's (its patterns, its
 *     twelve months' names, its era), with `firstYear` and `monthStarts`, the day each of its months begins on from
 *     the first month of `firstYear`, in days since 1 January 1970, and one more for where the table ends: the
 *     phone's own reckoning of the calendar, which the app reads a date's year, month and day from. Any other
 *     calendar with months of its own is answered in the Gregorian one;
 *   - `periods`, where a pattern names the part of the day more finely than two meridiems (`B`, as Taiwan's
 *     medium date and time does): for each such run of the letter as a pattern has it ("B"), `hours`, the part's
 *     name at each hour of the day, and `noon`, its name at twelve exactly.
 *
 * - `zone` -> the phone's own time zone by its name, "America/New_York" (the page's
 *   `Intl.DateTimeFormat().resolvedOptions().timeZone`).
 * - `offsets {zones, from, to}` -> for each zone the phone's time-zone database knows, a list: its offset from UTC
 *   in minutes at `from`, then pairs, the minute a change of it takes hold and the offset from then on, up to
 *   `to` (minutes since 1970). What the page asks `Intl` for a moment at a time (`timeZoneName: 'shortOffset'`),
 *   for a blank's "what time is it in Tokyo" (lib/core/phone_zones.dart).
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
        "zone" -> result.success(java.util.TimeZone.getDefault().id)
        "offsets" -> {
          val zones = call.argument<List<String>>("zones") ?: emptyList()
          val from = (call.argument<Number>("from") ?: 0).toLong()
          val to = (call.argument<Number>("to") ?: 0).toLong()
          worker.execute {
            val answer = try {
              offsets(zones, from, to)
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

    /** The calendars with months of their own that the app writes a date in, from a table of where each begins. */
    private val OWN_MONTHS = setOf("persian")

    /** The table's first year and how many it has: 1200 to 1599 of the Persian calendar is 1821 to 2221. */
    private const val FIRST_YEAR = 1200
    private const val YEARS = 400
    private const val DAY = 86_400_000L

    /** The day each month of `years` years from `first` begins on, by `locale`'s own calendar, and the day after the last. */
    private fun monthStarts(locale: ULocale, first: Int, years: Int): List<Int> {
      val calendar = Calendar.getInstance(android.icu.util.TimeZone.GMT_ZONE, locale)
      val out = ArrayList<Int>(years * 12 + 1)
      for (index in 0..years * 12) {
        calendar.clear()
        calendar.set(Calendar.EXTENDED_YEAR, first + index / 12)
        calendar.set(Calendar.MONTH, index % 12)
        calendar.set(Calendar.DAY_OF_MONTH, 1)
        out.add(Math.floorDiv(calendar.timeInMillis, DAY).toInt())
      }
      return out
    }

    /** Each run of `letter` in `pattern` that is a field and not quoted words: "B", "BBBB". */
    internal fun fieldsOf(pattern: String, letter: Char): Set<String> {
      val out = HashSet<String>()
      var quoted = false
      var at = 0
      while (at < pattern.length) {
        val unit = pattern[at]
        if (unit == '\'') {
          // `''` is an apostrophe, in or out of quotes.
          if (at + 1 < pattern.length && pattern[at + 1] == '\'') at += 1 else quoted = !quoted
          at += 1
        } else if (!quoted && unit == letter) {
          var end = at
          while (end < pattern.length && pattern[end] == letter) end += 1
          out.add(pattern.substring(at, end))
          at = end
        } else {
          at += 1
        }
      }
      return out
    }

    /**
     * The part of the day `run` (a pattern's `B`s) names at each hour, and at noon exactly, as the phone's own
     * formatter writes it: an hour's part is asked at half past it, since on the hour of twelve a locale may say
     * "noon"; and noon with no minutes in the pattern, which is how ICU reads twelve o'clock. Null on an Android
     * whose ICU does not know the letter.
     */
    private fun periods(run: String, locale: ULocale): Map<String, Any>? = try {
      val hourly = SimpleDateFormat("$run'|'m", locale).apply { timeZone = android.icu.util.TimeZone.GMT_ZONE }
      val exact = SimpleDateFormat(run, locale).apply { timeZone = android.icu.util.TimeZone.GMT_ZONE }
      mapOf(
        "hours" to (0..23).map { hour -> hourly.format(java.util.Date(hour * 3_600_000L + 1_800_000L)).substringBefore('|') },
        "noon" to exact.format(java.util.Date(12 * 3_600_000L)),
      )
    } catch (unknown: Exception) {
      // No names: the app writes the two meridiems there, as it did.
      null
    }

    /**
     * Each zone's offset at `from` and every change of it before `to`, in minutes; a zone not known is left out.
     * By the phone's time-zone rules (`java.time`, Android 8 and after); on an older Android, by asking its
     * offset a day at a time and closing in on each change to the minute.
     */
    fun offsets(zones: List<String>, from: Long, to: Long): Map<String, List<Int>> {
      val out = HashMap<String, List<Int>>()
      for (id in zones) {
        val table = ArrayList<Int>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          val rules = try {
            java.time.ZoneId.of(id).rules
          } catch (unknown: Exception) {
            continue
          }
          var at = java.time.Instant.ofEpochSecond(from * 60L)
          table.add(rules.getOffset(at).totalSeconds / 60)
          while (true) {
            val change = rules.nextTransition(at) ?: break
            if (change.instant.epochSecond >= to * 60L) break
            table.add((change.instant.epochSecond / 60L).toInt())
            table.add(change.offsetAfter.totalSeconds / 60)
            at = change.instant
          }
        } else {
          val zone = java.util.TimeZone.getTimeZone(id)
          // A name it does not know is answered as GMT.
          if (zone.id != id) continue
          val minute = 60_000L
          var at = from * minute
          var offset = zone.getOffset(at) / 60_000
          table.add(offset)
          while (at < to * minute) {
            val next = minOf(at + 1440L * minute, to * minute)
            val then = zone.getOffset(next) / 60_000
            if (then != offset) {
              var before = at
              var after = next
              while (after - before > minute) {
                val middle = before + (after - before) / 2 / minute * minute
                if (zone.getOffset(middle) / 60_000 == offset) before = middle else after = middle
              }
              table.add((after / minute).toInt())
              table.add(then)
              offset = then
            }
            at = next
          }
        }
        out[id] = table
      }
      return out
    }

    fun words(skeletons: Map<String, String>, tag: String?): Map<String, Any?> {
      val asked = if (tag.isNullOrEmpty()) ULocale.getDefault(ULocale.Category.FORMAT) else ULocale.forLanguageTag(tag)
      // The calendar a browser's `Intl` uses for the locale: the one it names (`-u-ca-`), else the first CLDR gives
      // its region. Android's ICU does not carry that list (it answers Gregorian for Thailand, from
      // `Calendar.getInstance` and from `getKeywordValuesForLocale` alike), and the list is three regions long.
      val own = asked.getUnicodeLocaleType("ca")?.let { if (it == "gregory") "gregorian" else it }
        ?: REGIONS[ULocale.addLikelySubtags(asked).country]
        ?: "gregorian"
      val offset = OFFSETS[own]
      // Where a calendar with months of its own begins each of them, by the phone's reckoning. Worked out before
      // anything is answered in that calendar: without the table the app could not say which of its months a
      // day is in, and the Gregorian calendar is answered instead, as before the table.
      val starts = if (own in OWN_MONTHS) {
        try {
          monthStarts(ULocale.Builder().setLocale(asked).setUnicodeLocaleKeyword("ca", own).build(), FIRST_YEAR, YEARS)
        } catch (failure: Exception) {
          null
        }
      } else {
        null
      }
      // The locale's own calendar where its months are these months, or where the app is told where its own months
      // begin; the Gregorian one otherwise.
      val calendar = if (own == "gregorian" || offset != null || starts != null) own else "gregorian"
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
      val finer = HashMap<String, Any>()
      for (run in patterns.values.flatMap { fieldsOf(it, 'B') }.toSet()) {
        periods(run, locale)?.let { finer[run] = it }
      }

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
        "periods" to finer,
        "firstYear" to (if (starts != null) FIRST_YEAR else null),
        "monthStarts" to starts,
      )
    }
  }
}
