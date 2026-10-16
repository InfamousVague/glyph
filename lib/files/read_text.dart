/// The words read in a note's pictures and files, on this device (lib/files/read_pass.dart reads them), kept beside
/// each one, and what a search is told of them.
///
/// **The sidecar.** One plain text file beside the thing it was read in, named for it with `.ocr.txt` after:
///
///     images/5f0c2e9a-….jpg            a picture
///     images/5f0c2e9a-….jpg.ocr.txt    the words read in it
///     images/files/8d1e4b7c-….pdf      a file
///     images/files/8d1e4b7c-….pdf.ocr.txt
///
/// UTF-8, the words line by line as they were read. A file of several pages has each page's words in turn, the
/// pages apart by a form feed (U+000C), as `pdftotext` writes them, so page three's words are what comes after the
/// second form feed. A PDF's words are its own where it has them, and read off the page's picture where it has none
/// (a scan). An empty sidecar is a thing read and found to hold no words; none at all is a thing not read yet.
/// Any app can open one; nothing in it is needed to read the note, and it can always be made again.
///
/// It goes where the thing goes: into the export's zip and the backup beside it, removed with it, and synced with
/// it sealed under the account's key like every other file (`FileKind.text`, lib/sync/notes.dart). The service never
/// has the words in the clear.
///
/// **The search.** [ReadTexts] holds every sidecar's words in memory, read once at launch off the UI's work and
/// kept as each one is made or arrives. It is the one hook lib/core/note_text.dart's search reading takes
/// ([searchExtra]): a note is found by the words of what it shows, as if they were its own, and a row found that
/// way says where (lib/core/search_hits.dart, [readSnippet]): "…total due 42.10 in Lease.pdf, page 2".
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/attachment_refs.dart';
import '../core/images.dart' show imageRef;
import '../core/note_text.dart' show SearchExtra;
import 'attachment_store.dart' show attachmentsFolder, readTextSuffix;

/// What separates one page's words from the next in a sidecar.
const String pageBreak = '\f';

/// Something a note shows that words can be read in: a picture, by its name under `image/`, or a file, by its
/// name under `file/`.
@immutable
class ReadThing {
  const ReadThing.picture(this.name) : picture = true;
  const ReadThing.file(this.name) : picture = false;

  /// Read back from [key]; null for a key that is neither.
  static ReadThing? ofKey(String key) {
    if (key.startsWith('image/')) return ReadThing.picture(key.substring(6));
    if (key.startsWith('file/')) return ReadThing.file(key.substring(5));
    return null;
  }

  final bool picture;
  final String name;

  /// `image/<name>` or `file/<name>`: what sync carries its words by, and the index keys them by.
  String get key => picture ? 'image/$name' : 'file/$name';

  /// Whether words can be read in it here: a picture, or a file that is a picture or a PDF.
  bool get readable => picture || const <AttachmentKind>{AttachmentKind.pdf, AttachmentKind.picture}.contains(attachmentKindOf(name));

  @override
  bool operator ==(Object other) => other is ReadThing && other.picture == picture && other.name == name;

  @override
  int get hashCode => Object.hash(picture, name);

  @override
  String toString() => key;
}

/// Every picture and file a body shows, in order, without repeats.
List<ReadThing> thingsIn(String body) {
  final things = <ReadThing>[];
  final seen = <String>{};
  if (body.contains('](image/')) {
    for (final match in imageRef.allMatches(body)) {
      final name = match.group(2) ?? '';
      if (name.isNotEmpty && seen.add('image/$name')) things.add(ReadThing.picture(name));
    }
  }
  for (final name in attachmentNames(body)) {
    if (seen.add('file/$name')) things.add(ReadThing.file(name));
  }
  return things;
}

/// The pages of a sidecar's words.
List<String> pagesOf(String text) => text.split(pageBreak);

/// A sidecar's words for these pages.
String textOfPages(List<String> pages) => pages.map((page) => page.replaceAll(pageBreak, ' ').trimRight()).join(pageBreak);

/// The sidecars of one data folder, and every one's words in memory.
class ReadTexts extends ChangeNotifier implements SearchExtra {
  ReadTexts({required String dataDir}) : _images = '$dataDir/images';

  final String _images;

  /// Every sidecar's words, by its thing's key; empty until [load] has read them.
  final Map<String, String> _words = <String, String>{};
  bool _loaded = false;
  Future<void>? _loading;
  int _mark = 0;

  /// Moves whenever any words are made, arrive or go: a search reads its notes' words again then.
  @override
  int get mark => _mark;

  /// Whether the sidecars on disk have been read in.
  bool get loaded => _loaded;

  /// How many things have words here (an empty sidecar counts: it was read).
  int get count => _words.length;

  /// Where the words of [thing] are kept; null for a name that may not name a file.
  String? pathOf(ReadThing thing) {
    if (!(thing.picture ? _pictureName : attachmentName).hasMatch(thing.name)) return null;
    return thing.picture ? '$_images/${thing.name}$readTextSuffix' : '$_images/$attachmentsFolder/${thing.name}$readTextSuffix';
  }

  /// Whether [thing] has been read here.
  bool has(ReadThing thing) => _words.containsKey(thing.key);

  /// The words read in [thing], or null where it has not been read.
  String? wordsOf(ReadThing thing) => _words[thing.key];

  /// Every sidecar there is, read in off the UI's isolate. Once; again only after [forgetAll].
  Future<void> load() => _loading ??= () async {
        final found = await compute(_readAll, _images);
        // Words made or arrived while the folder was read are newer than what was on disk.
        for (final entry in found.entries) {
          _words.putIfAbsent(entry.key, () => entry.value);
        }
        _loaded = true;
        _changed();
      }();

