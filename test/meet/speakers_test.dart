// Who said what (lib/meet/speakers.dart) and the note a meeting becomes (lib/meet/meet_note.dart): the captions as
// turns, Whisper's segments given the speaker whose turn overlaps them longest, the transcript as `**Name:** words`,
// the captions kept in the note and read back, and the note's shapes before and after its write-up.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/locale_dates.dart';
import 'package:ghost_md/core/note.dart' show Segment;
import 'package:ghost_md/mail/mail_note.dart' show mailNoteId;
import 'package:ghost_md/meet/gmt.dart';
import 'package:ghost_md/meet/meet_note.dart';
import 'package:ghost_md/meet/speakers.dart';

const List<CaptionLine> lines = [
  CaptionLine(at: 1000, speaker: 'Sam Lee', text: 'Good morning everyone.'),
  CaptionLine(at: 4000, speaker: 'Sam Lee', text: 'Launch checklist first.'),
  CaptionLine(at: 11000, speaker: 'Daniel', text: 'The pricing page is drafted.'),
];

OpenedTake take({String title = 'Launch sync', List<CaptionLine> captions = lines, int audio = 4}) => OpenedTake(
      meeting: 'm1',
      title: title,
      startedAt: DateTime(2026, 10, 18, 14, 0).millisecondsSinceEpoch,
      endedAt: DateTime(2026, 10, 18, 14, 45).millisecondsSinceEpoch,
      mime: 'audio/webm',
      captions: captions,
      audio: Uint8List(audio),
    );

