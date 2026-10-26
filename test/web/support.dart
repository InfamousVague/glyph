// What the web build's tests share: a stand-in for the browser's core (native/web) in the VM, where its WebAssembly
// cannot be opened. Only what lib/web/web_store.dart asks of it: a note's path, by the rules of
// native/web/src/paths.rs, which tool/web_core_vectors.mjs holds the real one to; a digest; an id. Every other
// command is handed to [rest] (the Mac's core, where a test opens it) or refused, as the worker refuses it.
import 'dart:convert';

import 'package:crypto/crypto.dart' as hash;
import 'package:ghost_md/core/bytes.dart';
import 'package:ghost_md/core/native/core.dart';

/// A title's file stem, near enough to names.rs `file_stem(title_of(..))` for these tests' titles: the first line
/// with words, its heading marks and the characters a file name cannot hold taken out; `Untitled` for none.
String stemOf(String body) {
  final line = body.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');
  final words = line.replaceFirst(RegExp(r'^#+\s*'), '').replaceAll(RegExp(r'[/\\:*?"<>|#^\[\]]'), '').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
  return words.isEmpty ? 'Untitled' : words;
}

String _folderOf(String path) => path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
String _inFolder(String folder, String name) => folder.isEmpty ? name : '$folder/$name';

bool _namedFor(String path, String stem) {
  final name = path.split('/').last;
  if (!name.endsWith('.md')) return false;
  final bare = name.substring(0, name.length - 3);
  return bare == stem || RegExp('^${RegExp.escape(stem)} \\d+\$').hasMatch(bare);
}

bool _libraryPath(String path) => path.toLowerCase().endsWith('.md') && path.split('/').every((part) => part.isNotEmpty && !part.startsWith('.'));

/// paths.rs `note_path`, in Dart.
String notePath({required String body, String? path, String? wanted, required List<String> taken}) {
  final stem = stemOf(body);
  String free(String folder) {
    var name = '$stem.md';
    for (var n = 2; taken.contains(_inFolder(folder, name)); n += 1) {
      name = '$stem $n.md';
    }
    return _inFolder(folder, name);
  }

  final want = wanted != null && _libraryPath(wanted) ? wanted : null;
  var at = path ?? free(want == null ? 'Inbox' : _folderOf(want));
  if (want != null && want != at && !taken.contains(want)) {
    at = want;
  } else if (!_namedFor(at, stem)) {
    at = free(_folderOf(at));
  }
  return at;
}

var _ids = 0;

/// The browser's core, as far as the web store asks it.
CoreInvoke browserCoreStandIn({CoreInvoke? rest}) => (command, [args = const {}]) async {
  switch (command) {
    case 'note_path':
      return notePath(body: args['body'] as String, path: args['path'] as String?, wanted: args['wanted'] as String?, taken: (args['taken'] as List).cast<String>());
    case 'sha256_16':
      return toHex(hash.sha256.convert(fromBase64Url(args['data'] as String)).bytes.sublist(0, 16));
    case 'new_id':
      return 'web-${_ids += 1}';
  }
  if (rest != null) return rest(command, args);
  throw CoreError('Ghost.md\'s core in the browser has no command named $command.');
};

/// A note's JSON as the old web app's store.ts kept it in `glyph-notes`.
String oldPageNotes(List<Map<String, Object?>> notes) => jsonEncode(notes);
