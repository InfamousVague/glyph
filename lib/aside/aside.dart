/// What the right-hand aside shows. A port of `src/app/aside/aside.ts`.
///
/// - **A book**, while it or one of its pages is open: its index, the open chapter marked. A journal's is one month
///   of its entries, newest first: the open entry's month, or its newest.
/// - **Chapters with no book**, while a numbered chapter is open (book/chapter_number.dart): it and its fellow
///   chapters, in the order of their numbers.
/// - **Nothing** anywhere else, and the aside and its toggle aren't shown.
///
/// Pure, so each rule is a test. What differs from the web: `localeCompare` is Dart's `compareTo` (the order of two
/// chapters with the same number), and the device's memory is [Stored] rather than `localStorage`.
library;

import 'package:flutter/foundation.dart';

import '../book/chapter_number.dart';
import '../book/journal_months.dart';
import '../core/book.dart';
import '../core/item_syntax.dart' show jsTrim;
import '../core/note.dart';
import '../core/note_text.dart';
import '../core/stored.dart';
import '../editor/items/wiki_links.dart';

/// What the aside holds (`AsideContent`).
@immutable
sealed class AsideContent {
  const AsideContent();
}

/// A book's index, or one month of a journal's entries.
class AsideBook extends AsideContent {
  const AsideBook({required this.place, required this.open, this.month, this.journal = false});
  final BookPlace place;

  /// The id of the page on screen; null while the book itself is.
  final String? open;

  /// A journal's month; null for a journal with nothing written. Only read when [journal].
  final JournalMonth? month;
  final bool journal;
}

/// A run of numbered chapters that no book lists.
class AsideChapters extends AsideContent {
  const AsideChapters({required this.title, required this.titleId, required this.chapters, required this.open});
  final String title;

  /// The note the chapters point back at, when there is one by that title.
  final String? titleId;
  final List<NumberedChapter> chapters;
  final String open;
}

@immutable
class NumberedChapter {
  const NumberedChapter({required this.id, required this.number, required this.name});
  final String id;
  final int number;

  /// The title without its number: the number is drawn in its own column.
  final String name;
}

/// [notes] are the library's notes as the app shows them; [open] the note on screen, or null on the home page.
/// A book shows its own index with no chapter marked; a page of one shows its book's with itself marked
/// (`asideContent`).
AsideContent? asideContent(List<Note> notes, Note? open) {
  if (open == null) return null;
  if (isBookBody(open.body)) {
    final journal = isJournalBody(open.body);
    final place = BookPlace(book: open, title: noteTitle(open.body), chapters: chaptersOf(open.body), at: -1, journal: journal);
    return AsideBook(place: place, open: null, journal: journal, month: journal ? asideMonth(open, notes, null) : null);
  }
  final place = bookIndex(notes)[titleKey(noteTitle(open.body))];
  if (place != null) {
    return AsideBook(place: place, open: open.id, journal: place.journal, month: place.journal ? asideMonth(place.book, notes, noteTitle(open.body)) : null);
  }
  return _chapterRun(notes, open);
}

/// The numbered chapters that belong with the open one, in order. Chapters belong together when their pages point
/// at the same note first (a chapter's "« [[The book]]" line; a link to another numbered chapter doesn't count), or,
/// with no such link, when they sit in the same folder. One chapter alone is no run, so it shows nothing
/// (`chapterRun`).
AsideContent? _chapterRun(List<Note> notes, Note open) {
  final mine = chapterOf(noteTitle(open.body));
  if (mine == null) return null;
  final group = _groupOf(open);
  final chapters = <NumberedChapter>[];
  for (final note in notes) {
    if (note.archivedAt != null || isBookBody(note.body)) continue;
    final numbered = note.id == open.id ? mine : chapterOf(noteTitle(note.body));
    if (numbered == null || _groupOf(note).key != group.key) continue;
    chapters.add(NumberedChapter(id: note.id, number: numbered.number, name: numbered.name));
  }
  if (chapters.length < 2) return null;
  chapters.sort((a, b) => a.number != b.number ? a.number - b.number : a.name.compareTo(b.name));
  String? titleId;
  final link = group.link;
  if (link != null) {
    for (final note in notes) {
      if (titleKey(noteTitle(note.body)) == titleKey(link)) {
        titleId = note.id;
        break;
      }
    }
  }
  return AsideChapters(title: group.link ?? group.folder ?? 'Chapters', titleId: titleId, chapters: chapters, open: open.id);
}

