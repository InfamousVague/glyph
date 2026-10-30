import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/markdown.dart' show Segment;
import 'package:ghost_md/capture/meeting.dart';
import 'package:ghost_md/core/locale_dates.dart';
import 'package:ghost_md/core/summary_text.dart' show dateTitled;

/// A meeting's gate and its title (lib/capture/meeting.dart): where one can be recorded, by platform and by the
/// binary's generation, and the date title in three locales, which core/summary_text.dart must still know as a date
/// title. Case for case with the web's `capture/meeting.test.ts`.

class Platform {
  bool tauri = false;
  bool android = false;
  bool ios = false;
  bool mobile = false;
  int generation = 0;
}

void main() {
  var platform = Platform();
  Future<bool> canRecord() => canRecordMeeting(
        native: platform.tauri,
        isIOS: platform.ios,
        isAndroid: platform.android,
        isMobile: platform.mobile,
        hasNativeGeneration: (wanted) async => platform.tauri && platform.generation >= wanted,
      );

  setUp(() => platform = Platform());

  group('where a meeting can be recorded', () {
    test('never in a browser, and never on iOS, which has no whisper and no model', () async {
      expect(await canRecord(), false);
      platform.tauri = true;
      platform.ios = true;
      platform.mobile = true;
      expect(await canRecord(), false);
    });

    test('on the Mac, in the page recorder', () async {
      platform.tauri = true;
      expect(await canRecord(), true);
    });

    test('on Android only from the generation with the service', () async {
      platform.tauri = true;
      platform.android = true;
      platform.mobile = true;
      platform.generation = meetingGeneration - 1;
      expect(await canRecord(), false);
      platform.generation = meetingGeneration;
      expect(await canRecord(), true);
      expect(meetingGeneration, 20);
    });
  });

  group('the title', () {
    // Local times: the title is the time on the phone's own clock.
    final afternoon = DateTime(2026, 9, 26, 14, 5).millisecondsSinceEpoch;
    final smallHours = DateTime(2026, 9, 26, 0, 5).millisecondsSinceEpoch;

    test('is the day and the month in the locale’s own order, and the time on a 24-hour clock', () {
      expect(meetingTitle(afternoon, 'en-GB'), 'Meeting, 26 Sept 14:05');
      expect(meetingTitle(afternoon, 'en-US'), 'Meeting, Sep 26 14:05');
      // The locale's literal after the day (".") is dropped, and its month abbreviation kept as it is.
      expect(meetingTitle(afternoon, 'de-DE'), 'Meeting, 26 Sept. 14:05');
      expect(meetingTitle(smallHours, 'en-GB'), 'Meeting, 26 Sept 00:05');
      expect(meetingTitle(smallHours, 'en-US'), 'Meeting, Sep 26 00:05');
      expect(meetingTitle(smallHours, 'de-DE'), 'Meeting, 26 Sept. 00:05');
    });

    group('in the phone’s own words, where no locale is named (core/locale_dates.dart)', () {
      tearDown(() => toldLocale = null);

      test('an American phone has the month first, and Sep', () {
        toldLocale = DateLocale.enUS;
        expect(meetingTitle(afternoon), 'Meeting, Sep 26 14:05');
        expect(meetingTitle(smallHours), 'Meeting, Sep 26 00:05');
        expect(dateTitled('# ${meetingTitle(afternoon)}\n\nWords.'), true);
        // A locale named is still that locale's.
        expect(meetingTitle(afternoon, 'en-GB'), 'Meeting, 26 Sept 14:05');
        expect(meetingTitle(afternoon, 'de-DE'), 'Meeting, 26 Sept. 14:05');
      });

      test('a British phone has the day first, and Sept, as a phone that has not said has', () {
        expect(meetingTitle(afternoon), 'Meeting, 26 Sept 14:05');
        toldLocale = DateLocale.enGB;
        expect(meetingTitle(afternoon), 'Meeting, 26 Sept 14:05');
        expect(meetingTitle(smallHours), 'Meeting, 26 Sept 00:05');
        expect(dateTitled('# ${meetingTitle(afternoon)}\n\nWords.'), true);
        expect(meetingTitle(afternoon, 'en-US'), 'Meeting, Sep 26 14:05');
      });
    });

    test('is still a date title to the summary, in every locale and at every hour, so the model’s heading can take its place', () {
      for (final locale in ['en-US', 'en-GB', 'de-DE', null]) {
        for (final ms in [afternoon, smallHours]) {
          expect(dateTitled('# ${meetingTitle(ms, locale)}\n\nWords.'), true, reason: '$locale at $ms');
        }
      }
      expect(dateTitled('# Planning call'), false);
    });

    test('heads the body a meeting note is made with, over its transcript', () {
      final body = meetingBody('Meeting, 26 Sep 14:05', const [
        Segment(text: 'we settled the date.', startMs: 0, endMs: 1000),
        Segment(text: 'A different one.', startMs: 5000, endMs: 6000),
      ]);
      // Timed turns, a new one after the pause (lib/capture/meeting_turns.dart; 2026-10-30).
      expect(body, '# Meeting, 26 Sep 14:05\n\n## Transcript\n\n(0:00) We settled the date.\n\n(0:05) A different one.');
      expect(dateTitled(body), true);
    });
  });
}
