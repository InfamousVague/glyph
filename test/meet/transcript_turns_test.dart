// A meeting's transcript is turns, every one saying who and when (Matt, 2026-10-30: "some of the meeting transcripts
// still go into one giant block instead of maintaining the name (timestamp): prefix on each line please address").
//
// The case it came from: the 2026-10-29 Engineering Standup (HelloTrade › Meetings, Google Meet, 09:28 to 10:06) had
// a body of "Ghost was in this meeting on Oct 29, 09:28 to 10:06.\n\n## Transcript\n\nOh yeah, we can talk about
// it. …" as one paragraph. That paragraph is the write-up's (tauri/src-tauri/src/transcript.rs `paragraphs`, which
// breaks only at a silence of more than 1.5 s between phrases; Whisper's phrases over a call's mixed sound abut, so a
// 38-minute call has none), and the meeting step (lib/meet/meet_note.dart `withSpeakers`) left it so where it found
// no phrases to name (it dropped the captions and kept the block) or no captions (it took the "being written up" off
// and kept the block). [standup] below is that meeting as the devices had it: 38 minutes, five people, Whisper's
// phrases abutting, Meet's captions a second behind them.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/markdown.dart' show toParagraphs;
import 'package:ghost_md/capture/meeting_turns.dart';
import 'package:ghost_md/core/library.dart' show withTranscript;
import 'package:ghost_md/core/merge_words.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/summary_text.dart' show summarySection, withSummary;
import 'package:ghost_md/meet/gmt.dart';
import 'package:ghost_md/meet/meet_note.dart';
import 'package:ghost_md/meet/speakers.dart';
import 'package:ghost_md/share/share_audio.dart' show meetingTurns;
import 'package:ghost_md/tapes/transcript_words.dart' show paragraphStartMs, writtenTranscript;

/// What each person in the standup says, a sentence at a time.
const Map<String, List<String>> _said = {
  'Phil Mulliken': ['Oh yeah, we can talk about it.', 'I was discussing the matching engine with Kevin yesterday.', 'The order book rebuild is slower than we thought.', 'We should profile it before Friday.', 'I can pair on that this afternoon.'],
  'Matt': ['Shipping the activity tray today.', 'The ring has its badge now.', 'Updates only show in the drawer.', 'I want a review before lunch.', 'Then the OTA goes out.'],
  'Kevin Ortiz': ['The settlement job failed twice overnight.', 'It was the retry window again.', 'I raised it to five minutes.', 'No alerts since.', 'I will watch it through the weekend.'],
  'Dana Reyes': ['Compliance wants the audit export by Monday.', 'It has to include the cancelled orders.', 'I have a draft of the columns.', 'Can someone check the timestamps?', 'They should be in UTC.'],
  'Sam Lee': ['Hiring: two interviews this week.', 'One backend, one design.', 'The design brief went out.', 'Feedback in the doc please.', 'That is it from me.'],
};

/// A phrase as the write-up keeps it, and the caption line Meet showed for it.
typedef _Heard = ({List<Segment> phrases, List<CaptionLine> captions, List<String> speakerOf});

/// The standup: 38 minutes of turns from 4 s to 2.5 min, Whisper's phrases 2 to 7 s and abutting, a caption line a
/// phrase a second after it, named. Seeded, so the same every run.
_Heard standup({int minutes = 38, int seed = 29}) {
  final random = math.Random(seed);
  final names = _said.keys.toList();
  final phrases = <Segment>[];
  final captions = <CaptionLine>[];
  final speakerOf = <String>[];
  var at = 1200;
  var last = -1;
  while (at < minutes * 60000) {
    var who = random.nextInt(names.length);
    if (who == last) who = (who + 1) % names.length;
    last = who;
    final name = names[who];
    // Most turns short, a few long: a stand-up's updates, and one long explanation.
    final turnMs = random.nextInt(10) < 8 ? 4000 + random.nextInt(40000) : 60000 + random.nextInt(90000);
    final end = at + turnMs;
    var n = 0;
    while (at < end) {
      final length = 2000 + random.nextInt(5000);
      // About fifteen characters a second, as speech is.
      final lines = _said[name]!;
      final words = <String>[];
      while (words.join(' ').length < length * 14 ~/ 1000) {
        words.add(lines[(n + words.length + random.nextInt(3)) % lines.length]);
      }
      final text = words.join(' ');
      phrases.add(Segment(startMs: at, endMs: at + length, text: ' $text '));
      captions.add(CaptionLine(at: at + captionLagMs, speaker: name, text: text));
      speakerOf.add(name);
      at += length;
      n += 1;
    }
  }
  return (phrases: phrases, captions: captions, speakerOf: speakerOf);
}

