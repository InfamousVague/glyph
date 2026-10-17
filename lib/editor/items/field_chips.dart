/// What a field on a to-do looks like as a chip: its words, its icon, its colour and what a screen reader hears.
/// Ports `src/app/editor/fieldChips.ts`. The grammar is `lib/core/task_fields.dart`'s; this says only how a field
/// it found is shown, and is shared by the two places that show one: a note's line (`task_fields.dart`) and a
/// board's card, so a due date reads "Tomorrow" on both and is red on both once it has passed.
///
///     📅 2026-10-03   "Sat 3 Oct", "Today", "Tomorrow", "Yesterday"; the year only when it is not this one. Red
///                     once it has passed and the box is not ticked, amber on the day, quiet once it is ticked
///     🛫 ⏳ ✅ ➕ ❌     the other days, quieter, each with its word: "Starts", "Scheduled", "Done", "Added"…
///     ⏫               a compact mark, the chevrons Jira draws, with the priority's name for a screen reader
///     @sam             a person: their initial in a ring, and the name as written; once Settings › Contacts
///                     matches them to a contact (lib/integrations/contacts), the contact's picture in the ring,
///                     or their initials where they have none
///     🔁 every week    a small repeat mark and its words
///     [effort:: 3]     the key quiet, the value as written
///
/// What differs:
/// - `chipElement` is [FieldChip], a widget, and the stylesheet (`fieldChipTheme`) is its build: every length is
///   the rule's, cited beside it, and the chip's place on the line (an inline block with a line-height of 1.35) is
///   worked out as Blink works it out, from the face's ascent and descent to whole pixels.
/// - A day is named with `Intl.DateTimeFormat` on the page, in the device's own language. Here it is named in
///   English, as the phone writes a date once it has said which way (core/locale_dates.dart, the page's own
///   answers: "Sat, Oct 3" on an American phone, "Sat, 3 Oct" on a British one). A locale named, which only a test
///   does, and a phone that has not said are written as they were before there was a table: the American way where
///   the region is the United States and the British way as the web's own tests pin it ("Sat 3 Oct", from Node's
///   newer CLDR, which dropped that comma) elsewhere. Other languages wait for the app's own.
library;

import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/days.dart';
import '../../core/locale_dates.dart';
import '../../core/task_fields.dart';
import '../../integrations/contacts/contact_book.dart' show PhoneContact;
import '../../integrations/contacts/contacts.dart';
import '../../reminders/remind_choices.dart' show clockWords;
import '../../reminders/reminder_syntax.dart' show readReminderTime;
import '../looks/look.dart' show FaceMetrics, lineBoxHeight;
import '../view/line.dart' show EditorRunScope;
import 'inline_box.dart';

/// Which page of the press-and-hold menu a tap on a chip opens; null, a tap edits it.
enum FieldMenu { date, priority, person, remind }

/// How a chip is coloured: a day by when it is, a priority by its rank (its name), and the rest plain or quiet.
typedef ChipTone = String;

class ChipLook {
  const ChipLook({required this.text, required this.icon, required this.tone, required this.label, required this.menu, required this.key, this.initial, this.name});

  /// What it says, after its icon or its initial: '' for a priority, which is its mark alone.
  final String text;
  final LucideIcon? icon;
  final ChipTone tone;

  /// What a screen reader hears: "Due Friday 3 October, overdue".
  final String label;

  /// Which menu a tap opens, and for which field.
  final FieldMenu? menu;

  /// The field the menu changes: a day's key, `priority`, or the person as written.
  final String key;

  /// A person's initial, in its ring.
  final String? initial;

  /// A named field's key, quiet before its value.
  final String? name;

  @override
  String toString() => 'ChipLook("$text", ${icon?.name}, $tone, "$label", ${menu?.name}, $key, $initial, $name)';
}

/// The days a menu can set from a chip, by their key; the rest edit as written.
const List<String> _dated = <String>['due', 'start', 'scheduled'];