  /// Keeps the words read in [thing], beside it, whole or not at all.
  Future<void> keep(ReadThing thing, String words) async {
    final path = pathOf(thing);
    if (path == null) return;
    final file = File(path);
    final part = File('$path.part');
    await file.parent.create(recursive: true);
    await part.writeAsString(words, flush: true);
    await part.rename(path);
    _words[thing.key] = words;
    _changed();
  }

  /// The words of [thing] as kept on disk, for sync to send; null where there are none.
  Future<String?> readKept(ReadThing thing) async {
    final had = _words[thing.key];
    if (had != null || _loaded) return had;
    final path = pathOf(thing);
    if (path == null) return null;
    try {
      return await File(path).readAsString();
    } on FileSystemException {
      return null;
    }
  }

  /// [thing] is gone, and its words with it.
  Future<void> forget(ReadThing thing) async {
    final path = pathOf(thing);
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Gone already.
      }
    }
    if (_words.remove(thing.key) != null) _changed();
  }

  /// Everything is gone (Erase everything removed the folder): nothing is held, and the folder is read again.
  void forgetAll() {
    _words.clear();
    _loaded = false;
    _loading = null;
    _changed();
  }

  void _changed() {
    _mark += 1;
    notifyListeners();
  }

  /// The words a search reads of a note beyond its own (lib/core/note_text.dart): every read thing's words, in
  /// the order the note shows them. Nothing for a note that shows nothing read, which is asked first.
  @override
  String of(String body) {
    if (_words.isEmpty) return '';
    if (!body.contains('](image/') && !body.contains('](file/')) return '';
    final out = StringBuffer();
    for (final thing in thingsIn(body)) {
      final words = _words[thing.key];
      if (words == null || words.isEmpty) continue;
      out
        ..write('\n')
        ..write(words.replaceAll(pageBreak, '\n'));
    }
    return out.toString();
  }

  /// The line a search row shows for a word found only in what a note shows, and where it was read.
  @override
  ({String text, String where})? snippet(String body, List<String> needles) => _words.isEmpty ? null : readSnippet(body, needles, wordsOf);
}

final RegExp _pictureName = RegExp(r'^[A-Za-z0-9_-]{1,64}\.(?:jpg|jpeg|png|webp)$');

/// Every sidecar under `images/` and `images/files/`, by key: read on a worker isolate.
Map<String, String> _readAll(String images) {
  final found = <String, String>{};
  void read(String folder, String prefix) {
    final dir = Directory(folder);
    if (!dir.existsSync()) return;
    for (final entry in dir.listSync(followLinks: false)) {
      if (entry is! File) continue;
      final file = entry.uri.pathSegments.last;
      if (!file.endsWith(readTextSuffix)) continue;
      final name = file.substring(0, file.length - readTextSuffix.length);
      try {
        found['$prefix$name'] = entry.readAsStringSync();
      } on FileSystemException {
        // Gone between the listing and the reading.
      } on FormatException {
        // Not UTF-8: not ours.
      }
    }
  }

  read(images, 'image/');
  read('$images/$attachmentsFolder', 'file/');
  return found;
}

/// The words a note's search found in one of the things it shows, cut around the first word found, and what to
/// call where: "in Lease.pdf, page 2", "in a picture". Null where none of [needles] is in any of their words.
({String text, String where})? readSnippet(String body, List<String> needles, String? Function(ReadThing thing) wordsOf, {int before = 36, int most = 120}) {
  for (final thing in thingsIn(body)) {
    final words = wordsOf(thing);
    if (words == null || words.isEmpty) continue;
    final lower = words.toLowerCase();
    if (lower.length != words.length) continue;
    var at = -1;
    for (final needle in needles) {
      if (needle.isEmpty) continue;
      final here = lower.indexOf(needle);
      if (here >= 0 && (at < 0 || here < at)) at = here;
    }
    if (at < 0) continue;
    final pages = pageBreak.allMatches(words.substring(0, at)).length;
    var start = at;
    while (start > 0 && words[start - 1] != '\n' && words[start - 1] != pageBreak && at - start < before) {
      start -= 1;
    }
    final opens = start > 0 && words[start - 1] != '\n' && words[start - 1] != pageBreak;
    if (opens) {
      final space = words.indexOf(' ', start);
      if (space >= 0 && space < at) start = space + 1;
    }
    var end = at;
    while (end < words.length && words[end] != '\n' && words[end] != pageBreak && end - start < most) {
      end += 1;
    }
    final runs = end < words.length && words[end] != '\n' && words[end] != pageBreak;
    final cut = words.substring(start, end).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cut.isEmpty) continue;
    final label = _labelOf(body, thing);
    final paged = !thing.picture && attachmentKindOf(thing.name) == AttachmentKind.pdf && pageBreak.allMatches(words).isNotEmpty;
    return (text: '${opens ? '…' : ''}$cut${runs ? '…' : ''}', where: 'in $label${paged ? ', page ${pages + 1}' : ''}');
  }
  return null;
}

/// What a person calls the thing: a file's own name, a picture's caption, or "a picture".
String _labelOf(String body, ReadThing thing) {
  if (thing.picture) {
    for (final match in imageRef.allMatches(body)) {
      if (match.group(2) == thing.name) {
        final caption = (match.group(1) ?? '').trim();
        if (caption.isNotEmpty && !caption.startsWith('video ')) return caption;
      }
    }
    return 'a picture';
  }
  for (final match in attachmentRef.allMatches(body)) {
    if (match.group(2) == thing.name) return match.group(1) ?? 'a file';
  }
  return 'a file';
}

/// The app's words read in things, once the device has said where its files are (lib/files/files_kit.dart).
ReadTexts? readTexts;
