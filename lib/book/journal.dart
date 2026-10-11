/// A journal: a notebook whose pages are dated entries, each started from a template the journal keeps (Matt: "a
/// journal function where we can just do entries into a book marked as a journal where we pick the template for
/// pages (time and date prefixed, with geo location, etc etc)"; tauri/docs/DESIGN.md §142). A port of
/// `src/app/book/journal.ts`.
///
/// It is a notebook note (lib/core/book.dart) with two more flat keys beside `book: true`, and a third when it keeps
/// places:
///
///     ---
///     title: "Diary"
///     book: true
///     journal: true
///     template: "# {{date}}\n\n**{{time}}** "
///     entry-place: true
///     ---
///
/// `template:` is one double-quoted string with JSON's escapes, which is also a YAML double-quoted scalar, so any
/// Markdown app reads the text back, and it stays one line, so the front matter stays flat.
///
/// An entry is an ordinary note named `2026-09-28 14.05`, by the minute it was made, in ASCII digits whatever the
/// language: its key (title_key.dart keeps only a-z and 0-9) never loses its month, and nothing in it is a character
/// a file name drops, so its file is `2026-09-28 14.05.md` and the index's link resolves in any Markdown app. Its
/// `date:` is the wall clock it was written at, with no offset, so a shared entry does not say which time zone its
/// writer was in. The friendly date is its heading and its row in the journal.
///
/// Pure: imports nothing that draws or stores.
///
/// What differs:
/// - `Preset` is [EntryPreset] and `PRESETS` [entryPresets], the names lib/notes/new_sheet.dart gave them when it
///   held them; `OWN` is [ownTemplate], `DEFAULT_TEMPLATE` [defaultTemplate], `PLACE_SENTENCE` [placeSentence].
/// - [entryTitle] and [localStamp] take a `DateTime` where the page takes milliseconds: the moment either way, read
///   by this device's clock.
/// - [stampOf] and [entryPages] were in lib/core/book.dart, and [uniqueTitle] in lib/notes/note_templates.dart,
///   until this file; both hand them on.
/// - The web's `JournalWriter` (the journal on screen writing its own index) is [JournalWriter], a class with the
///   one function.
library;

import 'dart:convert';

import '../core/book.dart' show chaptersOf, isBookBody, isJournalBody, withChapter;
import '../core/front_matter.dart';
import '../core/item_syntax.dart' show jsTrim;
import '../core/note.dart';
import '../core/note_text.dart' show noteTitle;
import '../core/properties.dart' show withFrontMatterValue;
import '../core/title_key.dart';

/// A template to start from, and the one sentence every hint says it with (`Preset`).
class EntryPreset {
  const EntryPreset({required this.id, required this.name, required this.text, required this.sentence});
  final String id;
  final String name;
  final String text;
  final String sentence;
}

/// The templates offered, in the order the sheet lists them: the first is every journal's default (`PRESETS`).
const List<EntryPreset> entryPresets = [
  EntryPreset(id: 'stamped', name: 'The date and the time', text: '# {{date}}\n\n**{{time}}** ', sentence: 'Starts with the date and the time.'),
  EntryPreset(id: 'time', name: 'Just the time', text: '**{{time}}** ', sentence: 'Starts with the time.'),
  EntryPreset(id: 'morning', name: 'A morning page', text: '# {{date}}\n\n> What is on your mind this morning?\n\n', sentence: 'Starts with a question for the morning.'),
  EntryPreset(id: 'todos', name: 'A day’s to-dos', text: '# {{date}}\n\n## To do\n\n- [ ] ', sentence: 'Starts with a to-do list.'),
];

/// A template of the person's own writing: any text that is not one of the presets (`OWN`).
const ({String id, String name, String sentence}) ownTemplate = (id: 'own', name: 'My own', sentence: 'Starts with your own template.');

/// The template a journal with none says starts its entries (`DEFAULT_TEMPLATE`).
const String defaultTemplate = '# {{date}}\n\n**{{time}}** ';

/// Said after a template's sentence when the journal keeps where each entry was written (`PLACE_SENTENCE`).
const String placeSentence = 'Keeps where each was written.';

EntryPreset? _presetFor(String text) {
  for (final preset in entryPresets) {
    if (preset.text == text) return preset;
  }
  return null;
}

/// Which preset [text] is, by its id, or `own`.
String presetOf(String text) => _presetFor(text)?.id ?? ownTemplate.id;

