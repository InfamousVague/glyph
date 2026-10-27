// The ElevenLabs plugin at work (lib/plugins/elevenlabs/elevenlabs.dart, voice_over.dart, elevenlabs_hold.dart,
// elevenlabs_pane.dart): a note read aloud in the voice chosen, its parts joined, kept as the note's file and put under
// its title; its cost said first; Eleven v4 refused read with Multilingual v2; failures said; the device held while it
// reads; and the page, which keeps only a key ElevenLabs accepts, lets a voice be picked and forgets twice.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/files/attachment_store.dart' show KeptAttachment;
import 'package:ghost_md/plugins/elevenlabs/elevenlabs.dart';
import 'package:ghost_md/plugins/elevenlabs/manifest.dart' as eleven;
import 'package:ghost_md/plugins/github/plain_field.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/types.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart' show Pick;

import '../github/support.dart';

Uint8List part(int n) => Uint8List.fromList([0xff, 0xfb, 0x90, n]);

/// ElevenLabs, answering each read with a part of its own, or with [fails].
class FakeEleven extends ElevenLabsClient {
  FakeEleven() : super(apiKey: 'sk_fake');

  final List<({String text, String voice, String model})> asked = [];
  ElevenFailure? Function(String model, int ask)? fails;
  void Function()? onAsk;

  @override
  Future<Uint8List> speak(String text, {required String voiceId, required String modelId}) async {
    asked.add((text: text, voice: voiceId, model: modelId));
    onAsk?.call();
    final failure = fails?.call(modelId, asked.length);
    if (failure != null) throw failure;
    return part(asked.length);
  }
}

/// What the device was told.
class Jobs implements BackgroundJobs {
  final List<String> told = [];

  @override
  Future<void> running(String id, {required String title, required String text, int? done, int? total}) async => told.add('running $id $title: $text');

  @override
  Future<void> ended(String id, {required String title, String? text, bool quiet = false}) async => told.add('ended $id${quiet ? ' quietly' : ''}');

  @override
  void onStop(void Function(String id)? stop) {}
}

