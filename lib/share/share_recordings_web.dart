/// The web build's [CoreRecordings] (share_recordings.dart says why): there are no files to read a recording from in a
/// browser, and a meeting's recording stays on the device that recorded it, so a share made here carries none.
library;

import '../core/native/files.dart';
import 'share_audio.dart';

class CoreRecordings implements ShareRecordings {
  const CoreRecordings(this.files);

  final CoreFiles files;

  @override
  Future<ShareRecording?> recordingOf(String noteId) async => null;
}