/// The sentence that says what an entry starts with: the preset's, or your own template's.
String templateSentence(String text) => _presetFor(text)?.sentence ?? ownTemplate.sentence;

// ---- the journal's keys -------------------------------------------------------------------------------------------

/// A front matter key's value as it is written, quotes and escapes and all, or null where there is none.
String? _rawValue(String body, String key) {
  final lines = body.split('\n');
  final end = frontMatterEnd(lines);
  final pattern = RegExp('^\\s*$key\\s*:', caseSensitive: false);
  // The page's `lines.slice(1, Math.max(1, end - 1))`.
  final to = (end - 1 < 1 ? 1 : end - 1).clamp(0, lines.length);
  for (final each in lines.length > 1 ? lines.sublist(1, to < 1 ? 1 : to) : const <String>[]) {
    if (pattern.hasMatch(each)) return jsTrim(each.replaceFirst(pattern, ''));
  }
  return null;
}

final RegExp _handQuoted = RegExp(r'''^(["'])(.*)\1$''');

/// The template as `template:` holds it: one JSON string, as the app writes it. A value someone wrote by hand
/// without quotes, or with quotes JSON will not read, is taken as written, `\n` as a line break. Absent, the default.
String templateOf(String body) {
  final raw = _rawValue(body, 'template');
  if (raw == null) return defaultTemplate;
  if (raw.startsWith('"')) {
    try {
      final Object? text = jsonDecode(raw);
      if (text is String) return text;
    } on FormatException {
      // Not JSON after all: read as written, below.
    }
  }
  return raw.replaceFirstMapped(_handQuoted, (m) => m.group(2)!).replaceAll(r'\n', '\n');
}

/// A template as `template:`'s value: JSON's escapes, and the two line separators JSON leaves raw escaped too.
String _templateValue(String text) => jsonEncode(text).replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');

/// The body with its template set; every other key and the index as they were.
String withTemplate(String body, String text) => withFrontMatterValue(body, 'template', _templateValue(text));

final RegExp _yes = RegExp(r'^(true|yes)$', caseSensitive: false);

/// Whether the journal's entries keep where each was written (`entry-place:`, never `place:`, which is a geotag's).
bool entryPlaceOf(String body) {
  final said = frontMatterValue(body, 'entry-place');
  return said != null && _yes.hasMatch(said);
}

/// The body with its entries keeping their places, or not.
String withEntryPlace(String body, bool on) => withFrontMatterValue(body, 'entry-place', on ? 'true' : null);

/// A notebook kept as a journal: `journal: true`, its template and its place switch, the rest as it was.
String withJournal(String body, String template, bool place) => withEntryPlace(withTemplate(withFrontMatterValue(body, 'journal', 'true'), template), place);

/// A journal made a notebook again: its three keys out, `book: true` and every page kept.
String withoutJournal(String body) => const ['journal', 'template', 'entry-place'].fold(body, (next, key) => withFrontMatterValue(next, key, null));

/// The body of a new journal: named, its template and its place switch, and an empty index under its heading.
String journalNoteBody(String name, String template, bool place) {
  final named = quotedTitle(name, 'Journal');
  final keys = ['title: $named', 'book: true', 'journal: true', 'template: ${_templateValue(template)}', if (place) 'entry-place: true'];
  return '---\n${keys.join('\n')}\n---\n# ${named.substring(1, named.length - 1)}\n\n';
}

final RegExp _numbered = RegExp(r'^\s*(\d+)([.)])');

/// The journal's body with an entry's line added last, where the index's last line is, or after its words when it
/// has none yet. Last, whatever the entries' times, so the index reads in the order they were made in any app, and
/// two devices that each added one merge as the two lines; the journal's own view orders by time.
///
/// At the index's top level, however its last line sits: in a notebook kept as a journal whose last page is a part
/// of the one above it, `withChapter` would indent the entry under that page too. Numbered on from the last
/// top-level line where the index numbers its pages.
String withEntry(String body, String title) {
  final clean = jsTrim(title);
  final chapters = chaptersOf(body);
  if (clean.isEmpty || chapters.isEmpty || chapters.last.depth == 0 || chapters.any((c) => sameTitle(c.title, clean))) return withChapter(body, clean);
  final last = chapters.last;
  final lines = body.split('\n');
  final top = chapters.reversed.where((c) => c.depth == 0).firstOrNull;
  final marker = top == null ? null : _numbered.firstMatch(top.line < lines.length ? lines[top.line] : '');
  lines.insert(last.line + 1, '${marker != null ? '${int.parse(marker.group(1)!) + 1}${marker.group(2)}' : '-'} [[$clean]]');
  return lines.join('\n');
}

