/// Snippets: the person's own text expansions (Matt, 2026-10-27: "build ... snippets"; docs/ideas/
/// CUSTOMIZATION_AND_SOUNDS.md idea 15, "Personal text expansions (;sig, ;addr, today's date in a format) in Settings,
/// offered on the +"). What a snippet is, what may be typed to call it, and what it becomes. Pure: the editor's half,
/// which watches for a trigger as it is typed, is lib/editor/commands/snippets.dart; the list itself is kept with the
/// preferences ([Preferences.snippets]) and edited on Settings › Snippets (lib/settings/panes/snippets_pane.dart).
///
/// **The trigger.** A semicolon and then letters and digits, up to 24 of them: `;sig`, `;addr2`. One rule, so it is
/// easy to say and hard to type by accident: a semicolon is followed by a space in prose, never by a word, and the
/// keyboard does not capitalise after it. It is called when it stands on its own, at a line's start or after a space,
/// and the space, Enter or Tab typed after it is what calls it. Letters are matched whatever their case, since a
/// phone's keyboard may capitalise a line's first letter, and so two snippets may not differ only by case.
///
/// **The words.** Markdown, any number of lines, with four placeholders filled as it is written:
///
///     {date}       27 October 2026      the day, in the phone's own order ("October 27, 2026" on an American one)
///     {time}       16:05                a 24-hour clock, as the +'s time row and a template's {{time}} write it
///     {datetime}   27 October 2026, 16:05
///     {cursor}     where the caret lands; the end of the words where there is none
///
/// Single braces, where a template's are double ({{date}}, lib/core/template.dart): a snippet is the person's own
/// shorthand and short to type, and a template's placeholder in a snippet is left for the template. Anything else in braces is left as it was typed, so a blank for the AI (`{?q}`) or a
/// plugin's `{image: ...}` can be part of a snippet.
library;

import 'locale_dates.dart';
import 'preferences.dart' show Snippet;
import 'template.dart' show clockTime;

/// What a trigger is: a semicolon and one to 24 letters or digits.
final RegExp snippetTriggerRule = RegExp(r'^;[A-Za-z0-9]{1,24}$');

/// A trigger at the end of the words before the caret, on its own: at the line's start or after a space.
final RegExp _triggerAtEnd = RegExp(r'(?:^|\s)(;[A-Za-z0-9]{1,24})$');

const List<String> _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// The placeholders, as Settings lists them under the words.
const List<({String name, String says})> snippetPlaceholders = [
  (name: '{date}', says: 'today’s date'),
  (name: '{time}', says: 'the time now'),
  (name: '{datetime}', says: 'both'),
  (name: '{cursor}', says: 'where the caret lands'),
];

/// "27 October 2026": the day, the month in full and the year, in the phone's order.
String snippetDate(DateTime at) => toldDate(at, DateForm.yMMMMd) ?? '${at.day} ${_months[at.month - 1]} ${at.year}';

/// A snippet's words as they are written at [now]: the placeholders filled, `{cursor}` taken out, and where the caret
/// goes, counted from the words' start. Only the first `{cursor}` places the caret; any other is taken out too.
({String text, int caret}) expandSnippet(String text, DateTime now) {
  final filled = text.replaceAllMapped(_placeholder, (match) => switch (match.group(1)) {
        'date' => snippetDate(now),
        'time' => clockTime(now),
        'datetime' => '${snippetDate(now)}, ${clockTime(now)}',
        _ => _cursor,
      });
  final at = filled.indexOf(_cursor);
  final words = filled.replaceAll(_cursor, '');
  return (text: words, caret: at < 0 ? words.length : at);
}

/// A placeholder in single braces: a template's `{{date}}` in a snippet is left for the template.
final RegExp _placeholder = RegExp(r'(?<!\{)\{(date|time|datetime|cursor)\}(?!\})');

/// Where the caret goes, once the placeholders are filled; a character no one types, so `{{cursor}}` stays words.
const String _cursor = '\u{E000}';

/// Whether [snippet]'s words place the caret themselves.
bool placesCaret(Snippet snippet) => _placeholder.allMatches(snippet.text).any((match) => match.group(1) == 'cursor');

/// The snippet [trigger] calls, whatever its case; null for none.
Snippet? snippetFor(String trigger, List<Snippet> snippets) {
  final key = trigger.toLowerCase();
  for (final each in snippets) {
    if (each.trigger.toLowerCase() == key) return each;
  }
  return null;
}

/// The snippet whose trigger ends [before] (the line's words up to the caret), on its own, and where in [before] the
/// trigger starts; null where there is none.
({int from, Snippet snippet})? triggerBefore(String before, List<Snippet> snippets) {
  if (snippets.isEmpty || !before.contains(';')) return null;
  final match = _triggerAtEnd.firstMatch(before);
  if (match == null) return null;
  final trigger = match.group(1)!;
  final snippet = snippetFor(trigger, snippets);
  return snippet == null ? null : (from: before.length - trigger.length, snippet: snippet);
}

/// What is wrong with a snippet as Settings would keep it, in words; null where nothing is. [others] are the rest of
/// the list, for a trigger that is taken.
String? snippetProblem(String trigger, String text, List<Snippet> others) {
  final typed = trigger.trim();
  if (typed.isEmpty) return 'Give it a trigger, like ;sig.';
  if (!typed.startsWith(';')) return 'A trigger starts with a semicolon, like ;sig.';
  if (!snippetTriggerRule.hasMatch(typed)) return 'After the semicolon, letters and digits only, at most 24.';
  if (snippetFor(typed, others) != null) return '$typed is already a snippet.';
  if (text.trim().isEmpty) return 'Write what $typed becomes.';
  return null;
}

/// A trigger as it is kept: what was typed, trimmed.
String keptTrigger(String typed) => typed.trim();

/// A new snippet's id: unlike any in [list], from the moment it was made.
String newSnippetId(List<Snippet> list, DateTime now) {
  final ids = {for (final each in list) each.id};
  var n = now.microsecondsSinceEpoch;
  while (ids.contains('s-${n.toRadixString(36)}')) {
    n += 1;
  }
  return 's-${n.toRadixString(36)}';
}

/// A snippet's words on one short line, as a row shows them: the placeholders filled at [now], lines joined.
String snippetPreviewLine(Snippet snippet, DateTime now, {int most = 60}) {
  final words = expandSnippet(snippet.text, now).text.trim().replaceAll(RegExp(r'\s*\n\s*'), ' · ');
  return words.length <= most ? words : '${words.substring(0, most - 1)}…';
}