/// What a chapter belongs to: the first note its page points at that isn't another chapter, else its folder
/// (`groupOf`).
({String key, String? link, String? folder}) _groupOf(Note note) {
  final own = titleKey(noteTitle(note.body));
  for (final link in wikiLinksIn(note.body)) {
    final title = jsTrim(link.title);
    if (title.isEmpty || titleKey(title) == own || chapterOf(title) != null) continue;
    return (key: 'link:${titleKey(title)}', link: title, folder: null);
  }
  final path = note.path;
  final folder = path != null && path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : null;
  return (key: 'folder:${folder ?? ''}', link: null, folder: folder == null || folder.isEmpty ? null : folder.split('/').last);
}

// ---- kept to this device ------------------------------------------------------------------------------------------

const String _shownKey = 'glyph-aside-shown';
const String _tabKey = 'glyph-aside-tab';

/// Whether the aside is shown, kept to this device between launches; hidden until it has been opened once
/// (`readAsideShown`).
bool readAsideShown([Stored? on]) => (on ?? stored).readText(_shownKey) == '1';

/// Not kept, it opens hidden next time (`writeAsideShown`).
void writeAsideShown(bool shown, [Stored? on]) => (on ?? stored).writeText(_shownKey, shown ? '1' : '0');

/// Which of the aside's tabs the person last looked at, kept to this device: the index, the version history, and
/// since 2.1 the note's links and its outline (lib/links/note_links.dart). (`'index' | 'history' | 'links' |
/// 'outline'`; an enum cannot name a value `index` here.)
enum AsideTab { contents, history, links, outline }

AsideTab readAsideTab([Stored? on]) => switch ((on ?? stored).readText(_tabKey)) {
      'history' => AsideTab.history,
      'links' => AsideTab.links,
      'outline' => AsideTab.outline,
      _ => AsideTab.contents,
    };

void writeAsideTab(AsideTab tab, [Stored? on]) => (on ?? stored).writeText(_tabKey, tab == AsideTab.contents ? 'index' : tab.name);

/// Heard by an open aside when something asks for a tab (`ASIDE_TAB_CHOSEN`): the bar's History button.
final ValueNotifier<AsideTab?> asideTabChosen = ValueNotifier<AsideTab?>(null);

/// Turns an open aside to [tab], and keeps it as the one chosen (`showAsideTab`).
void showAsideTab(AsideTab tab, [Stored? on]) {
  writeAsideTab(tab, on);
  asideTabChosen
    ..value = null
    ..value = tab;
}

// ---- the docked sidebar's own switch (core/useWideScreen.ts) ------------------------------------------------------

/// Kept under a key of its own since the sidebar on a wide window became simple mode's list (Matt, 2026-10-24: "make
/// the sidebar on advanced mode the same as simple but just hide it by default"). The old tree's switch was
/// `glyph-sidebar-shown`, which a Mac had at '1' from the first time the tree showed; read as this one it would have
/// opened the new list on everyone who ever had the tree, so "hide it by default" would have held only for new
/// installs. Under a new key everyone starts hidden once, and from their first press on the list is where they left
/// it. The old key is not read again, and the first write forgets it (the Tauri carry still brings it over, as it
/// brings every key it finds).
const String _sidebarShownKey = 'glyph-sidebar-list-shown';
const String _oldSidebarShownKey = 'glyph-sidebar-shown';

/// Whether the sidebar beside the note is showing, as kept to this device; null until it has ever been toggled,
/// when it is hidden (`readSidebarShown`, shell/wide_screen.dart `sidebarShownAtFirst`).
bool? readSidebarShown([Stored? on]) {
  final kept = (on ?? stored).readText(_sidebarShownKey);
  return kept == '1' || kept == '0' ? kept == '1' : null;
}

void writeSidebarShown(bool shown, [Stored? on]) {
  final at = on ?? stored;
  at.writeText(_sidebarShownKey, shown ? '1' : '0');
  at.writeText(_oldSidebarShownKey, null);
}