/// The journal on screen, writing its own index: the app puts an entry's line in, or takes it out, through the
/// journal's editor rather than under it, since the open journal's next save would otherwise write the old index
/// back or be refused (`JournalWriter`).
class JournalWriter {
  const JournalWriter({required this.id, required this.write});
  final String id;

  /// `change` made to the journal's body as the screen holds it, saved at once.
  final void Function(String Function(String body) change) write;
}

// ---- an entry -----------------------------------------------------------------------------------------------------

String _two(int n) => n.toString().padLeft(2, '0');
String _four(int n) => n.toString().padLeft(4, '0');

/// An entry's name, by the minute it was made in the device's time: "2026-09-28 14.05", ASCII in every language.
String entryTitle(DateTime at) {
  final local = at.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)} ${_two(local.hour)}.${_two(local.minute)}';
}

/// A title an entry is named by: the minute, and ` (2)` or more for a second in the same minute.
final RegExp _entryTitle = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}\.\d{2}(?: \(\d+\))?$');

bool isEntryTitle(String title) => _entryTitle.hasMatch(jsTrim(title));

/// [title], or with ` (2)`, ` (3)` after it until no key in [keys] is its (title_key.dart).
String uniqueTitle(String title, Set<String> keys) {
  if (!keys.contains(titleKey(title))) return title;
  for (var n = 2;; n += 1) {
    final next = '$title ($n)';
    if (!keys.contains(titleKey(next))) return next;
  }
}

/// The wall clock at [at] as `date:` writes it: "2026-09-28T14:05", with no offset.
String localStamp(DateTime at) {
  final local = at.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}T${_two(local.hour)}:${_two(local.minute)}';
}

/// An entry's note: its name and when it was written, then the words it starts with.
String entryBody(String title, String stamp, String words) => '---\ntitle: ${quotedTitle(title, title)}\ndate: $stamp\n---\n$words';

/// `date:`'s wall clock: a day, and a time where it gives one.
final RegExp _wall = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2}))?');

/// When an entry was written, as the wall clock read then, in milliseconds whose UTC fields are that wall clock:
/// from its `date:`, else from when the note was made, read in this device's time. So an entry written at 23:30 in
/// New York sorts and is grouped on the 28th wherever it is read, and entries compare by the clocks they were
/// written at.
int stampOf(String body, int createdAt) {
  final said = _wall.firstMatch(frontMatterValue(body, 'date') ?? '');
  if (said != null) {
    return DateTime.utc(int.parse(said.group(1)!), int.parse(said.group(2)!), int.parse(said.group(3)!), int.parse(said.group(4) ?? '0'), int.parse(said.group(5) ?? '0'))
        .millisecondsSinceEpoch;
  }
  final made = DateTime.fromMillisecondsSinceEpoch(createdAt);
  return DateTime.utc(made.year, made.month, made.day, made.hour, made.minute).millisecondsSinceEpoch;
}

/// An ISO stamp of a wall clock ([stampOf]), as the page's `new Date(wall).toISOString()` writes it.
String wallIso(int wall) {
  final at = DateTime.fromMillisecondsSinceEpoch(wall, isUtc: true);
  return '${_four(at.year)}-${_two(at.month)}-${_two(at.day)}T${_two(at.hour)}:${_two(at.minute)}:${_two(at.second)}.${at.millisecond.toString().padLeft(3, '0')}Z';
}

/// The notes some journal's index names, by id: its entries, and any page it planned before it was kept as a
/// journal. Recent and the palette's first list leave them out (lib/home/dashboard.dart, lib/commands), as they
/// leave out the Guide's pages: a year of entries would otherwise fill Recent every day, and the journal's card is
/// the way to them.
Set<String> entryPages(Iterable<Note> notes) {
  final named = <String>{};
  for (final note in notes) {
    if (!isJournalBody(note.body)) continue;
    for (final chapter in chaptersOf(note.body)) {
      final key = titleKey(chapter.title);
      if (key.isNotEmpty) named.add(key);
    }
  }
  final ids = <String>{};
  if (named.isEmpty) return ids;
  for (final note in notes) {
    if (!isBookBody(note.body) && named.contains(titleKey(noteTitle(note.body)))) ids.add(note.id);
  }
  return ids;
}
