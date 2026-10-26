// A Discord call's take on the device (docs/DISCORD_CALLS.md): its kind read as Discord; its speaker turns, lines with
// a name and no words, kept rather than dropped; kept in the note under ## Captions as names and times alone, and read
// back to name Whisper's phrases once the write-up comes; the note filed with no sound or none kept says who spoke
// when, and that Discord has no captions; and the bot's own mix, written by discord/bot/lib/webm.mjs
// (test/meet/fixtures/discord_mix.webm, made by discord/bot/test/webm.test.mjs), read by the very reader a Meet's is.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/locale_dates.dart';
import 'package:ghost_md/core/note.dart' show Segment;
import 'package:ghost_md/meet/gmt.dart';
import 'package:ghost_md/meet/meet_api.dart';
import 'package:ghost_md/meet/meet_in.dart';
import 'package:ghost_md/meet/meet_note.dart';
import 'package:ghost_md/meet/speakers.dart';
import 'package:ghost_md/meet/webm.dart';

import 'support.dart';

/// The bot's turns: the floor passing, a second late for the device's caption lag (discord/bot/lib/turns.mjs).
const List<Map<String, Object?>> turns = [
  {'at': 1000, 'speaker': 'Sam Lee', 'text': ''},
  {'at': 9000, 'speaker': 'Ali', 'text': ''},
  {'at': 14000, 'speaker': 'Sam Lee', 'text': ''},
];

OpenedTake discordTake({int audio = 4}) => readTake(gmt1(title: 'Standup in Ghost HQ', kind: 'discord', captions: turns, audio: List.filled(audio, 1)));

void main() {
  setUp(() => toldLocale = null);

  test('a take and a booking of kind discord are Discord’s, and so is a Discord channel link', () {
    expect(discordTake().service, MeetService.discord);
    expect(MeetService.of(null, url: 'https://discord.com/channels/333333333333333333/444444444444444444'), MeetService.discord);
    expect(MeetService.of(null, url: 'https://discord.com/invite/x'), MeetService.meet, reason: 'only a channel is a call');
    expect(MeetService.discord.words, 'Discord');
    final booking = MeetBooking.fromJson({'id': 'c1', 'title': 'Standup', 'url': null, 'kind': 'discord', 'startsAt': 1, 'endsAt': 2, 'state': 'done'})!;
    expect(booking.service, MeetService.discord, reason: 'the kind outlives the link the sweep blanks');
    expect(meetStateWords(MeetBooking.fromJson({'id': 'c2', 'kind': 'discord', 'startsAt': 1, 'endsAt': 2, 'state': 'failed', 'detail': 'nothing_heard'})!), 'Couldn’t join: Ghost heard nobody in the call');
  });

  test('in a Discord take, a turn with a name and no words is kept; one with neither is not, nor a Meet’s', () {
    final ndjson = Uint8List.fromList(utf8.encode('{"at":5,"speaker":"","text":""}\n{"at":1000,"speaker":"Sam Lee","text":""}\n'));
    expect(readCaptions(ndjson, turns: true), const [CaptionLine(at: 1000, speaker: 'Sam Lee', text: '')]);
    expect(readCaptions(ndjson), isEmpty, reason: 'a Meet caption with no words is still nothing');
    expect(discordTake().captions.length, 3, reason: 'a take of kind discord reads its turns');
  });

  test('the turns wait in the note as names and times, and name Whisper’s phrases when the write-up comes', () {
    final take = discordTake();
    final body = meetNoteBody(take, now: 0, writeUp: true);
    expect(body, contains('## Captions\n\n**Sam Lee (0:01):**\n\n**Ali (0:09):**\n\n**Sam Lee (0:14):**'));
    expect(turnsOf(body).map((t) => (t.speaker, t.startMs)), [('Sam Lee', 1000), ('Ali', 9000), ('Sam Lee', 14000)]);
    // Whisper's phrases: Sam from the start, Ali from 8 s (the turn's a second late, as captions are), Sam again at 13 s.
    const segments = [
      Segment(startMs: 0, endMs: 7500, text: 'Morning. Release notes first.'),
      Segment(startMs: 8000, endMs: 12500, text: 'They are drafted.'),
      Segment(startMs: 13000, endMs: 16000, text: 'Great, ship it.'),
    ];
    final written = withSpeakers('$body\n## Transcript\n\nMorning. Release notes first. They are drafted. Great, ship it.\n', segments)!;
    expect(written, contains('**Sam Lee (0:00):** Morning. Release notes first.\n\n**Ali (0:08):** They are drafted.\n\n**Sam Lee (0:13):** Great, ship it.'));
    expect(written, isNot(contains('## Captions')));
    expect(phraseSpeakers(segments, body), ['Sam Lee', 'Ali', 'Sam Lee']);
  });

  test('filed with no sound kept, the note says who spoke when, and that Discord shows no captions', () {
    final notKept = meetNoteBody(discordTake(), now: 0, writeUp: false);
    expect(notKept, contains('The recording could not be kept on this device, and Discord shows no captions: who spoke when is below.'));
    expect(notKept, contains('## Who spoke\n\n- Sam Lee, 0:01\n- Ali, 0:09\n- Sam Lee, 0:14\n'));
    expect(notKept, isNot(contains('## Transcript')));
    final noSound = meetNoteBody(discordTake(audio: 0), now: 0, writeUp: false, why: CaptionsOnly.noSound);
    expect(noSound, contains('No sound came with it, and Discord shows no captions.'));
  });

  test('the Discord bot’s mix reads as a Meet recording does: mono Opus, a packet every 20 ms, no gaps', () {
    final track = readWebmOpus(File('test/meet/fixtures/discord_mix.webm').readAsBytesSync());
    expect(track.channels, 1);
    expect(track.preSkip, 312);
    expect(track.packets.length, greaterThan(150));
    expect(track.atMs, [for (var i = 0; i < track.packets.length; i += 1) i * 20]);
    expect(track.durationMs, closeTo(track.packets.length * 20, 10));
    expect(packedForDecoder(track).length, greaterThan(track.packets.length * 8));
  });
}
