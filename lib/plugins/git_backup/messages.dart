/// The commit messages (docs/MARKDOWN_FIRST.md §10 Cadence, as Matt had them on 2026-10-31): `Edit: Title` for one
/// note changed; `3 notes changed: First, Second…` for several; `New:`, `Moved:`, `Trashed:` or `Deleted:`
/// where that one kind is the whole change; and plain words for a change with no note in it (a picture, the config).
library;

import 'repo.dart';

/// What a note's path says of it: its title, from the file's name (the title line is the truth, but the file is
/// named after it, and a removed note has no body to read).
String titleOfPath(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

bool _isNote(String path) => path.toLowerCase().endsWith('.md') && !path.split('/').any((part) => part.startsWith('.'));

bool _isVersions(String path) => path.endsWith('.versions');

/// Whether [path] is inside `.trash/` (the trash folder decision 2 names; nothing writes it yet).
bool _inTrash(String path) => path.startsWith('.trash/') || path.contains('/.trash/');

/// The message for a commit of [changes], with [titleOf] reading a note's title where the file is still there
/// (null for the file's name).
String commitMessage(List<GitChange> changes, {String? Function(String path)? titleOf}) {
  String title(String path) => titleOf?.call(path) ?? titleOfPath(path);
  final notes = [for (final c in changes) if (_isNote(c.path)) c];
  if (notes.isEmpty) {
    final versions = changes.where((c) => _isVersions(c.path)).length;
    if (versions > 0 && versions == changes.length) return versions == 1 ? 'History of ${title(changes.single.path.replaceFirst(RegExp(r'\.versions$'), ''))}' : 'History of $versions notes';
    final pictures = changes.where((c) => c.path.startsWith('image/')).length;
    final files = changes.where((c) => c.path.startsWith('file/')).length;
    final recordings = changes.where((c) => c.path.startsWith('recordings/')).length;
    if (pictures > 0 && pictures == changes.length) return pictures == 1 ? 'A picture' : '$pictures pictures';
    if (files > 0 && files == changes.length) return files == 1 ? 'A file' : '$files files';
    if (recordings > 0 && recordings == changes.length) return recordings == 1 ? 'A recording' : '$recordings recordings';
    if (changes.every((c) => c.path.startsWith('.glyph/') || c.path == '.gitignore' || c.path == 'README.txt' || c.path.startsWith('.github/'))) return 'Library settings';
    return changes.length == 1 ? 'Changed: ${changes.single.path}' : '${changes.length} files changed';
  }
  if (notes.length == 1) {
    final one = notes.single;
    return switch (one.kind) {
      'added' => _inTrash(one.path) ? 'Trashed: ${title(one.path)}' : 'New: ${title(one.path)}',
      'removed' => 'Deleted: ${title(one.path)}',
      'renamed' => _inTrash(one.path) ? 'Trashed: ${title(one.path)}' : 'Moved: ${title(one.path)}',
      _ => 'Edit: ${title(one.path)}',
    };
  }
  final kinds = notes.map((c) => c.kind).toSet();
  final titles = notes.map((c) => title(c.path)).toList();
  final first = titles.take(2).join(', ');
  final more = titles.length > 2 ? '…' : '';
  if (kinds.length == 1) {
    final word = switch (kinds.single) {
      'added' => notes.every((c) => _inTrash(c.path)) ? 'Trashed' : 'New',
      'removed' => 'Deleted',
      'renamed' => notes.every((c) => _inTrash(c.path)) ? 'Trashed' : 'Moved',
      _ => null,
    };
    if (word != null) return '$word: $first$more';
  }
  return '${notes.length} notes changed: $first$more';
}

/// The merge commit's message, when the remote moved and this device put the two together.
String mergeMessage({required int theirs, required int conflicts}) {
  final from = theirs == 1 ? 'a commit' : '$theirs commits';
  return conflicts == 0 ? 'Merge $from from the remote' : 'Merge $from from the remote, $conflicts ${conflicts == 1 ? 'conflict copy' : 'conflict copies'} kept';
}
