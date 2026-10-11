/// A note's versions file: `<Title>.versions`, beside the note's `.md`, holding every version kept of it. A port of
/// `src/app/core/versions/file.ts`. (Matt: "create a special file like a versions files that efficiently tracks
/// changes in a way that can be shared via a file it doesn't need to be super human readable but it should be at
/// least a bit (like a yarn lock)".)
///
///     # Ghost.md versions 1
///     # note gho-7f3a
///
///     v1 2026-10-04T15:20:01.000Z matt 3f9a21c0
///       +# Launch plan
///       +- book the venue
///     v2 2026-10-04T16:02:44.000Z matt 8c0d4e11 "Before the review"
///       =1
///       -- book the venue
///       +- book the venue (done)
///
/// A version is its head line - its number, when, who, the hash of the note's whole text then, and a name if it was
/// given one - and under it, indented, the change from the version before: `=N` keeps N lines, `-` takes a line out
/// and `+` puts one in, each line as it was. So the file grows by what changed, not by the note each time, and a
/// person can still read what each version did. A version marked `full` holds the whole note rather than a change:
/// one in every [fullEvery], so a file that lost its oldest versions to [mostVersions] still starts somewhere, and a
/// damaged version costs only the ones up to the next full one.
///
/// Reading a file rebuilds each version and checks it against its hash; a version that does not come out as written
/// is dropped, never shown as something it was not. Two devices' files are merged version by version
/// ([mergeFiles]), by when each was kept, who kept it and its hash, so a timeline kept on two devices is one
/// timeline after a sync.
///
/// The file is the WIRE between this app and the web's: what [writeFile] writes for a list of versions is, byte for
/// byte, what the page writes for it (the head's time as `toISOString` writes it, the name as `JSON.stringify`
/// does). What differs:
/// - [mergeFiles] orders two versions kept in the same millisecond by who kept them, which the page asks of
///   `localeCompare`. Dart has no collation, so [compareAsPage] gives the browser's order for the characters a
///   handle, a hash and an id are made of (`_ - .`, then digits, then letters with case second), and the code
///   units' order for anything else. Two devices only disagree where two people with handles outside that alphabet
///   kept a version in the same millisecond.
/// - Reading and writing the file's bytes is `versions_store.dart`, which was here first; this is the text.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'versions_diff.dart';

/// The format's number, said in the file's first line (`FORMAT`).
const int versionsFormat = 1;
const String _magic = '# Ghost.md versions';

/// A whole note rather than a change, every this many versions (`FULL_EVERY`).
const int fullEvery = 50;

/// The most versions a file keeps: the oldest go first (`MOST_VERSIONS`).
const int mostVersions = 1000;

/// What a version is kept from: when, who, the name it was given, and the note's words then.
@immutable
class VersionWords {
  const VersionWords({required this.at, required this.by, required this.text, this.label});

  /// When it was kept, in ms.
  final int at;

  /// Who kept it: their handle, or `me` without an account.
  final String by;

  /// The name it was given, if any.
  final String? label;

  /// The note's whole text then.
  final String text;
}

/// A version as read from a file (`Version`).
@immutable
class Version extends VersionWords {
  const Version({required this.n, required super.at, required super.by, required this.hash, super.label, required super.text, required this.added, required this.removed});

  /// Its place in the file, from 1.
  final int n;

  /// The hash of the note's text then ([hashText]).
  final String hash;

  /// How many lines it put in and took out against the version before.
  final int added;
  final int removed;

  /// The same version under [label].
  Version named(String label) => Version(n: n, at: at, by: by, hash: hash, label: label, text: text, added: added, removed: removed);
}

/// A versions file, read (`VersionsFile`).
@immutable
class VersionsFile {
  const VersionsFile({required this.noteId, required this.versions, required this.damaged});
  final String noteId;
  final List<Version> versions;

  /// Versions in the file that did not come out as their hash says, and were left out.
  final int damaged;
}

