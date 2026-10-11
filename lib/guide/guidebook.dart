/// Ghost.md: The Guide, the app's own manual, built in as a notebook. A port of `src/app/guidebook/guidebook.ts`:
/// forty-four chapters in eleven parts, each a Markdown file in `assets/guidebook/chapters/`, named `NN-slug.md` so
/// the files' order is the book's, and `assets/guidebook/index.md` the notebook's own note: `book: true` in its
/// front matter, its numbered `[[links]]` the chapters, found by title as any notebook's are. The Markdown is the web
/// app's, byte for byte (test/guide/guidebook_test.dart compares each file with `tauri/` where it is beside the
/// repository).
///
/// The book costs the library nothing until it is added ([addGuideBook], from Settings › About). Added, it is
/// ordinary notes, written through the library as a note typed in the editor is, and from then on the person's own
/// to read, edit, share or delete. Adding it twice gives one book: a chapter whose title a note already has is not
/// made again, since the index finds its chapters by title, and a book already there by the Guide's title is
/// answered as it is.
///
/// What differs:
/// - The page reads each chapter through a lazy glob, a chunk of its own fetched on the press; here they are assets
///   of the app, read through an [AssetBundle] ([rootBundle] unless a test brings one that reads the files).
/// - A bundle cannot be asked what it holds without its manifest, so the chapters' file names are written here
///   ([guideChapterFiles]) and the test holds the list to the folder. [guideChapters] is its length, as the page's
///   `GUIDE_CHAPTERS` is the length of the glob.
/// - `guidePages`, `isGuideBook` and `GUIDE_TITLE` were ported with the home page, in lib/core/book.dart, and are
///   handed on from there.
/// - [addGuideBook] is given the library it writes to, where the page's store is a module.
library;

import 'package:flutter/services.dart';

import '../core/book.dart';
import '../core/library.dart';
import '../core/note.dart';
import '../core/note_text.dart';

export '../core/book.dart' show guidePages, guideTitle, isGuideBook;

/// Where the book's Markdown is kept among the app's assets.
const String guideAssets = 'assets/guidebook';

/// The chapters' files, in book order: the numbers in the names are the order.
const List<String> guideChapterFiles = <String>[
  '01-the-first-five-minutes.md',
  '02-a-note-is-a-markdown-file.md',
  '03-finding-your-way-around.md',
  '04-the-marks-you-can-type.md',
  '05-effects-on-words.md',
  '06-links-between-notes.md',
  '07-tags-footnotes-and-the-small-marks.md',
  '08-pictures-and-voice-memos.md',
  '09-recording-a-note.md',
  '10-saying-the-marks.md',
  '11-spoken-commands.md',
  '12-lists-and-to-dos.md',
  '13-boards-made-of-list-items.md',
  '14-books-and-reading-one-through.md',
  '15-canvases-cards-and-lines.md',
  '16-the-models-on-your-phone.md',
  '17-asking-the-ai-to-work-on-a-note.md',
  '18-spoken-asks-and-the-review.md',
  '19-accounts-sync-and-the-key-you-hold.md',
  '20-live-typing.md',
  '21-sharing-a-note-or-a-book.md',
  '22-notion-and-github.md',
  '23-claude-on-your-notes.md',
  '24-settings-one-section-at-a-time.md',
  '25-the-side-key-the-fold-and-the-mac.md',
  '26-what-stays-on-your-phone.md',
  '27-ghost-md-in-one-page.md',
  '28-no-router-five-screens.md',
  '29-the-native-half.md',
  '30-the-editor-and-its-language.md',
  '31-formats-that-stay-markdown.md',
  '32-the-plugin-seam.md',
  '33-from-microphone-to-markdown.md',
  '34-reading-a-command-writing-it-safely.md',
  '35-the-engines-on-the-device.md',
  '36-the-library-on-disk.md',
  '37-sync-and-the-end-to-end-keys.md',
  '38-live-typing-over-a-relay.md',
  '39-glyph-api-the-server.md',
  '40-the-claude-connector-inside.md',
  '41-over-the-air-and-releases.md',
  '42-tests-and-the-report-that-ships.md',
  '43-working-on-ghost-md.md',
  '44-where-the-docs-and-the-code-disagree.md',
];

/// How many chapters the book has, known without loading one (`GUIDE_CHAPTERS`).
const int guideChapters = 44;

/// A chapter as it ships: its title, read from its heading as the list reads it, and its Markdown (`GuideChapter`).
class GuideChapter {
  const GuideChapter({required this.title, required this.body});
  final String title;
  final String body;
}

/// The whole book (`GuideBook`).
class GuideBook {
  const GuideBook({required this.index, required this.chapters});

  /// The book note's body: front matter, the intro, the parts with their numbered links, and the words after them.
  final String index;

  /// The chapters, in book order.
  final List<GuideChapter> chapters;
}

/// The whole book, read now (`loadGuideBook`). Nothing of it is read before this is called. A file that cannot be
/// read is the bundle's error, and nothing has been written to any library by then.
Future<GuideBook> loadGuideBook({AssetBundle? bundle}) async {
  final from = bundle ?? rootBundle;
  final read = await Future.wait(<Future<String>>[
    from.loadString('$guideAssets/index.md', cache: false),
    for (final file in guideChapterFiles) from.loadString('$guideAssets/chapters/$file', cache: false),
  ]);
  return GuideBook(
    index: read.first,
    chapters: <GuideChapter>[for (final body in read.skip(1)) GuideChapter(title: noteTitle(body), body: body)],
  );
}

/// Puts the guide in [library] and answers its index, the note to open (`addGuideBook`). [notes] are the notes there
/// are now, out of the trash; an archived one counts as missing, as it does to a `[[link]]`. The chapters are made
/// first, the last of them first, so a list sorted newest first reads the book from chapter one; the index comes
/// last, newest of all.
Future<Note> addGuideBook(NoteLibrary library, List<Note> notes, {AssetBundle? bundle}) async {
  final shown = <Note>[
    for (final note in notes)
      if (note.archivedAt == null || note.archivedAt == 0) note,
  ];
  for (final note in shown) {
    if (isBookBody(note.body) && sameTitle(noteTitle(note.body), guideTitle)) return note;
  }
  final book = await loadGuideBook(bundle: bundle);
  bool titled(String title) => shown.any((note) => sameTitle(noteTitle(note.body), title));
  for (final chapter in book.chapters.reversed) {
    if (!titled(chapter.title)) await library.createNote(chapter.body);
  }
  return library.createNote(book.index);
}
