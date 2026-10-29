/// This device's meeting recordings, as a share reads them (lib/share/share_audio.dart): where the core keeps each
/// (`recordings/<note id>.wav`, lib/core/native/files.dart [CoreFiles.where]) and a megabyte of it at a time, read
/// from the file by Dart so an hour's recording is never held whole. In the web build there are no files to read, and
/// a browser has no meeting's recording anyway: share_recordings_web.dart answers none.
library;

import 'dart:io';

import '../core/native/files.dart';
import 'share_audio.dart';

/// [ShareRecordings] over the core's files.
class CoreRecordings implements ShareRecordings {
  const CoreRecordings(this.files);

  final CoreFiles files;

  @override
  Future<ShareRecording?> recordingOf(String noteId) async {
    ({String path, int bytes})? where;
    try {
      where = await files.where(CoreFileKind.recording, noteId);
    } catch (_) {
      where = null;
    }
    // A WAV's header alone is no recording.
    if (where == null || where.bytes <= 44) return null;
    final file = File(where.path);
    return ShareRecording(
      mime: 'audio/wav',
      bytes: where.bytes,
      read: (offset, length) async {
        final open = await file.open();
        try {
          await open.setPosition(offset);
          final bytes = await open.read(length);
          return bytes.length == length ? bytes : throw const FileSystemException('The recording changed while it was being sent.');
        } finally {
          await open.close();
        }
      },
    );
  }
}