/// FNV-1a over the text's UTF-16 units, as eight hex digits: enough to tell a version rebuilt wrong from one rebuilt
/// right (`hashText`).
String hashText(String text) {
  var hash = 0x811c9dc5;
  for (var i = 0; i < text.length; i += 1) {
    hash ^= text.codeUnitAt(i);
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Who may keep a version, as a word with no spaces in it (`who`).
String _who(String by) {
  final word = by.replaceAll(RegExp(r'\s+'), '-');
  return word.isEmpty ? 'me' : word;
}

// --- reading ---------------------------------------------------------------------------------------------------------

final RegExp _head = RegExp(r'^v(\d+) (\S+) (\S+) ([0-9a-f]{8})( full)?(?: (".*"))?$');

/// The time a head line says, in ms; 0 for one that is no time (`Date.parse`, and its NaN).
int _timeOf(String text) => DateTime.tryParse(text)?.millisecondsSinceEpoch ?? 0;

/// JS's `Number(text) || 0`, for the whole numbers a keep is written as.
int _countOf(String text) => int.tryParse(text.trim()) ?? 0;

/// A versions file read and every version in it rebuilt; null where the text is not a versions file at all
/// (`readFile`).
VersionsFile? readFile(String file) {
  final lines = file.split('\n');
  if (!lines[0].startsWith(_magic)) return null;
  var noteId = '';
  final versions = <Version>[];
  var damaged = 0;
  List<String>? previous = [];
  ({int at, String by, String hash, String? label, bool full})? head;
  var steps = <Step>[];

  void close() {
    final open = head;
    if (open == null) return;
    final base = open.full ? const <String>[] : previous;
    final rebuilt = base != null ? applySteps(base, steps) : null;
    final text = rebuilt?.join('\n');
    if (rebuilt != null && text != null && hashText(text) == open.hash) {
      final changed = open.full && versions.isNotEmpty ? countSteps(diffLines(previous ?? const [], rebuilt)) : countSteps(steps);
      versions.add(Version(n: versions.length + 1, at: open.at, by: open.by, hash: open.hash, label: open.label, text: text, added: changed.added, removed: changed.removed));
      previous = rebuilt;
    } else {
      damaged += 1;
      // The versions after it are changes to one that is not there: none is read until the next full one.
      previous = null;
    }
    head = null;
    steps = [];
  }

  for (final line in lines.skip(1)) {
    if (line.startsWith('# note ')) {
      noteId = line.substring('# note '.length).trim();
      continue;
    }
    if (line.startsWith('#') || (line.isEmpty && head == null)) continue;
    final match = _head.firstMatch(line);
    if (match != null) {
      close();
      String? label;
      final quoted = match[6];
      if (quoted != null) {
        try {
          final said = jsonDecode(quoted);
          if (said is String && said.isNotEmpty) label = said;
        } on FormatException {
          label = null;
        }
      }
      head = (at: _timeOf(match[2]!), by: match[3]!, hash: match[4]!, label: label, full: match[5] != null);
      continue;
    }
    if (head == null) continue;
    if (line.startsWith('  =')) {
      steps.add(Keep(_countOf(line.substring(3))));
    } else if (line.startsWith('  -')) {
      steps.add(Del(line.substring(3)));
    } else if (line.startsWith('  +')) {
      steps.add(Add(line.substring(3)));
    }
    // A line between versions that is none of these (an empty one, a stray edit): the version is checked by its hash.
  }
  close();
  return VersionsFile(noteId: noteId, versions: versions, damaged: damaged);
}

// --- writing ---------------------------------------------------------------------------------------------------------

String _stepLine(Step step) => switch (step) {
      Keep(:final count) => '  =$count',
      Del(:final line) => '  -$line',
      Add(:final line) => '  +$line',
    };

/// A time as the page's `toISOString` writes it: UTC, to the millisecond.
String _iso(int at) => DateTime.fromMillisecondsSinceEpoch(at, isUtc: true).toIso8601String();

/// The whole file for [versions], numbered afresh, each written as its change from the one before (`writeFile`).
String writeFile(String noteId, List<VersionWords> versions) {
  final kept = versions.length > mostVersions ? versions.sublist(versions.length - mostVersions) : versions;
  final out = ['$_magic $versionsFormat', '# note $noteId', '# A version is the change from the one before it: "=N" keeps N lines, "-" takes a line out, "+" puts one in.', ''];
  var previous = <String>[];
  for (final (at, version) in kept.indexed) {
    final lines = linesOf(version.text);
    // The first a file holds is always whole, and one in every fullEvery after it.
    final full = at % fullEvery == 0;
    final name = version.label;
    final label = name != null && name.isNotEmpty ? ' ${jsonEncode(name)}' : '';
    out.add('v${at + 1} ${_iso(version.at)} ${_who(version.by)} ${hashText(version.text)}${full ? ' full' : ''}$label');
    out.addAll((full ? [for (final line in lines) Add(line)] : diffLines(previous, lines)).map(_stepLine));
    previous = lines;
  }
  return '${out.join('\n')}\n';
}

/// The file with a version of [text] kept at the end, or null where there is nothing to keep: the last version
/// already holds this text, and it is not being given a name (`withVersion`). A file that is not a versions file is
/// started again.
String? withVersion(String? file, String noteId, String text, {required int at, required String by, String? label}) {
  final read = file != null && file.isNotEmpty ? readFile(file) : null;
  final versions = read?.versions ?? const <Version>[];
  final last = versions.isEmpty ? null : versions.last;
  final trimmed = label?.trim();
  final name = trimmed == null || trimmed.isEmpty ? null : trimmed;
  if (last != null && last.text == text) {
    if (name == null || last.label == name) return null;
    // The same words, named now: the name goes on the version that has them, rather than a version of no change.
    return writeFile(noteId, [...versions.take(versions.length - 1), last.named(name)]);
  }
  return writeFile(noteId, [...versions, VersionWords(at: at, by: by, text: text, label: name)]);
}

/// A version's key across devices: when it was kept, who kept it and what it held (`keyOf`).
String _keyOf(Version version) => '${version.at}|${version.by}|${version.hash}';

int _weight(int unit) {
  if (unit == 0x5f) return 1; // _
  if (unit == 0x2d) return 2; // -
  if (unit == 0x2e) return 3; // .
  if (unit >= 0x30 && unit <= 0x39) return 10 + unit - 0x30;
  if (unit >= 0x61 && unit <= 0x7a) return 30 + unit - 0x61;
  if (unit >= 0x41 && unit <= 0x5a) return 30 + unit - 0x41;
  return 1000 + unit;
}

/// [a] against [b] as the page's `localeCompare` orders them, for the characters a handle, a hash and an id are
/// made of (see the header): `_`, `-`, `.`, then digits, then letters, case told apart only between words otherwise
/// the same, lower case first. Anything else goes after, by its code unit.
int compareAsPage(String a, String b) {
  final shared = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < shared; i += 1) {
    final by = _weight(a.codeUnitAt(i)).compareTo(_weight(b.codeUnitAt(i)));
    if (by != 0) return by;
  }
  if (a.length != b.length) return a.length.compareTo(b.length);
  for (var i = 0; i < shared; i += 1) {
    final x = a.codeUnitAt(i), y = b.codeUnitAt(i);
    // The same letter in another case: lower case first.
    if (x != y) return y.compareTo(x);
  }
  return 0;
}

/// Two files of one note's versions as one, as a sync meets them (`mergeFiles`): every version in either, once, in
/// the order they were kept, and a name given on either side kept. Null where neither is a versions file.
String? mergeFiles(String? mine, String? theirs, String noteId) {
  final a = mine != null && mine.isNotEmpty ? readFile(mine) : null;
  final b = theirs != null && theirs.isNotEmpty ? readFile(theirs) : null;
  if (a == null && b == null) return null;
  final all = <String, Version>{};
  for (final version in [...?a?.versions, ...?b?.versions]) {
    final key = _keyOf(version);
    final was = all[key];
    if (was == null || (was.label == null && version.label != null)) all[key] = version;
  }
  final ordered = all.values.toList()
    ..sort((x, y) {
      final when = x.at.compareTo(y.at);
      if (when != 0) return when;
      final who = compareAsPage(x.by, y.by);
      return who != 0 ? who : compareAsPage(x.hash, y.hash);
    });
  final id = a != null && a.noteId.isNotEmpty ? a.noteId : (b != null && b.noteId.isNotEmpty ? b.noteId : noteId);
  return writeFile(id, ordered);
}