void main() {
  late TestGround ground;
  late FakeEleven fake;
  late List<({Uint8List bytes, String name})> kept;

  Future<void> key() => eleven.host.secrets.write(apiKeySecret, 'sk_kept');

  setUp(() {
    ground = useGround();
    fake = FakeEleven();
    elevenLabsClient = () => fake;
    kept = [];
    keepVoiceOver = (bytes, name) async {
      kept.add((bytes: bytes, name: name));
      return KeptAttachment(name: '0000000${kept.length}-1111-4222-8333-444444444444.mp3', original: name, bytes: bytes.length);
    };
    final registry = createRegistry([elevenLabsPlugin], store: MemorySwitches());
    registry.setEnabled('elevenlabs', true);
    usePlugins(registry);
  });

  tearDown(() {
    elevenLabsClient = () => ElevenLabsClient.kept();
    usePluginGround(PluginGround());
    usePlugins(createRegistry(const []));
  });

  NoteAction voiceOver() => plugins.noteActions().singleWhere((a) => a.id == 'elevenlabs-voice-over');

  group('the note’s Voice-over', () {
    test('says what to do first without a key, and costs nothing', () async {
      final note = TestNote('# Plan\n\nWords to read.');
      expect(voiceOver().enabled(note.noteId, note.body()), isFalse);
      expect(voiceOver().hint(note.noteId, note.body()), 'Add your ElevenLabs key in Settings › ElevenLabs first.');
      expect(await makeVoiceOver(note), isFalse);
      expect(note.said.single, contains('Add your ElevenLabs key'));
      expect(fake.asked, isEmpty);
    });

    test('says the characters and credits before anything is asked, by the model chosen', () async {
      await key();
      const body = '# Plan\n\nWords to read.';
      expect(voiceOver().hint('n', body), 'Read aloud by ElevenLabs with Eleven v4: 21 characters, about 21 ElevenLabs credits. Kept at the top of the note.');
      setModel('eleven_flash_v2_5');
      expect(voiceOver().hint('n', body), contains('with Flash v2.5: 21 characters, about 11 ElevenLabs credits'));
      expect(fake.asked, isEmpty);
    });

    test('lists the voices, the chosen one first, then the rest and the person’s own', () async {
      await key();
      keepOwnVoices(const [ElevenVoice(id: 'mine1', name: 'Matt', line: 'Cloned from a memo')]);
      setVoice('6WwXjDDEMyNmFG95zycZ');
      final choices = voiceOver().choices!('n');
      expect(choices.first.label, 'Eldrin');
      expect(choices.length, offeredVoices.length + 1);
      expect(choices.last.label, 'Matt');
      expect(choices.last.hint, 'Cloned from a memo · Your own voice');
    });

    test('reads the note in the voice pressed, keeps the parts joined as one MP3, and puts it under the title', () async {
      await key();
      final note = TestNote('---\nbook: false\n---\n# Trip\nWe land on **Friday**.\n\n```\ncode\n```');
      expect(await makeVoiceOver(note, 'OZ0L6eISlOejga3XjDFt'), isTrue);
      expect(fake.asked.single, (text: 'Trip.\n\nWe land on Friday.', voice: 'OZ0L6eISlOejga3XjDFt', model: 'eleven_v4'));
      expect(kept.single.name, 'Voice-over, Talia.mp3');
      expect(kept.single.bytes, part(1));
      expect(note.body(), '---\nbook: false\n---\n# Trip\n\n[Voice-over, Talia.mp3](file/00000001-1111-4222-8333-444444444444.mp3 "4 bytes")\n\nWe land on **Friday**.\n\n```\ncode\n```');
      expect(note.said.last, 'Added a voice-over read by Talia, at the top of the note.');
      expect(voiceOverMaking.value, isEmpty);
    });

    test('a long note is read in parts, each said, and joined in order', () async {
      await key();
      final paragraph = List.generate(80, (i) => 'Sentence $i of the long note.').join(' ');
      final note = TestNote('# Long\n\n${List.filled(4, paragraph).join('\n\n')}');
      final heard = <Map<String, String>>[];
      void listen() => heard.add(voiceOverMaking.value);
      voiceOverMaking.addListener(listen);
      expect(await makeVoiceOver(note), isTrue);
      voiceOverMaking.removeListener(listen);
      expect(fake.asked.length, greaterThan(1));
      expect(fake.asked.every((a) => a.text.length <= voiceOverChunk), isTrue);
      expect(fake.asked.every((a) => a.voice == defaultVoiceId), isTrue);
      expect(kept.single.bytes, [for (var i = 1; i <= fake.asked.length; i += 1) ...part(i)]);
      expect(heard.first, {'note-1': 'Part 1 of ${fake.asked.length}'});
      expect(heard.last, isEmpty);
      expect(note.said, contains('ElevenLabs is reading part 2 of ${fake.asked.length}…'));
    });

    test('a voice-over made again takes the old one’s line; a note with no title has it at the top', () async {
      await key();
      final note = TestNote('Just words.\n\n[Voice-over, Elara.mp3](file/old.mp3 "1 MB")');
      expect(await makeVoiceOver(note), isTrue);
      expect(note.body(), 'Just words.\n\n[Voice-over, Elara.mp3](file/00000001-1111-4222-8333-444444444444.mp3 "4 bytes")');
      // The old voice-over is not read.
      expect(fake.asked.single.text, 'Just words.');
      final bare = TestNote('No title here.');
      expect(await makeVoiceOver(bare), isTrue);
      expect(bare.body(), '[Voice-over, Elara.mp3](file/00000002-1111-4222-8333-444444444444.mp3 "4 bytes")\n\nNo title here.');
    });

    test('Eleven v4 refused for the key is read with Multilingual v2, and the note says so', () async {
      await key();
      fake.fails = (model, ask) => model == 'eleven_v4' ? const ElevenFailure('This ElevenLabs key can’t use that model.', status: 403, code: 'model_access_denied') : null;
      final note = TestNote('# A\n\nB.');
      expect(await makeVoiceOver(note), isTrue);
      expect([for (final a in fake.asked) a.model], ['eleven_v4', 'eleven_multilingual_v2']);
      expect(note.said.last, contains('Eleven v4 isn’t open to this key, so Multilingual v2 read it.'));
    });

    test('credits spent, or a key refused, are said and nothing is kept', () async {
      await key();
      fake.fails = (model, ask) => const ElevenFailure('Your ElevenLabs credits are used up for now.', status: 402, code: 'insufficient_credits');
      final note = TestNote('# A\n\nB.');
      expect(await makeVoiceOver(note), isFalse);
      expect(note.said.last, 'Your ElevenLabs credits are used up for now.');
      expect(kept, isEmpty);
      expect(note.body(), '# A\n\nB.');
      expect(voiceOverMaking.value, isEmpty);
    });

    test('a note past the most is refused with its count, and so is one with nothing to read', () async {
      await key();
      final huge = '# Huge\n\n${'word ' * 12000}';
      expect(voiceOver().enabled('n', huge), isFalse);
      expect(voiceOver().hint('n', huge), contains('a voice-over reads at most 50,000'));
      final note = TestNote(huge);
      expect(await makeVoiceOver(note), isFalse);
      expect(fake.asked, isEmpty);
      expect(voiceOver().hint('n', '![x](image/x.png)'), 'There are no words in this note to read aloud.');
    });

    test('one note is read once at a time', () async {
      await key();
      final note = TestNote('# A\n\nB.');
      fake.onAsk = () => fake.onAsk = null;
      final first = makeVoiceOver(note);
      expect(voiceOver().enabled(note.noteId, note.body()), isFalse);
      expect(await makeVoiceOver(note), isFalse);
      expect(note.said, contains('ElevenLabs is already reading this note.'));
      expect(await first, isTrue);
    });
  });

  test('the device is held while a note is read, and let go quietly after', () async {
    final jobs = Jobs();
    final hold = ElevenLabsHold(background: jobs)..start();
    await key();
    final note = TestNote('# A\n\nB.');
    expect(await makeVoiceOver(note), isTrue);
    expect(jobs.told, ['running $voiceOverJobId Making a voice-over with ElevenLabs: Reading', 'ended $voiceOverJobId quietly']);
    hold.dispose();
  });

  group('the ElevenLabs page', () {
    Finder field() => find.descendant(of: find.byWidgetPredicate((w) => w is PlainField && w.label == 'ElevenLabs API key'), matching: find.byType(EditableText));

    testWidgets('refuses a key ElevenLabs refuses, and keeps nothing', (tester) async {
      ground = useGround((request) async => FetchResponse.json(401, {'detail': {'code': 'invalid_api_key', 'message': 'Invalid API key'}}));
      elevenLabsClient = () => ElevenLabsClient.kept();
      await pumpPane(tester, const ElevenLabsPane());
      expect(actionEnabled(tester, 'Keep it'), isFalse);
      await tester.enterText(field(), 'sk_wrong');
      await tester.pump();
      await press(tester, action('Keep it'));
      expect(ground.asked.single.url.path, '/v1/user');
      expect(textOf(tester), contains('ElevenLabs refused that key'));
      expect(ground.secrets.held, isEmpty);
      await away(tester);
    });

    testWidgets('keeps a key that works, trimmed, says the month, then forgets it when Forget is pressed twice', (tester) async {
      ground = useGround((request) async => request.url.path == '/v1/user'
          ? FetchResponse.json(200, {
              'subscription': {'tier': 'creator', 'character_count': 2500, 'character_limit': 100000},
            })
          : FetchResponse.json(200, {'voices': <Object?>[]}));
      elevenLabsClient = () => ElevenLabsClient.kept();
      await pumpPane(tester, const ElevenLabsPane());
      expect(elevenLabsPlugin.settings!.summary(), 'Not set up');
      await tester.enterText(field(), '  sk_typed  ');
      await tester.pump();
      await press(tester, action('Keep it'));
      await settle(tester);
      expect(ground.secrets.held, {apiKeySecret: 'sk_typed'});
      expect(textOf(tester), contains('The key works.'));
      expect(textOf(tester), contains('2,500 of 100,000 credits used this month.'));
      expect(textOf(tester), isNot(contains('sk_typed')));
      expect(elevenLabsPlugin.settings!.summary(), 'Key kept · Elara');
      await press(tester, action('Forget'));
      await press(tester, action('Tap again'));
      expect(ground.secrets.held, isEmpty);
      expect(field(), findsOneWidget);
      await away(tester);
    });

    testWidgets('a voice picked is the one voice-overs are read in', (tester) async {
      await pumpPane(tester, const ElevenLabsPane());
      expect(chosenVoice().id, defaultVoiceId);
      final row = find.byKey(const ValueKey('elevenlabs-voice-jSuBIjxMKhqIfb0wCK1F'));
      await tester.ensureVisible(row);
      await tester.tap(find.descendant(of: row, matching: find.byType(Pick)));
      await settle(tester);
      expect(chosenVoice().name, 'Baxter');
      expect(eleven.host.storage.get<Object?>(eleven.voiceKey, null), 'jSuBIjxMKhqIfb0wCK1F');
      await away(tester);
    });
  });
}
