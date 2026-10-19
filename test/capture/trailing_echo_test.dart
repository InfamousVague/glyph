import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/trailing_echo.dart';
import 'package:ghost_md/core/note.dart';

/// Whisper's echo at the end of a recording (lib/capture/trailing_echo.dart), case for case with the web's
/// `capture/trailingEcho.test.ts`.
void main() {
  group("Whisper's echo at the end of a recording", () {
    for (final (heard, kept) in [
      ('Add eggs to Go. Go.', 'Add eggs to Go.'),
      ('Add eggs to Go. Go. Go.', 'Add eggs to Go.'),
      ('Add to Go Detroit, Michigan and Marietta, Ohio. Go. Go.', 'Add to Go Detroit, Michigan and Marietta, Ohio.'),
      ('Put it on the work list. Work list.', 'Put it on the work list.'),
    ]) {
      test('drops it: $heard', () => expect(withoutTrailingEcho(heard), kept));
    }

    for (final heard in ['Add eggs to Go.', 'We should go. Now.', 'It was fun. Really fun, actually, the whole day.', 'Go.', 'Remind me to call Sam. Tomorrow.']) {
      test('keeps speech: $heard', () => expect(withoutTrailingEcho(heard), heard));
    }

    test('takes it off the phrases too, however they were cut', () {
      const segments = [
        Segment(text: 'Add eggs to Go.', startMs: 0, endMs: 1000),
        Segment(text: 'Go.', startMs: 1000, endMs: 1500),
        Segment(text: 'Go.', startMs: 1500, endMs: 2000),
      ];
      expect(segmentsWithoutTrailingEcho(segments), [segments[0]]);
      expect(
        segmentsWithoutTrailingEcho(const [Segment(text: 'Add eggs to Go. Go.', startMs: 0, endMs: 2000)]),
        const [Segment(text: 'Add eggs to Go.', startMs: 0, endMs: 2000)],
      );
    });
  });
}
