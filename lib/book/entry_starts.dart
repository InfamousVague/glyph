/// What a new entry can start from, as New entry offers it on an open journal (../glyph docs/DESIGN.md §142): the
/// journal's usual template first, then the presets it is not, then an empty page, each told on one line as it would
/// start this minute. A port of `src/app/book/entryStarts.ts`. Pure, so the order and the line are tests.
///
/// What differs: `Start` is [EntryStart], the name lib/notes/new_sheet.dart gave it when it held [entryStarts] and
/// [startLine]; that file hands them on. `JUST_THE_TITLE` is [justTheTitle]. The moment is asked for, where the
/// page's default is now.
library;

import '../core/item_syntax.dart' show jsTrim;
import '../core/template.dart' show fillTemplate;
import 'journal.dart';

/// One way to start an entry: its name, and the text it starts with (`Start`).
class EntryStart {
  const EntryStart({required this.id, required this.name, required this.text});
  final String id;
  final String name;
  final String text;
}

/// The journal's usual template first, then the presets it is not, then an empty page.
List<EntryStart> entryStarts(String usual) {
  EntryPreset? preset;
  for (final each in entryPresets) {
    if (each.text == usual) {
      preset = each;
      break;
    }
  }
  return [
    EntryStart(id: 'usual', name: preset?.name ?? ownTemplate.name, text: usual),
    for (final each in entryPresets)
      if (each.text != usual) EntryStart(id: each.id, name: each.name, text: each.text),
    if (jsTrim(usual).isNotEmpty) const EntryStart(id: 'empty', name: 'An empty page', text: ''),
  ];
}

final RegExp _lineMark = RegExp(r'^\s*(?:#{1,6}\s+|>\s?|[-*+]\s+\[[ xX]\]\s*|[-*+]\s+)');
final RegExp _emphasis = RegExp(r'\*\*|__|\*|_');

/// How a template starts, on one line: filled for [at], its marks taken off, its lines joined.
String startLine(String text, String journal, [DateTime? at]) {
  final now = at ?? DateTime.now();
  final filled = fillTemplate(text, at: now, title: entryTitle(now), journal: jsTrim(journal).isEmpty ? 'Journal' : jsTrim(journal));
  final lines = [
    for (final line in filled.split('\n'))
      if (jsTrim(line.replaceFirst(_lineMark, '').replaceAll(_emphasis, '')) case final words when words.isNotEmpty) words,
  ];
  return lines.isNotEmpty ? lines.join(' · ') : 'Nothing, a blank page';
}

/// A new page made as it always was: its title, and nothing under it (`JUST_THE_TITLE`).
const EntryStart justTheTitle = EntryStart(id: 'title', name: 'Just the title', text: '');

/// What a notebook's new page can start from, under its title in Add a page (Matt: "To be clear this should be
/// visible on the page where I enter the note name after hitting new page in journal"): just its title, as a page
/// always began, then the templates a journal's entries start from.
List<EntryStart> pageStarts() => [justTheTitle, for (final each in entryPresets) EntryStart(id: each.id, name: each.name, text: each.text)];

final RegExp _firstHeading = RegExp('^# ');

/// A new page's body: its title as its heading, so its line in the index still finds it, and the template filled
/// under it for this minute, `{{title}}` the page's name and `{{journal}}` the notebook's. A heading the template
/// opens with steps down a level, so the page keeps one title.
String pageBody(String title, String template, String notebook, [DateTime? at]) {
  final head = '# $title\n\n';
  if (jsTrim(template).isEmpty) return head;
  final filled = fillTemplate(template, at: at ?? DateTime.now(), title: title, journal: jsTrim(notebook).isEmpty ? 'Notebook' : jsTrim(notebook));
  return head + filled.replaceFirst(_firstHeading, '## ');
}
