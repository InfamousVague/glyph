/// A note's versions file handed to the person (Matt: "a way that can be shared via a file"). A port of
/// `src/app/core/versions/share.ts`: answers what was done, in the words a toast says it.
///
/// The page tried, in order: the share sheet where it takes a file (`navigator.share`), a download in a browser, the
/// library's folder opened on the Mac (where the file is beside its note, `<Title>.versions`), and, where none of
/// those is there, the file's text copied. An Android WebView has no share sheet for a page and the app is not a
/// browser, so on the phone the page copies the text and says so; that is what this does there.
///
/// What differs: the first two ways are not here (no page, no browser). The Mac's folder is [files], given where the
/// build can show it (lib/core/library_files.dart). An iPhone's page shares the file through its own sheet; here it
/// is copied as on Android.
library;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';

import 'library_files.dart';
import 'versions_store.dart';

final RegExp _notInAName = RegExp(r'[\\/:*?"<>|]+');

/// The file's name: the note's title, less what a file's name cannot hold (`name`).
String versionsFileName(String title) => '${(title.trim().isEmpty ? 'Untitled' : title.trim()).replaceAll(_notInAName, ' ').trim()}.versions';

/// Hands over note [noteId]'s versions file (`shareVersionsFile`). [copy] is the clipboard's, the phone's own unless
/// a test brings one.
Future<String> shareVersionsFile(VersionsStore store, String noteId, String title, {LibraryFiles? files, Future<void> Function(String text)? copy, TargetPlatform? platform}) async {
  final text = await store.readVersionsFile(noteId);
  if (text == null || text.isEmpty) return 'This note has no versions yet.';
  final name = versionsFileName(title);
  if ((platform ?? defaultTargetPlatform) == TargetPlatform.macOS && files != null && await files.canBrowse()) {
    await files.browse();
    return '$name is beside the note in the folder that opened.';
  }
  await (copy ?? _copy)(text);
  return 'This device can’t send a file, so the versions file is copied as text.';
}

Future<void> _copy(String text) => Clipboard.setData(ClipboardData(text: text));