/// The word before a day that is not the due day, so the chips say which day they are.
const Map<String, String> _dayWord = <String, String>{'start': 'Starts', 'scheduled': 'Scheduled', 'done': 'Done', 'created': 'Added', 'cancelled': 'Cancelled'};

/// Dataview's names for the days, read as the emoji's are.
const Map<String, String> _dataviewDays = <String, String>{'due': 'due', 'start': 'start', 'scheduled': 'scheduled', 'created': 'created', 'completion': 'done', 'cancelled': 'cancelled'};

/// Each priority's mark: Jira's chevrons, two up for the most urgent and two down for the least. The kit's icons,
/// never the emoji they are written with.
const Map<String, LucideIcon> priorityIcon = <String, LucideIcon>{'highest': Lucide.chevronsUp, 'high': Lucide.chevronUp, 'medium': Lucide.equal, 'low': Lucide.chevronDown, 'lowest': Lucide.chevronsDown};

const List<String> _weekdays = <String>['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const List<String> _months = <String>['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// Whether `locale` writes a day the American way; the device's own where none is given.
bool _american(String? locale) {
  final said = locale ?? ui.PlatformDispatcher.instance.locale.toLanguageTag();
  return said.toUpperCase().endsWith('-US') || said == 'en';
}

String _named(DateTime at, {required bool long, required bool year, String? locale}) {
  // The phone's own words where no locale is named and the phone has said its own.
  if (locale == null) {
    final told = toldDate(at, long ? (year ? DateForm.yMMMMEEEEd : DateForm.MMMMEEEEd) : (year ? DateForm.yMMMEd : DateForm.MMMEd));
    if (told != null) return told;
  }
  final weekday = _weekdays[at.weekday - 1], month = _months[at.month - 1];
  final w = long ? weekday : weekday.substring(0, 3);
  // September is "Sept" in British short dates, as the browser writes it.
  final m = long ? month : (month == 'September' && !_american(locale) ? 'Sept' : month.substring(0, 3));
  if (_american(locale)) return '$w, $m ${at.day}${year ? ', ${at.year}' : ''}';
  // The British way has a comma after the weekday once the year is said: "Fri, 15 Jan 2027".
  return year ? '$w, ${at.day} $m ${at.year}' : '$w ${at.day} $m';
}

/// A day as a chip says it, counted from `today`: "Today", "Tomorrow", "Yesterday", else its weekday, day and
/// month, "Sat 3 Oct", and the year only when it is not this one. Words that are not a day come back as they are.
String dayLabel(String day, String today, [String? locale]) {
  final gap = daysBetween(today, day);
  final at = dateOfDay(day);
  if (gap == null || at == null) return day;
  if (gap == 0) return 'Today';
  if (gap == 1) return 'Tomorrow';
  if (gap == -1) return 'Yesterday';
  return _named(at, long: false, year: day.substring(0, 4) != today.substring(0, 4), locale: locale);
}

/// A day said in full for a screen reader: "Saturday 3 October", with the year when it is not this one.
String daySaid(String day, String today, [String? locale]) {
  final at = dateOfDay(day);
  if (at == null) return day;
  return _named(at, long: true, year: day.substring(0, 4) != today.substring(0, 4), locale: locale);
}

/// Where a due day stands: past and not done is overdue, on the day is today, and a ticked box quiets it whatever
/// the day, since a finished thing is not late.
String dueTone(String day, String today, bool done) {
  if (done) return 'done';
  final gap = daysBetween(today, day);
  if (gap == null) return 'plain';
  return gap < 0 ? 'overdue' : (gap == 0 ? 'today' : 'plain');
}

final RegExp _dashes = RegExp(r'[-_]+');

/// A person's name as a chip shows it: as written, its dashes the spaces they stand for.
String personShown(String name) => name.replaceAll(_dashes, ' ').trim();

final RegExp _relative = RegExp(r'^(?:Today|Tomorrow|Yesterday)$');

/// A day field's look: due, or another day with its word.
ChipLook _dayLook(String key, String day, String today, bool done, String? locale) {
  final named = dayLabel(day, today, locale);
  final said = daySaid(day, today, locale);
  final menu = _dated.contains(key) ? FieldMenu.date : null;
  if (key == 'due') {
    final tone = dueTone(day, today, done);
    return ChipLook(text: named, icon: Lucide.calendarDays, tone: tone, label: 'Due $said${tone == 'overdue' ? ', overdue' : (tone == 'today' ? ', today' : '')}', menu: menu, key: key);
  }
  final word = _dayWord[key]!;
  // "Starts tomorrow", "Done yesterday": a relative day after a word reads as part of the sentence.
  final shown = _relative.hasMatch(named) ? named.toLowerCase() : named;
  return ChipLook(text: '$word $shown', icon: null, tone: done ? 'done' : 'quiet', label: '$word $said', menu: menu, key: key);
}

/// How `span` is drawn, or null where it is drawn as written: a day the calendar has not got (`2026-02-30`), a
/// priority or a day by name that does not read as one, and Tasks' ids. `done` is whether the item is finished,
/// which quiets every chip on it.
ChipLook? chipLook(FieldSpan span, {required String today, required bool done, String? locale}) {
  if (span.kind == FieldKind.date) return isIsoDay(span.value) ? _dayLook(span.key, span.value, today, done, locale) : null;
  if (span.kind == FieldKind.priority || (span.kind == FieldKind.inline && span.key == 'priority')) {
    final priority = priorityOf(span.value);
    if (priority == null) return null;
    return ChipLook(text: '', icon: priorityIcon[priority.name], tone: done ? 'done' : priority.name, label: '${priority.label} priority', menu: FieldMenu.priority, key: 'priority');
  }
  if (span.kind == FieldKind.person) {
    final shown = personShown(span.value);
    return ChipLook(text: shown, icon: null, tone: done ? 'done' : 'plain', label: 'Assigned to $shown', menu: FieldMenu.person, key: span.value, initial: shown.isEmpty ? '' : shown.substring(0, 1).toUpperCase());
  }
  if (span.kind == FieldKind.recurs) return ChipLook(text: span.value, icon: Lucide.repeat, tone: done ? 'done' : 'quiet', label: 'Repeats ${span.value}', menu: null, key: 'recurs');
  if (span.kind == FieldKind.tasks && span.key == 'reminder') {
    // A reminder, `⏰ 2026-10-03 09:00` (lib/reminders): its day as a due day says it, and its time on the clock.
    final at = readReminderTime(span.value);
    if (at == null) return null;
    final time = clockWords(at.hour, at.minute);
    return ChipLook(text: '${dayLabel(at.day, today, locale)} $time', icon: Lucide.alarmClock, tone: done ? 'done' : 'quiet', label: 'Reminder ${daySaid(at.day, today, locale)} at $time', menu: FieldMenu.remind, key: 'reminder');
  }
  if (span.kind == FieldKind.inline) {
    // Dataview's `[due:: 2026-10-03]` is the due day, written its way: drawn as one, and changed in its own form.
    final day = _dataviewDays[span.key];
    if (day != null && isIsoDay(span.value)) return _dayLook(day, span.value, today, done, locale);
    return ChipLook(text: span.value, icon: null, tone: done ? 'done' : 'quiet', label: '${span.key}: ${span.value}', menu: null, key: span.key, name: span.key);
  }
  return null;
}

/// Whether two looks draw the same chip, so the widget's element is kept.
bool sameLook(ChipLook a, ChipLook b) => a.text == b.text && identical(a.icon, b.icon) && a.tone == b.tone && a.label == b.label && a.menu == b.menu && a.key == b.key && a.initial == b.initial && a.name == b.name;

/// A chip: its icon or its initial, a named field's key, and its words. The same on a line and on a card.
///
/// The look is `fieldChipTheme`'s: a tag's size and weight, so a line of them reads as one line of words. A day
/// in the red ramp once it has passed and in amber on the day; a priority's mark in red, amber or blue by its
/// rank, the least in the third ink; a person's initial in a purple ring; and the rest in the third ink, unfilled,
/// quieter than a tag. A finished item's chips all go to the third ink.
class FieldChip extends StatelessWidget {
  const FieldChip(this.look, {super.key, this.onTap, this.lineHeight = 1.35});

  final ChipLook look;

  /// The chip's own line, against its type: the stylesheet's 1.35 on a line of the note. A board's card draws its
  /// chips as buttons, whose `font: inherit` takes the editor's 1.6 back (measured on the page: 19.44 at 12.15).
  final double lineHeight;

  /// A tap on a chip that has a menu, with the chip's box on the screen.
  final void Function(Rect box)? onTap;

  /// A person's chip follows Settings › Contacts: matched, it wears the contact's face.
  @override
  Widget build(BuildContext context) {
    if (look.menu != FieldMenu.person || look.initial == null) return _chip(context, null, null);
    final contacts = phoneContacts;
    return ListenableBuilder(
      listenable: contacts,
      builder: (context, _) {
        final contact = contacts.contactOf(look.key);
        return _chip(context, contact, contact == null ? null : contacts.photoOf(contact));
      },
    );
  }

  Widget _chip(BuildContext context, PhoneContact? contact, Uint8List? photo) {
    final t = context.tokens;
    final run = EditorRunScope.maybeOf(context)?.look;
    final parent = run?.fontSize ?? t.len('app-body');
    final coding = run?.props.mono ?? true;
    // '.cm-field': { display: 'inline-block', padding: '0 0.35em', borderRadius: '0.35em',
    //   background: 'color-mix(in srgb, currentColor 9%, transparent)', color: 'var(--app-ink-2, inherit)',
    //   fontSize: '0.92em', lineHeight: '1.35', whiteSpace: 'nowrap', fontVariantNumeric: 'tabular-nums',
    //   verticalAlign: 'baseline' }
    final em = 0.92 * parent;
    final mark = look.text.isEmpty;
    final person = look.initial != null;
    final tone = look.tone;
    final ink3 = t.color('app-ink-3');
    var color = t.color('app-ink-2');
    Color? ground = color.withValues(alpha: color.a * 0.09);
    Color? hairline;
    switch (tone) {
      // '.cm-field[data-tone="overdue"]': { color: 'var(--glacier-red-11)',
      //   background: 'color-mix(in oklch, var(--glacier-red-9) 16%, transparent)' }
      case 'overdue':
        color = t.color('glacier-red-11');
        ground = t.colorOf('color-mix(in oklch, var(--glacier-red-9) 16%, transparent)');
      // '.cm-field[data-tone="today"]': amber, 18%
      case 'today':
        color = t.color('glacier-amber-11');
        ground = t.colorOf('color-mix(in oklch, var(--glacier-amber-9) 18%, transparent)');
      // '.cm-field[data-tone="quiet"], .cm-field[data-tone="done"]': { color: 'var(--app-ink-3, inherit)',
      //   background: 'none', boxShadow: 'inset 0 0 0 1px color-mix(in srgb, currentColor 22%, transparent)' }
      case 'quiet' || 'done':
        color = ink3;
        ground = null;
        // '.cm-field[data-mark][data-tone="done"]': { boxShadow: 'none' }
        hairline = mark ? null : ink3.withValues(alpha: ink3.a * 0.22);
      case 'highest' || 'high':
        color = t.color('glacier-red-11');
      case 'medium':
        color = t.color('glacier-amber-11');
      case 'low':
        color = t.color('glacier-blue-11');
      case 'lowest':
        color = ink3;
    }
    // '.cm-field[data-mark]': { padding: '0 0.1em', background: 'none' }
    if (mark) ground = null;
    final style = (run?.style ?? t.textAt(em)).copyWith(
      fontSize: em,
      color: color,
      letterSpacing: 0,
      decoration: TextDecoration.none,
      fontVariations: <FontVariation>[FontVariation('wght', run?.props.weight ?? 400), if (run?.props.optical ?? false) FontVariation('opsz', em)],
      fontFeatures: <FontFeature>[...?run?.style.fontFeatures, const FontFeature.tabularFigures()],
    );
    // The chip's line box, as the page makes it: the face's ascent and descent to whole pixels, the leading split
    // with the upper half floored.
    final face = FaceMetrics.of(style);
    final ascent = (face.ascent * em).roundToDouble(), descent = (face.descent * em).roundToDouble();
    final height = lineBoxHeight(lineHeight, em);
    final baseline = ascent + ((height - ascent - descent) / 2).floorToDouble();
    Widget words(String text, TextStyle of, double size) => Dropped(
      top: baseline - FaceMetrics.of(of).ascent * size,
      child: Text(
        text,
        softWrap: false,
        textScaler: TextScaler.noScaling,
        style: of.copyWith(height: FaceMetrics.of(of).ascent + FaceMetrics.of(of).descent),
      ),
    );

    final children = <Widget>[];
    final icon = look.icon;
    if (icon != null) {
      // '.cm-field > svg': { inlineSize: '0.95em', blockSize: '0.95em', verticalAlign: '-0.14em' }
      // '.cm-field[data-mark] > svg': { inlineSize: '1.1em', blockSize: '1.1em', verticalAlign: '-0.2em' }
      final size = (mark ? 1.1 : 0.95) * em, drop = (mark ? 0.2 : 0.14) * em;
      children.add(
        Dropped(
          top: baseline + drop - size,
          // `iconElement(look.icon, look.menu === 'priority' ? 2.6 : 2.2)`: the stroke in the icon's own units. The
          // app's wash for a closed silhouette (app.css) reaches a chip's icon as it does every other.
          child: AppIcon(icon, size: size, strokeWidth: look.menu == FieldMenu.priority ? 2.6 : 2.2, color: color),
        ),
      );
      // '.cm-field > svg + .cm-fieldWords': { marginInlineStart: '0.25em' }
      if (!mark) children.add(SizedBox(width: 0.25 * em));
    }
    if (person) {
      // '.cm-fieldInitial': { display: 'inline-block', inlineSize: '1.25em', blockSize: '1.25em',
      //   marginInlineEnd: '0.28em', borderRadius: '50%',
      //   background: 'color-mix(in oklch, var(--glacier-purple-9) 24%, transparent)',
      //   color: 'var(--glacier-purple-11)', fontSize: '0.78em', fontWeight: '700', lineHeight: '1.25em',
      //   textAlign: 'center', verticalAlign: '0.08em' }
      // '.cm-field[data-tone="done"] .cm-fieldInitial': { background: 'color-mix(in srgb, currentColor 12%,
      //   transparent)', color: 'inherit' }
      final size = 0.78 * em, ring = 1.25 * size;
      final done = tone == 'done';
      TextStyle ringStyleAt(double at) => style.copyWith(
        fontSize: at,
        fontWeight: FontWeight.w700,
        fontVariations: <FontVariation>[const FontVariation('wght', 700), if (run?.props.optical ?? false) FontVariation('opsz', at)],
        color: done ? color : t.color('glacier-purple-11'),
      );
      // A line of one size in the ring: its baseline there, the ascent and descent to whole pixels.
      double ringBaselineAt(double at) {
        final face = FaceMetrics.of(ringStyleAt(at));
        final ascent = (face.ascent * at).roundToDouble(), descent = (face.descent * at).roundToDouble();
        return ascent + ((ring - ascent - descent) / 2).floorToDouble();
      }

      // The ring's place on the line is the initial's, whatever is drawn in it.
      final ringBaseline = ringBaselineAt(size);
      // A contact's two initials in the round of one are smaller, so they keep inside it.
      final letters = contact?.initials ?? look.initial!;
      final letterSize = letters.length > 1 ? 0.6 * em : size;
      final letterStyle = ringStyleAt(letterSize);
      final letterFace = FaceMetrics.of(letterStyle);
      final Widget inRing = photo != null
          // The contact's picture fills the ring; on a finished item it is quieted with the rest.
          ? Opacity(
              opacity: done ? 0.55 : 1,
              child: ClipOval(child: SizedBox.square(dimension: ring, child: Image.memory(photo, fit: BoxFit.cover, gaplessPlayback: true))),
            )
          : Container(
              width: ring,
              height: ring,
              decoration: BoxDecoration(
                color: done ? color.withValues(alpha: color.a * 0.12) : t.colorOf('color-mix(in oklch, var(--glacier-purple-9) 24%, transparent)'),
                shape: BoxShape.circle,
              ),
              child: OverflowBox(
                minWidth: 0,
                maxHeight: double.infinity,
                alignment: Alignment.topCenter,
                child: Dropped(
                  top: ringBaselineAt(letterSize) - letterFace.ascent * letterSize,
                  child: Text(
                    letters,
                    softWrap: false,
                    textScaler: TextScaler.noScaling,
                    style: letterStyle.copyWith(height: letterFace.ascent + letterFace.descent),
                  ),
                ),
              ),
            );
      children.add(
        Padding(
          padding: EdgeInsetsDirectional.only(end: 0.28 * size),
          child: Dropped(top: baseline - 0.08 * size - ringBaseline, child: inRing),
        ),
      );
    }
    final name = look.name;
    if (name != null) {
      // '.cm-fieldName': { marginInlineEnd: '0.3em', fontSize: '0.86em', letterSpacing: '0.02em', opacity: '0.75' }
      final size = 0.86 * em;
      final nameStyle = style.copyWith(
        fontSize: size,
        letterSpacing: coding ? 0 : 0.02 * size,
        color: color.withValues(alpha: color.a * 0.75),
        fontVariations: <FontVariation>[FontVariation('wght', run?.props.weight ?? 400), if (run?.props.optical ?? false) FontVariation('opsz', size)],
      );
      children
        ..add(words(name, nameStyle, size))
        ..add(SizedBox(width: 0.3 * size));
    }
    if (look.text.isNotEmpty) children.add(words(look.text, style, em));

    // '.cm-field[data-person]': { paddingInlineStart: '0.12em', borderRadius: '999px' }
    final radius = person ? height / 2 : 0.35 * em;
    final chip = InlineBox(
      above: baseline,
      below: height - baseline,
      child: DecoratedBox(
        decoration: BoxDecoration(color: ground, borderRadius: BorderRadius.circular(radius)),
        child: CustomPaint(
          foregroundPainter: hairline == null ? null : _Hairline(hairline, radius),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: EdgeInsetsDirectional.only(start: (mark ? 0.1 : (person ? 0.12 : 0.35)) * em, end: (mark ? 0.1 : 0.35) * em),
              child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
          ),
        ),
      ),
    );
    final tap = onTap;
    return Semantics(
      label: look.label,
      button: tap != null,
      child: ExcludeSemantics(
        child: tap == null
            ? chip
            : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final box = context.findRenderObject();
                  if (box is RenderBox && box.attached) tap(box.localToGlobal(Offset.zero) & box.size);
                },
                child: chip,
              ),
      ),
    );
  }
}

/// `box-shadow: inset 0 0 0 1px`.
class _Hairline extends CustomPainter {
  const _Hairline(this.color, this.radius);

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius((Offset.zero & size).deflate(0.5), Radius.circular(radius - 0.5 < 0 ? 0 : radius - 0.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_Hairline oldDelegate) => oldDelegate.color != color || oldDelegate.radius != radius;
}