void main() {
  setUp(() => toldLocale = null);
  group('names kept on the phrases (2026-10-26)', namesKept);

  test('captions become turns, each lasting until the next begins', () {
    final turns = captionTurns(lines);
    expect(turns, const [
      CaptionTurn(speaker: 'Sam Lee', startMs: 1000, endMs: 11000, text: 'Good morning everyone. Launch checklist first.'),
      CaptionTurn(speaker: 'Daniel', startMs: 11000, endMs: 13000, text: 'The pricing page is drafted.'),
    ]);
  });

  test('each segment takes the speaker whose turn overlaps it longest, a caption\'s lag allowed for', () {
    final turns = captionTurns(lines);
    final segments = [
      const Segment(startMs: 0, endMs: 4000, text: 'Good morning everyone.'),
      const Segment(startMs: 4000, endMs: 9500, text: 'Launch checklist first.'),
      // 200 ms of Sam's turn (moved a second earlier) and 4 s of Daniel's.
      const Segment(startMs: 9800, endMs: 14000, text: 'The pricing page'),
      // Past every turn, but within four seconds of Daniel's.
      const Segment(startMs: 13000, endMs: 14000, text: 'is drafted.'),
      // Far from any turn.
      const Segment(startMs: 40000, endMs: 41000, text: 'Is anyone there?'),
    ];
    final speakers = alignSpeakers(segments, turns);
    expect(speakers, ['Sam Lee', 'Sam Lee', 'Daniel', 'Daniel', null]);
    expect(speakerParagraphs(segments, speakers), [
      '**Sam Lee:** Good morning everyone. Launch checklist first.',
      '**Daniel:** The pricing page is drafted.',
      'Is anyone there?',
    ]);
    expect(alignSpeakers(segments, const []), everyElement(isNull), reason: 'no captions, no names');
  });

  test('an unnamed turn names nobody, and a name is written plain', () {
    final turns = captionTurns(const [CaptionLine(at: 0, speaker: '', text: 'Hello?'), CaptionLine(at: 3000, speaker: 'Ana *(host)*:', text: 'Hi.')]);
    expect(turns.last.speaker, 'Ana host');
    expect(alignSpeakers(const [Segment(startMs: 0, endMs: 1500, text: 'Hello?')], turns), ['Ana host'], reason: 'the nearest named turn, a second and a half away');
    expect(captionParagraphs(turns), ['Hello?', '**Ana host:** Hi.']);
  });

  test('the captions kept in the note read back as the same turns', () {
    final turns = captionTurns([...lines, const CaptionLine(at: 3725000, speaker: '', text: 'An hour in.')]);
    final section = captionsSection(turns);
    expect(section, startsWith('## Captions\n\n**Sam Lee (0:01):** Good morning everyone. Launch checklist first.\n\n**Daniel (0:11):** The pricing page is drafted.\n\n(1:02:05) An hour in.'));
    final body = '# Launch sync\n\nA line.\n\n$section\n\n## Transcript\n\nWords.\n';
    final read = turnsOf(body);
    expect([for (final t in read) (t.speaker, t.startMs, t.text)], [(turns[0].speaker, 1000, turns[0].text), (turns[1].speaker, 11000, turns[1].text), ('', 3725000, 'An hour in.')]);
    expect(read[0].endMs, 11000);
    expect(turnsOf('# No captions\n'), isEmpty);
  });

  test('a note\'s id is made from its take\'s, the same each time and never a mail\'s', () {
    const id = 'AbCdEfGhIjKlMnOpQrStUv';
    expect(meetNoteId(id), meetNoteId(id));
    expect(meetNoteId(id), isNot(mailNoteId(id)));
    expect(meetNoteId(id), matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(meetNoteId('not-the-service-shape'), isNot(meetNoteId('not-the-service-shapf')));
  });

  test('filed to be written up: the captions wait under their own heading', () {
    final body = meetNoteBody(take(), now: 0, writeUp: true);
    expect(body, '# Launch sync\n\nGhost was in this meeting on 18 Oct, 14:00 to 14:45. It is being written up on your device.\n\n'
        '## Captions\n\n**Sam Lee (0:01):** Good morning everyone. Launch checklist first.\n\n**Daniel (0:11):** The pricing page is drafted.\n');
  });

  test('filed from the captions alone, the captions are the transcript and the note says why', () {
    expect(meetNoteBody(take(), now: 0, writeUp: false), '# Launch sync\n\nGhost was in this meeting on 18 Oct, 14:00 to 14:45. This is from Meet’s captions: the recording could not be kept on this device.\n\n'
        '## Transcript\n\n**Sam Lee:** Good morning everyone. Launch checklist first.\n\n**Daniel:** The pricing page is drafted.\n');
    expect(meetNoteBody(take(captions: const [], audio: 0), now: 0, writeUp: false, why: CaptionsOnly.noSound), endsWith('No sound came with it, so this is from Meet’s captions.\n\n## Transcript\n\nMeet showed no captions.\n'));
  });

  test('with no title the note is named by its date, as a meeting recorded here is', () {
    expect(meetNoteBody(take(title: ''), now: 0, writeUp: true), startsWith('# Meeting, 18 Oct 14:00\n'));
  });

  test('once the write-up has put Whisper\'s words in, each part is given its speaker and the captions go', () {
    final filed = meetNoteBody(take(), now: 0, writeUp: true);
    expect(withSpeakers(filed, const []), isNull, reason: 'no transcript yet');
    // What the write-up leaves (tauri/src-tauri/src/transcript.rs `with_transcript`): its section on the end.
    final written = '${filed.trimRight()}\n\n## Transcript\n\nGood morning everyone. Launch checklist first. The pricing page is drafted.\n';
    final segments = [
      const Segment(startMs: 0, endMs: 3000, text: 'Good morning everyone.'),
      const Segment(startMs: 3000, endMs: 8000, text: 'Launch checklist first.'),
      const Segment(startMs: 10200, endMs: 12500, text: 'The pricing page is drafted.'),
    ];
    expect(withSpeakers(written, segments), '# Launch sync\n\nGhost was in this meeting on 18 Oct, 14:00 to 14:45.\n\n'
        '## Transcript\n\n**Sam Lee (0:00):** Good morning everyone. Launch checklist first.\n\n**Daniel (0:10):** The pricing page is drafted.\n');
    // A summary landed above it stays where it is.
    final summarised = written.replaceFirst('\n\nGhost was', '\n## Summary\nA call.\n\nGhost was');
    expect(withSpeakers(summarised, segments), startsWith('# Launch sync\n## Summary\nA call.\n\nGhost was in this meeting'));
    // No phrases with times kept: the words stay as Whisper wrote them, and the captions still go.
    expect(withSpeakers(written, const []), '# Launch sync\n\nGhost was in this meeting on 18 Oct, 14:00 to 14:45.\n\n## Transcript\n\nGood morning everyone. Launch checklist first. The pricing page is drafted.\n');
    expect(withSpeakers('# A note\n\n## Transcript\n\nWords.\n', segments), '# A note\n\n## Transcript\n\nWords.\n', reason: 'no captions kept: nothing to do');
  });
  test('a meeting with no captions waits for its write-up, then loses the "being written up" line (2026-10-19, test 4)', () {
    final filed = meetNoteBody(take(captions: const []), now: 0, writeUp: true);
    expect(awaitsWriteUp(filed), isTrue);
    expect(withSpeakers(filed, const []), isNull, reason: 'no transcript yet: keep waiting');
    final written = '${filed.trimRight()}\n\n## Transcript\n\nGood morning everyone.\n';
    final done = withSpeakers(written, const [Segment(startMs: 0, endMs: 2000, text: 'Good morning everyone.')])!;
    expect(done, '# Launch sync\n\nGhost was in this meeting on 18 Oct, 14:00 to 14:45.\n\n## Transcript\n\nGood morning everyone.\n');
    expect(awaitsWriteUp(done), isFalse);
  });
}

// Matt, 2026-10-26: "Also after some time all the speaker labels disappeared". The note kept its names; the
// transcript's view showed Whisper's phrases, which carry none. And one speaker of his standup read as `groups`.
void namesKept() {
  const segments = [
    Segment(startMs: 0, endMs: 3000, text: 'Good morning everyone.'),
    Segment(startMs: 3000, endMs: 8000, text: 'Launch checklist first.'),
    Segment(startMs: 10200, endMs: 12500, text: 'The pricing page is drafted.'),
  ];

  test('each phrase is given its speaker from the captions while the note keeps them', () {
    final filed = meetNoteBody(take(), now: 0, writeUp: true);
    expect(phraseSpeakers(segments, filed), ['Sam Lee', 'Sam Lee', 'Daniel']);
  });

  test('once written up, from the transcript’s timed paragraphs, which keep the names and when each began', () {
    final filed = meetNoteBody(take(), now: 0, writeUp: true);
    final written = withSpeakers('${filed.trimRight()}\n\n## Transcript\n\nGood morning everyone. Launch checklist first. The pricing page is drafted.\n', segments)!;
    expect(written, isNot(contains('## Captions')));
    expect(transcriptParagraphs(written), [(speaker: 'Sam Lee', startMs: 0, words: 6), (speaker: 'Daniel', startMs: 10000, words: 5)]);
    expect(phraseSpeakers(segments, written), ['Sam Lee', 'Sam Lee', 'Daniel']);
  });

  test('a meeting written up before the times were kept is named by where its words fall', () {
    const body = '# Standup\n\n## Transcript\n\n**Phil Mulliken:** Good morning everyone. Launch checklist first.\n\n**Matt:** The pricing page is drafted.\n';
    expect(phraseSpeakers(segments, body), ['Phil Mulliken', 'Phil Mulliken', 'Matt']);
    // Corrected by hand a little, it still matches.
    const edited = '# Standup\n\n## Transcript\n\n**Phil Mulliken:** Good morning, everyone! The launch checklist first.\n\n**Matt:** Pricing page drafted.\n';
    expect(phraseSpeakers(segments, edited), ['Phil Mulliken', 'Phil Mulliken', 'Matt']);
  });

  test('a recording made on the device names nobody', () {
    expect(phraseSpeakers(segments, '# A walk\n\n## Transcript\n\nGood morning everyone. Launch checklist first. The pricing page is drafted.\n'), [null, null, null]);
    expect(namedTranscript(segments, '# A walk\n\n## Transcript\n\nGood morning everyone.\n'), isNull);
  });

  test('a transcript written again from its phrases keeps the names (a write-up, the better words)', () {
    const body = '# Standup\n\n## Transcript\n\n**Phil Mulliken:** Good morning everyone. Launch checklist first.\n\n**Matt:** The pricing page is drafted.\n';
    const better = [
      Segment(startMs: 0, endMs: 3000, text: 'Good morning, everyone.'),
      Segment(startMs: 3000, endMs: 8000, text: 'Launch checklist first.'),
      Segment(startMs: 10200, endMs: 12500, text: 'The pricing page is drafted.'),
    ];
    expect(namedTranscript(better, body), '## Transcript\n\n**Phil Mulliken (0:00):** Good morning, everyone. Launch checklist first.\n\n**Matt (0:10):** The pricing page is drafted.');
  });

  test('one of Meet’s icons is no speaker: `groups` is read as nobody named', () {
    final turns = captionTurns(const [
      CaptionLine(at: 0, speaker: 'groups', text: 'Let us start with the board.'),
      CaptionLine(at: 3000, speaker: 'Sam Lee', text: 'Sure.'),
    ]);
    expect([for (final t in turns) t.speaker], ['', 'Sam Lee']);
    expect(captionParagraphs(turns), ['Let us start with the board.', '**Sam Lee:** Sure.']);
    expect(turnsOf('# Call\n\n## Captions\n\n**groups (0:00):** Hello.\n\n**Groups Inc (0:04):** Hi.').map((t) => t.speaker), ['', 'Groups Inc']);
    expect(transcriptParagraphs('# Call\n\n## Transcript\n\n**groups:** Hello.\n').single.speaker, isNull);
  });
}
