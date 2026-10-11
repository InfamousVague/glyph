/// The notes' folder, shown where the device shows folders (Matt: "add a browse local files button somewhere to open
/// the folder on the phones file browser"): the Files app on the phone, where the app lists its library as a place
/// of its own (android/…/glyph/files/LibraryDocuments.kt, read-only). A port of `src/app/core/libraryFiles.ts`, for
/// the sidebar's Browse files (lib/notes/note_tree.dart `onBrowseFiles`).
///
/// What differs:
/// - The page's imports (`window.GlyphHost.browseFiles`, `invoke`, the binary's generation) are one value,
///   [LibraryFiles], which the app's root makes and a test makes from fakes.
/// - **The phone is asked on `ghost_md/files`** (android/…/ghost_md/FilesBridge.kt): `canBrowseFiles` where the
///   page looked for the activity's function, `browseFiles` where it called it (LibraryFiles.kt). An Android run
///   with no phone half behind the channel, which a test is, is the page's "activity from before it": not offered.
/// - **No generation to wait for** (`FILES_GENERATION`, 18): the Dart and the phone's half are one build.
/// - **Not on a Mac yet.** The page asked Rust there (`library_reveal`, Finder through Tauri's opener). This core
///   has no such command (native/src/dispatch.rs names it among those not here), so off the phone the folder is
///   offered only where a way to show it is given ([LibraryFiles.new]'s `reveal`), and the app's root gives none.
/// - The sidebar asked the device itself as it was put up (NoteTree.tsx `browsable`); here it is handed the press
///   or nothing, so the asking is [LibraryFiles.offered], asked once by whoever builds the sidebar.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'library_folder.dart' show filesChannel;

/// The binary with `library_reveal` and the activity's `browseFiles` (`FILES_GENERATION`), kept for the record:
/// nothing here waits for it.
const int filesGeneration = 18;

/// The notes' folder as the app reaches it: the page's imports, as one value (see the header).
class LibraryFiles {
  LibraryFiles({Future<void> Function()? reveal, MethodChannel channel = filesChannel, TargetPlatform? platform})
      : _reveal = reveal,
        _channel = channel,
        _platform = platform;

  /// A desktop's way to show the folder (the page's `invoke('library_reveal')`: Finder on a Mac); null where this
  /// build has none.
  final Future<void> Function()? _reveal;
  final MethodChannel _channel;
  final TargetPlatform? _platform;

  bool get _phone => (_platform ?? defaultTargetPlatform) == TargetPlatform.android;

  /// The real iPhone app draws the tool and its press does nothing: `canBrowseFiles` answers by the binary's
  /// generation where there is no `GlyphHost`, an iPhone's binary is new enough, and `library_reveal` then has
  /// nothing to open there (NoteTree.tsx logs the failure and says nothing). Kept as the page has it.
  bool get _iPhone => (_platform ?? defaultTargetPlatform) == TargetPlatform.iOS;

  /// Whether this device can show the notes' folder (`canBrowseFiles`).
  Future<bool> canBrowse() async {
    if (_iPhone) return true;
    if (!_phone) return _reveal != null;
    try {
      return await _channel.invokeMethod<bool>('canBrowseFiles') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Shows the notes' folder: the Files app on the phone, Finder on a Mac (`browseFiles`).
  Future<void> browse() async {
    if (_iPhone) throw StateError('An iPhone has no way to show the notes’ folder.');
    if (_phone) {
      await _channel.invokeMethod<void>('browseFiles');
      return;
    }
    final reveal = _reveal;
    if (reveal == null) throw StateError('This device has no way to show the notes’ folder.');
    await reveal();
  }

  bool _asked = false;
  bool _can = false;

  /// The sidebar's Browse files (NoteTree.tsx `browsable` and its tool's press): nothing until this device has said
  /// it can show the folder, then the press. The device is asked once, the first time this is read, and [onKnown]
  /// is told when it has said yes, for the sidebar to be drawn again with its tool.
  VoidCallback? offered(VoidCallback onKnown) {
    if (!_asked) {
      _asked = true;
      unawaited(canBrowse().then<void>((can) {
        if (!can) return;
        _can = true;
        onKnown();
      }, onError: (Object _) {}));
    }
    return _can ? _press : null;
  }

  void _press() => unawaited(browse().then<void>((_) {}, onError: (Object failure) => debugPrint('[ghost] could not show the notes folder: $failure')));
}