/// The note as the meeting step files it, to be written up.
String filed(List<CaptionLine> captions) {
  final turns = captionTurns(captions);
  return '# Engineering Standup\n\nGhost was in this meeting on 29 Oct, 09:28 to 10:06. It is being written up on your device.\n\n${captionsSection(turns)}\n';
}

/// What the write-up left in the note before 2026-10-30: its section on the end, its paragraphs broken at a silence
/// of 1.5 s only (`paragraphs`, the twin of markdown.dart `toParagraphs`).
String writtenUpBefore(String body, List<Segment> phrases) => '${body.trimRight()}\n\n## Transcript\n\n${toParagraphs(phrases).join('\n\n')}\n';

/// The paragraphs under `## Transcript`.
List<String> paragraphsOf(String body) => writtenTranscript(body) ?? const [];

final RegExp _named = RegExp(r'^\*\*(.+?) \((\d+(?::\d{2}){1,2})\):\*\* ');
final RegExp _bare = RegExp(r'^\((\d+(?::\d{2}){1,2})\) ');

int _clock(String clock) => clock.split(':').fold(0, (total, part) => total * 60 + int.parse(part)) * 1000;

/// Every paragraph a timed turn, the times never falling, none over a minute and a phrase.
void expectTurns(List<String> paragraphs, {required bool named}) {
  expect(paragraphs, isNotEmpty);
  var was = -1;
  for (final p in paragraphs) {
    final m = _named.firstMatch(p) ?? _bare.firstMatch(p);
    expect(m, isNotNull, reason: 'a turn with no time: ${p.substring(0, math.min(80, p.length))}');
    if (named) expect(_named.hasMatch(p), isTrue, reason: p.substring(0, math.min(80, p.length)));
    final at = paragraphStartMs(p);
    expect(at, isNotNull);
    expect(at!, greaterThanOrEqualTo(was));
    was = at;
  }
}

