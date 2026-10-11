import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/capture_session.dart' show Phase;
import 'package:ghost_md/capture/screen_text.dart';

/// The recorder's own lines (lib/capture/screen_text.dart): the top line, and how a recording ends. Case for case
/// with the web's `capture/screenText.test.ts`.

/// The web's `{ ...listening, … }`: listening, no error, no download, no words yet, but for what a case says.
String? status({Phase phase = Phase.listening, String? error, ({num received, num total})? download, bool heardWords = false}) =>
    statusLine(phase: phase, error: error, download: download, heardWords: heardWords);

void main() {
  group('the top line', () {
    test('says what stands between the person and the recording', () {
      expect(status(phase: Phase.starting), 'Starting');
      expect(status(phase: Phase.finishing), 'Saving');
      expect(status(phase: Phase.failed), 'Could not start');
      expect(status(phase: Phase.failed, error: 'Local only is on'), 'Local only is on');
    });

    test('counts a download in megabytes, whatever the phase', () {
      expect(status(phase: Phase.starting, download: (received: 12400000, total: 60100000)), 'Downloading voice model 12 / 60 MB');
    });

    test('shows a problem only until the first words, and says nothing while it listens', () {
      expect(status(error: 'capture_push rejected'), 'Problem: capture_push rejected');
      expect(status(error: 'capture_push rejected', heardWords: true), isNull);
      expect(status(), isNull);
    });

    test('says where the words are going, and names no note over the lock screen', () {
      expect(whereLine(null, false), 'New note');
      expect(whereLine('# Weekend trip\n\nBook the cabin.', false), 'Adding to “Weekend trip”');
      // A meeting is recorded, not read, and its line says only that, whatever else is true.
      expect(whereLine(null, false, meeting: true), 'Meeting');
      expect(whereLine('# Weekend trip', true, routed: true, meeting: true), 'Meeting');
      expect(whereLine('# Weekend trip', true), 'Adding to your last note');
      // A note a command switched to, and one a card will make at Done.
      expect(whereLine('# House TODOs', false, routed: true), 'Adding to “House TODOs”');
      expect(whereLine('# House TODOs', true, routed: true), 'Adding to the note you named');
      expect(whereLine(null, false, named: 'Moon base'), 'New note “Moon base”');
      expect(whereLine(null, true, named: 'Moon base'), 'New note');
    });
  });

  group('how a recording ends', () {
    test('names the side key the way this phone stops with it', () {
      expect(stopHint(true, true, false), 'Press the side key to stop.');
      expect(stopHint(true, false, false), 'Hold the side key again to stop.');
      expect(stopHint(false, true, false), 'Press the side key to stop.');
    });

    test('says going quiet finishes it when that is on', () {
      expect(stopHint(false, false, true), 'Stop talking to finish, or tap Done.');
      expect(stopHint(true, false, true), 'Stop talking to finish, or hold the side key again.');
    });

    test('is Done otherwise', () {
      expect(stopHint(false, false, false), 'Tap Done to stop.');
    });
  });
}
