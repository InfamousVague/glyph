import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/book_view.dart' show numbered;
import 'package:ghost_md/canvas/how_canvas.dart';
import 'package:ghost_md/canvas/sample_canvas.dart';
import 'package:ghost_md/core/board_note.dart' as board;
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/boards/items.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/editor/items/wiki_links.dart';
import 'package:ghost_md/guide/guidebook.dart';
import 'package:ghost_md/plugins/marks.dart';
import 'package:ghost_md/settings/panes/about_pane.dart' as about;

import 'support.dart';

/// `guidebook/guidebook.test.ts`, case for case: Ghost.md: The Guide as it ships. The index is a book whose chapters
/// are the files, every link in it lands on a page that will be there, no page shares a name with the notes Settings
/// already adds, nothing in it reads like a secret, adding it twice leaves one book, and the Marks plugin's marks are
/// all taught, typed and said and counted. And one case of this port's own: the assets are the web app's files.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bundle = DiskBundle();

  /// The chapter files as they are on disk, in the order of their names: `(name, body)`.
  final files = [
    for (final file in Directory('assets/guidebook/chapters').listSync().whereType<File>().where((f) => f.path.endsWith('.md')).toList()..sort((a, b) => a.path.compareTo(b.path)))
      (file.uri.pathSegments.last, file.readAsStringSync()),
  ];

  /// The notes Settings › About adds, by the titles the app gives them.
  final builtIn = [noteTitle(sampleNoteBody), noteTitle(board.boardNoteBody()), noteTitle(sampleCanvasBody()), noteTitle(howCanvasBody())];

  late GuideBook book;
  late List<String> titles;
  late List<({String name, String body})> pages;
  setUpAll(() async {
    book = await loadGuideBook(bundle: bundle);
    titles = [for (final chapter in book.chapters) chapter.title];
    pages = [for (final chapter in book.chapters) (name: chapter.title, body: chapter.body), (name: guideTitle, body: book.index)];
  });

  final fenceOpen = RegExp(r'^\s*(`{3,}|~{3,})');
  final inlineCode = RegExp(r'(`+)[\s\S]*?\1');

  /// A page's words with its code taken out, fenced and inline: where a [[link]] is a link rather than an example.
  String prose(String markdown) {
    final kept = <String>[];
    String? fence;
    for (final line in markdown.split('\n')) {
      final open = fenceOpen.firstMatch(line)?.group(1);
      if (fence != null) {
        if (open != null && open[0] == fence[0] && open.length >= fence.length && line.trim() == open) fence = null;
        continue;
      }
      if (open != null) {
        fence = open;
        continue;
      }
      kept.add(line.replaceAll(inlineCode, ''));
    }
    return kept.join('\n');
  }

  /// What a secret looks like, by name: never in a page anyone can add to their library and share.
  final secrets = <(String, RegExp)>[
    ('an IP address', RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b')),
    ('a password', RegExp(r'password\s*[:=]', caseSensitive: false)),
    ('a token', RegExp(r'token\s*=', caseSensitive: false)),
    ('SSHPASS', RegExp('sshpass', caseSensitive: false)),
    ('a hex key', RegExp(r'\b[0-9a-f]{32,}\b', caseSensitive: false)),
  ];

  /// A base64 key: a run of sixteen or more characters with no path or word breaks in it, mixing letters and digits.
  String? keyLike(String text) {
    for (final run in RegExp(r'[A-Za-z0-9+/=_-]{16,}').allMatches(text)) {
      for (final piece in run.group(0)!.split(RegExp(r'[/_-]'))) {
        if (piece.length >= 16 && RegExp(r'\d').hasMatch(piece) && RegExp('[A-Za-z]').hasMatch(piece)) return piece;
      }
    }
    return null;
  }

  final heading = RegExp(r'^# (.+)\n');

  group('the book', () {
    test('is an index whose chapters are exactly the chapter files, in the order of their names', () {
      expect(files, hasLength(44));
      // The count About's row gives, and the list the loader reads by, both held to the folder.
      expect(guideChapters, files.length);
      expect(about.guideChapters, files.length);
      expect(guideChapterFiles, [for (final (name, _) in files) name]);
      expect([for (final (name, _) in files) name.substring(0, 2)], [for (var i = 0; i < files.length; i++) '${i + 1}'.padLeft(2, '0')]);
      expect(isBookBody(book.index), isTrue);
      expect(noteTitle(book.index), guideTitle);
      final fileTitles = [for (final (_, body) in files) heading.firstMatch(body)?.group(1)];
      expect([for (final chapter in chaptersOf(book.index)) chapter.title], fileTitles);
      expect(titles, fileTitles);
      // Numbered straight through the parts, one to forty-four, none of them a part of another.
      expect(numbered(chaptersOf(book.index)), [for (var i = 0; i < titles.length; i++) '${i + 1}']);
    });

    test('opens every chapter with its own title as its heading, and names it so', () {
      for (final (name, body) in files) {
        final title = heading.firstMatch(body)?.group(1);
        expect(title, isNotNull, reason: name);
        expect(noteTitle(body), title, reason: name);
      }
    });

    test('points every link at a page of the book or a note Settings adds, and every link to a line at an item it has', () {
      final known = [...titles, guideTitle, ...builtIn];
      final lost = <String>[];
      var checked = 0;
      for (final page in pages) {
        final words = prose(page.body);
        for (final link in wikiLinksIn(words)) {
          checked += 1;
          if (!known.any((title) => sameTitle(title, link.title))) lost.add('${page.name}: [[${link.title}]]');
        }
        // `[[#^an-anchor]]` is this page's own item; the item may sit in an example block, where a board still reads it.
        final anchors = {for (final item in itemsIn(page.body)) item.id};
        for (final found in RegExp(r'\[\[#\^([a-z0-9-]+)\]\]').allMatches(words)) {
          checked += 1;
          if (!anchors.contains(found.group(1))) lost.add('${page.name}: [[#^${found.group(1)}]]');
        }
      }
      expect(lost, isEmpty);
      // Every chapter ends on three, and the index names all forty-four: a count this low means nothing was read.
      expect(checked, greaterThan(44 * 3 + 44));
      // The examples in code are not links, and are not read as any: the canvas frame, written in backticks.
      expect(wikiLinksIn(prose('Write `![[Cabin weekend, laid out]]` alone.')), isEmpty);
    });

    test('shares no title with another page or with the notes Settings adds', () {
      final all = [guideTitle, ...titles];
      for (final title in all) {
        expect(builtIn.where((one) => sameTitle(one, title)), isEmpty, reason: title);
        expect(all.where((other) => sameTitle(other, title)), hasLength(1), reason: title);
      }
    });

    test('holds nothing that looks like a secret', () {
      final found = <String>[];
      for (final page in pages) {
        for (final (what, pattern) in secrets) {
          final hit = pattern.firstMatch(page.body);
          if (hit != null) found.add('${page.name}: $what (${hit.group(0)})');
        }
        final key = keyLike(page.body);
        if (key != null) found.add('${page.name}: a key ($key)');
      }
      expect(found, isEmpty);
    });

    test('knows a secret when it sees one', () {
      final hits = ['ssh root@203.0.113.9', 'password: hunter2', 'curl ?token=abc', 'SSHPASS=x sshpass', 'sha 9f86d081884c7d659a2feaa0c55ad015'].where((text) => secrets.any((secret) => secret.$2.hasMatch(text)));
      expect(hits, hasLength(5));
      expect(keyLike('Authorization: Bearer sk-ant-api03-Zx9Qb7LmT2vWc4Yh'), 'Zx9Qb7LmT2vWc4Yh');
      expect(keyLike('src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph/MainActivity.kt'), isNull);
    });

    // The Marks plugin's marks against the chapters that teach them, read from the plugin, so a mark added or cut is
    // a chapter to change.
    test('teaches every mark the Marks plugin has: typed in its table, shown at work, said around its words, and counted', () {
      String chapter(String number) => files.where((file) => file.$1.startsWith('$number-')).firstOrNull?.$2 ?? '';
      List<String> rows(String body) => body.split('\n').where((line) => line.startsWith('| ')).toList();
      const words = ['none', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen'];
      final own = marks.where((mark) => mark.look is! EffectLook).toList();
      final effects = marks.where((mark) => mark.look is EffectLook).toList();
      expect(own.length + effects.length, marks.length);

      // The marks chapter: a row for each of its own, the mark typed in it, the line that shows them at work, and its count.
      final taught = chapter('04');
      final atWork = taught.split('\n').where((line) => line.startsWith('Here they are at work:')).firstOrNull ?? '';
      for (final mark in own) {
        final typed = mark.delimiter.replaceAll('|', r'\|');
        expect(rows(taught).any((row) => row.startsWith('| ${mark.name} |') && row.contains('`$typed')), isTrue, reason: '${mark.name} in the table');
        expect(atWork, contains(mark.delimiter), reason: '${mark.name} at work');
      }
      expect(taught, contains('## Ghost.md\'s own ${words[own.length]}'));
      expect(taught, contains('the ${words[own.length]} marks it adds of its own'));

      // The effects chapter: each effect typed, and said.
      for (final mark in effects) {
        final row = rows(chapter('05')).where((line) => line.startsWith('| ${mark.name} |')).firstOrNull;
        expect(row, contains('`${mark.delimiter}'), reason: '${mark.name} in the effects table');
        expect(row, contains('"${mark.cue} … end ${mark.cue}"'));
      }

      // The cues chapter: every mark said around its words, the spoiler in a sentence of its own under the table.
      final saying = chapter('10');
      for (final mark in marks) {
        expect(mark.cue, isNotEmpty, reason: mark.name);
        if (mark.name == 'Spoiler') {
          expect(saying.toLowerCase(), contains('“${mark.cue} … end ${mark.cue}”'));
        } else {
          expect(rows(saying).any((row) => row.contains('“${mark.cue} … end ${mark.cue}”') && row.contains('`${mark.delimiter}…${mark.delimiter}`')), isTrue, reason: '${mark.name} said');
        }
      }

      // The two chapters that count them, by the plugin.
      final count = words[marks.length];
      final seam = rows(chapter('32')).where((row) => row.startsWith('| `marks` |')).firstOrNull ?? '';
      expect(seam, contains('${count[0].toUpperCase()}${count.substring(1)} inline formats'));
      for (final mark in own) {
        expect(seam, contains(mark.name.toLowerCase()));
      }
      expect(seam, contains('${words[effects.length]} effects'));
      expect(chapter('30'), contains('the Marks plugin\'s $count formats'));
    });

    test('is in the app’s own bundle, by the asset lines of pubspec.yaml', () async {
      final shipped = await loadGuideBook();
      expect(shipped.index, book.index);
      expect([for (final chapter in shipped.chapters) chapter.body], [for (final chapter in book.chapters) chapter.body]);
    });

    test('is the web app’s own Markdown, byte for byte, where ../glyph is beside the repository', () {
      final web = Directory('../glyph/src/app/guidebook');
      if (!web.existsSync()) {
        markTestSkipped('../glyph is not beside the repository');
        return;
      }
      final theirs = web.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.md')).toList();
      expect(theirs, hasLength(45));
      for (final file in theirs) {
        final at = file.path.substring(web.path.length + 1);
        final ours = File('assets/guidebook/$at');
        expect(ours.existsSync(), isTrue, reason: at);
        expect(ours.readAsBytesSync(), file.readAsBytesSync(), reason: at);
      }
      // And nothing of ours that is not theirs.
      expect(Directory('assets/guidebook').listSync(recursive: true).whereType<File>(), hasLength(45));
    });
  });

  group('adding the book', () {
    // A clock that moves, so a list sorted newest first is in the order the notes were made.
    late int clock;
    late SampleLibrary library;
    setUp(() {
      clock = 1760000000000;
      library = SampleLibrary(const [], clock: () => clock += 1000);
    });
    List<Note> listed() => listOrderNewest(library.value);

    test('makes every chapter and the index, and answers the index, which reads as the book', () async {
      final index = await addGuideBook(library, library.value, bundle: bundle);
      expect(isBookBody(index.body), isTrue);
      expect(noteTitle(index.body), guideTitle);
      final notes = listed();
      expect(notes, hasLength(45));
      // Newest first: the index, then the book from its first chapter, so Recent opens at the start.
      expect([for (final note in notes.take(3)) noteTitle(note.body)], [guideTitle, titles[0], titles[1]]);
      expect([for (final note in notes) noteTitle(note.body)]..sort(), [guideTitle, ...titles]..sort());
      // The home page knows them as the Guide's: its pages by the index, and the book itself.
      expect(guidePages(notes), hasLength(44));
      expect(isGuideBook(index), isTrue);
    });

    test('twice gives one book, opened the second time rather than made again', () async {
      final first = await addGuideBook(library, library.value, bundle: bundle);
      final second = await addGuideBook(library, library.value, bundle: bundle);
      expect(second.id, first.id);
      expect(library.value, hasLength(45));
    });

    test('leaves a chapter a note already has by that title, and makes one again where that note is archived', () async {
      final mine = await library.createNote('# Live typing\n\nMy own notes on it.');
      await addGuideBook(library, library.value, bundle: bundle);
      expect(library.value, hasLength(45));
      expect([for (final note in library.value.where((note) => sameTitle(noteTitle(note.body), 'Live typing'))) note.id], [mine.id]);

      library = SampleLibrary(const [], clock: () => clock += 1000);
      final put = await library.createNote('# Live typing\n\nPut away.');
      await library.archive(put.id, archived: true);
      await addGuideBook(library, library.value, bundle: bundle);
      expect(library.value.where((note) => sameTitle(noteTitle(note.body), 'Live typing')), hasLength(2));
    });
  });
}

/// Newest edit first, as the page's store lists them.
List<Note> listOrderNewest(List<Note> notes) => [...notes]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
