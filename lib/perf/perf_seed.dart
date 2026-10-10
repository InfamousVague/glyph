/// A library the size of a real one, for a build made to be measured (`--dart-define=GHOST_PERF_SEED=350`).
///
/// A fresh library has eight notes, and an app with eight notes is fast whatever it does. The person this is
/// measured for has about three hundred and fifty: mostly short notes, a few long ones of ten thousand letters and
/// more, notebooks with their tickets, boards, canvases and a journal. So the core is given that many before the
/// app reads it, made from the examples the app itself ships (lib/core/sample_library.dart), each under a name of
/// its own so the lists, the links and the queries have that much to read.
///
/// Only ever in a build that measures itself, which is a build with its own id and its own folder
/// (tool/perf.sh): never a library a person keeps.
library;

import 'dart:io';

import '../core/native/core.dart';
import '../core/native/device_paths.dart';
import '../core/sample_library.dart';
import 'perf_run.dart' show PerfLaunch;

/// How many notes a measured build's library is brought up to (`--dart-define=GHOST_PERF_SEED=<n>`); 0 leaves the
/// library as it is.
const int ghostPerfSeed = int.fromEnvironment('GHOST_PERF_SEED');

/// Brings the library up to [want] notes, and answers how many it made. Asked again with the notes already there,
/// it makes none.
Future<int> seedPerfLibrary(CoreInvoke core, int want) async {
  if (!await _measuredLibrary()) return 0;
  final listed = await core('list_notes');
  final have = listed is List ? listed.length : 0;
  if (have >= want) return 0;
  final examples = [...seedLibrary(null), ...starterNotes(DateTime.now().millisecondsSinceEpoch)];
  var made = 0;
  for (var i = have; i < want; i += 1) {
    final body = perfBody(examples[i % examples.length].body, i);
    try {
      await core('create_note', {'id': 'perf-${i.toString().padLeft(4, '0')}', 'body': body, 'source': 'editor'});
      made += 1;
    } on CoreError {
      // An id from a run before: the note is there already.
    }
  }
  // The four the walk opens (lib/perf/perf_run.dart `benchScript`), made last so they lead the home page.
  final canvas = examples.firstWhere((note) => note.body.contains('"nodes"'), orElse: () => examples.first).body;
  final bench = {
    'perf-bench-notebook': _named(exampleNotebookBody(), 'Bench notebook'),
    'perf-bench-canvas': _named(canvas, 'Bench canvas'),
    'perf-bench-board': _named(boardNoteBody, 'Bench board'),
    'perf-bench-long': _long(_named(sampleNoteBody, 'Bench long'), sampleNoteBody),
  };
  for (final entry in bench.entries) {
    try {
      await core('create_note', {'id': entry.key, 'body': entry.value, 'source': 'editor'});
      made += 1;
    } on CoreError {
      // There already.
    }
  }
  return made;
}

/// Whether the library this build has open is one made to be filled: a desktop build's only in the folder its
/// environment names (`GHOST_PERF_DIR`, tool/perf.sh), a phone's only in the app whose id says it is the measured
/// one (`….flutter.perf`, android/app/build.gradle.kts `GHOST_PERF_ID`). A measured build opened any other way, a
/// double click on the Mac's profile app, the same apk under the app's own id, has a person's notes in front of it,
/// and theirs is a library that syncs: it is left as it is.
Future<bool> _measuredLibrary() async {
  if (PerfLaunch.dirs() != null) return true;
  if (!Platform.isAndroid) return false;
  try {
    return (await DevicePaths.find()).dataDir.contains('.flutter.perf');
  } catch (_) {
    return false;
  }
}

/// [body] under [name]: its first heading, or its front matter's title, said again.
String _named(String body, String name) {
  final lines = body.split('\n');
  for (var at = 0; at < lines.length; at += 1) {
    if (lines[at].startsWith('# ')) {
      lines[at] = '# $name';
      break;
    }
    if (lines[at].startsWith('title:')) {
      lines[at] = 'title: "$name"';
      break;
    }
  }
  return lines.join('\n');
}

/// [body] made long by [example]'s words said again under headings of their own, to twelve thousand letters.
String _long(String body, String example) {
  final again = example.replaceFirst(RegExp(r'^---\n[\s\S]*?\n---\n'), '').replaceFirst(RegExp(r'^# .*\n', multiLine: true), '');
  final more = StringBuffer(body);
  for (var part = 2; more.length < 12000; part += 1) {
    more
      ..write('\n\n## Again, part $part\n\n')
      ..write(again);
  }
  return more.toString();
}

/// One of the examples as note [i] of a big library: its first heading (or its title in the front matter) given the
/// number, so no two share a name, and every tenth made long by its own words said again, since a long note is
/// where typing and scrolling are felt.
String perfBody(String example, int i) {
  final lines = example.split('\n');
  for (var at = 0; at < lines.length; at += 1) {
    final line = lines[at];
    if (line.startsWith('# ') || line.startsWith('title:')) {
      final quoted = line.endsWith('"');
      lines[at] = quoted ? '${line.substring(0, line.length - 1)} $i"' : '$line $i';
      break;
    }
  }
  final body = lines.join('\n');
  // A canvas is its JSON, and a notebook's index its list: neither is made longer by saying it twice.
  if (i % 10 != 3 || body.contains('"nodes"') || body.contains('book: true')) return body;
  return _long(body, example);
}