void main() {
  test('the write-up\'s Rust twin and the app write a meeting\'s turns alike (test/capture/fixtures/meeting_turns.json)', () {
    final cases = (jsonDecode(File('test/capture/fixtures/meeting_turns.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    for (final c in cases) {
      final segments = [for (final s in (c['segments'] as List).cast<List<dynamic>>()) Segment(startMs: s[0] as int, endMs: s[1] as int, text: s[2] as String)];
      expect(turnLines(segments), (c['paragraphs'] as List).cast<String>(), reason: c['why'] as String);
    }
    expect(meetingTranscript(const []), '## Transcript\n\n');
    expect(meetingTranscript(const [], 'first words'), '## Transcript\n\n(0:00) First words');
    expect(meetingTranscript(const [Segment(startMs: 4000, endMs: 5000, text: 'we settled it.')], ' and the '), '## Transcript\n\n(0:04) We settled it. and the');
  });

  group('the standup of 2026-10-29', () {
    final heard = standup();

    test('the fixture is the meeting: 38 minutes, five people, phrases that abut', () {
      expect(heard.phrases.last.endMs, greaterThan(38 * 60000));
      expect(heard.speakerOf.toSet(), hasLength(5));
      for (var i = 1; i < heard.phrases.length; i += 1) {
        expect(heard.phrases[i].startMs, heard.phrases[i - 1].endMs);
      }
      // What it was: the write-up's paragraphs, one for the whole meeting.
      expect(toParagraphs(heard.phrases), hasLength(1));
    });

    test('with its captions, each turn is named by when it was said, a minute at most, every one timed', () {
      final body = writtenUpBefore(filed(heard.captions), heard.phrases);
      final out = withSpeakers(body, heard.phrases)!;
      expect(out, isNot(contains('## Captions')));
      expect(out, isNot(contains('being written up')));
      final paragraphs = paragraphsOf(out);
      expectTurns(paragraphs, named: true);
      expect(paragraphs.length, greaterThan(38), reason: 'about a turn a minute or more, not one block');
      // Who: each phrase's speaker, read back from the written turns, is the one who said it.
      final read = phraseSpeakers(heard.phrases, out);
      var right = 0;
      for (var i = 0; i < read.length; i += 1) {
        if (read[i] == heard.speakerOf[i]) right += 1;
      }
      expect(right / read.length, greaterThan(0.97));
      // No turn runs past a minute and a phrase.
      final starts = [for (final p in paragraphs) paragraphStartMs(p)!];
      for (var i = 1; i < starts.length; i += 1) {
        expect(starts[i] - starts[i - 1], lessThanOrEqualTo(turnMostMs + 7000));
      }
      // And the words are all there, in order.
      final words = paragraphs.map((p) => p.replaceFirst(_named, '')).join(' ');
      expect(words.split(' ').length, heard.phrases.map((s) => s.text.trim()).join(' ').split(' ').length);
    });

    test('the example\'s step: no phrases to name them by, the captions\' own turns, not the block', () {
      final body = writtenUpBefore(filed(heard.captions), heard.phrases);
      final out = withSpeakers(body, const [])!;
      final paragraphs = paragraphsOf(out);
      expectTurns(paragraphs, named: true);
      expect(paragraphs.first, startsWith('**${heard.speakerOf.first} (0:02):** '));
      expect(out, isNot(contains('## Captions')));
    });

    test('the example\'s other step: no captions came, the phrases in timed turns', () {
      final body = writtenUpBefore(filed(const []), heard.phrases);
      final out = withSpeakers(body, heard.phrases)!;
      final paragraphs = paragraphsOf(out);
      expectTurns(paragraphs, named: false);
      expect(paragraphs.length, greaterThanOrEqualTo(36), reason: "a turn about every minute");
      expect(paragraphs.first, startsWith('(0:01) '));
    });

    test('captions missing for ten minutes: those turns are timed with nobody named, the rest named', () {
      final gap = [for (final c in heard.captions) if (c.at < 10 * 60000 || c.at > 20 * 60000) c];
      final out = withSpeakers(writtenUpBefore(filed(gap), heard.phrases), heard.phrases)!;
      final paragraphs = paragraphsOf(out);
      expectTurns(paragraphs, named: false);
      final unnamed = [for (final p in paragraphs) if (_bare.hasMatch(p)) paragraphStartMs(p)!];
      expect(unnamed, isNotEmpty);
      expect(unnamed.every((at) => at > 9 * 60000 && at < 21 * 60000), isTrue, reason: 'only the stretch with no captions');
      expect(paragraphs.where(_named.hasMatch).length, greaterThan(paragraphs.length ~/ 2));
    });

    test('captions on another clock meet none of the phrases: the captions\' own turns', () {
      final late = [for (final c in heard.captions) CaptionLine(at: c.at + 3 * 3600000, speaker: c.speaker, text: c.text)];
      final out = withSpeakers(writtenUpBefore(filed(late), heard.phrases), heard.phrases)!;
      expectTurns(paragraphsOf(out), named: true);
    });

    test('the share and the transcript\'s view read every turn with its time and its speaker', () {
      final out = withSpeakers(writtenUpBefore(filed(heard.captions), heard.phrases), heard.phrases)!;
      final note = Note(id: 'standup', body: out, createdAt: 0, updatedAt: 0, source: NoteSource.capture, recordingMs: heard.phrases.last.endMs);
      final shared = meetingTurns(note);
      expect(shared.speakers.toSet(), _said.keys.toSet());
      expect(shared.turns.every((t) => t.speaker >= 0 && t.phrases.single.startMs >= 0), isTrue);
      expect(transcriptParagraphs(out).every((p) => p.speaker != null && p.startMs != null), isTrue);
    });
  });

  test('a single long monologue is a turn a minute, each named and timed', () {
    final phrases = <Segment>[];
    for (var at = 0; at < 10 * 60000; at += 5000) {
      phrases.add(Segment(startMs: at, endMs: at + 5000, text: 'And the next part of the plan is this, which we will cover in more detail now.'));
    }
    final captions = [for (final p in phrases) CaptionLine(at: p.startMs + 1000, speaker: 'Phil Mulliken', text: p.text)];
    final out = withSpeakers(writtenUpBefore(filed(captions), phrases), phrases)!;
    final paragraphs = paragraphsOf(out);
    expect(paragraphs, hasLength(10));
    expect([for (final p in paragraphs) p.substring(0, p.indexOf(':** ') + 4)], [for (var m = 0; m < 10; m += 1) '**Phil Mulliken ($m:00):** ']);
    // The captions alone, the same monologue, cut at its sentences about a minute apart.
    final alone = paragraphsOf(withSpeakers(writtenUpBefore(filed(captions), phrases), const [])!);
    expect(alone.length, inInclusiveRange(9, 11));
    expectTurns(alone, named: true);
  });

  test('filed from the captions alone, the transcript is timed turns', () {
    final heard = standup(minutes: 6);
    final take = OpenedTake(meeting: 'm', title: 'Engineering Standup', service: MeetService.meet, startedAt: DateTime(2026, 10, 29, 9, 28).millisecondsSinceEpoch, endedAt: DateTime(2026, 10, 29, 10, 6).millisecondsSinceEpoch, mime: 'audio/webm', captions: heard.captions, audio: Uint8List(0));
    final body = meetNoteBody(take, now: 0, writeUp: false);
    expectTurns(paragraphsOf(body), named: true);
  });

  test('a Discord call: turns with no words name the phrases, and are no paragraphs of their own', () {
    const phrases = [Segment(startMs: 0, endMs: 4000, text: 'Release notes first.'), Segment(startMs: 4000, endMs: 9000, text: 'They are drafted.')];
    const turns = [CaptionLine(at: 0, speaker: 'Ana', text: ''), CaptionLine(at: 4500, speaker: 'Ben', text: '')];
    final body = '# Call\n\nGhost was in this meeting on 29 Oct, 09:28 to 10:06. It is being written up on your device.\n\n${captionsSection(captionTurns(turns))}\n\n## Transcript\n\nRelease notes first. They are drafted.\n';
    expect(paragraphsOf(withSpeakers(body, phrases)!), ['**Ana (0:00):** Release notes first.', '**Ben (0:04):** They are drafted.']);
    expect(captionTurnLines(captionTurns(turns)), isEmpty);
  });

  group('Rebuild transcript', () {
    final heard = standup(minutes: 12, seed: 7);
    // The example as it stands now: summary on top, the captions gone, Whisper's words one block.
    final broken = withSummary(writtenUpBefore(filed(heard.captions), heard.phrases).replaceFirst(RegExp(r'\n## Captions[\s\S]*?(?=\n## Transcript)'), '').replaceFirst(' It is being written up on your device.', ''), '## Summary\n\nThe team agreed to ship today.\n\n- [ ] Matt: review before lunch');

    test('from the phrases and the captions its versions kept: named turns, everything above untouched', () {
      expect(paragraphsOf(broken), hasLength(1));
      final captions = captionsOfVersions([broken, filed(heard.captions), broken]);
      expect(captions, isNotNull);
      final section = rebuiltTranscript(broken, heard.phrases, captions: captions)!;
      final rebuilt = withTranscript(broken, section);
      expectTurns(paragraphsOf(rebuilt), named: true);
      final above = broken.substring(0, broken.indexOf('## Transcript'));
      expect(rebuilt.substring(0, rebuilt.indexOf('## Transcript')), above, reason: 'the summary and the line, byte for byte');
      expect(summarySection(rebuilt)?.text, summarySection(broken)?.text);
      // Once more changes nothing.
      expect(withTranscript(rebuilt, rebuiltTranscript(rebuilt, heard.phrases)!), rebuilt);
    });

    test('with no captions anywhere: timed turns with nobody named', () {
      final rebuilt = withTranscript(broken, rebuiltTranscript(broken, heard.phrases)!);
      expectTurns(paragraphsOf(rebuilt), named: false);
      expect(captionsOfVersions([broken]), isNull);
    });

    test('with no phrases kept and no captions there is nothing to rebuild from', () {
      expect(rebuiltTranscript(broken, const []), isNull);
    });

    test('in a team note, the rebuild and a summary written on another device merge into one note', () {
      final section = rebuiltTranscript(broken, heard.phrases, captions: captionsOfVersions([filed(heard.captions)]))!;
      final mine = withTranscript(broken, section);
      final theirs = broken.replaceFirst('The team agreed to ship today.', 'The team agreed to ship today, after the review.');
      final merged = mergedWords(broken, mine, theirs);
      expect(merged, isNotNull);
      expect(merged, contains('after the review.'));
      expect(paragraphsOf(merged!), paragraphsOf(mine));
    });
  });
}
