// The Lovart plugin at work (lib/plugins/lovart/lovart.dart, meetings.dart, lovart_pane.dart): a cue made into its
// picture, kept first and named `lovart-…`; every cue in order; inspiration under its heading; a design meeting given
// inspiration once, only where it was asked for; and the keys' page, which keeps only keys Lovart accepts.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/lovart/lovart.dart';
import 'package:ghost_md/plugins/lovart/manifest.dart' as lovart;
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/github/plain_field.dart';
import 'package:glacier/glacier.dart' show GlacierSwitch;

import '../github/support.dart';

final Uint8List png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 9, 9]);

/// Lovart, answering each prompt with [count] pictures, or with [fails].
class FakeClient extends LovartClient {
  FakeClient({this.count = 1, this.fails}) : super(accessKey: 'ak', secretKey: 'sk');

  int count;
  LovartFailure? fails;
  final List<String> asked = [];

  /// Run as each prompt is asked, before the answer: a note changing while Lovart works.
  void Function()? onAsk;

  @override
  Future<List<Uint8List>> generate(String prompt, {Duration timeout = lovartTimeout}) async {
    asked.add(prompt);
    onAsk?.call();
    if (fails != null) throw fails!;
    return [for (var i = 0; i < count; i++) png];
  }
}

void main() {
  late TestGround ground;
  late MemoryPictureStore pictures;
  late FakeClient fake;

  Future<void> keys() async {
    await lovart.host.secrets.write(accessKeySecret, 'ak-1');
    await lovart.host.secrets.write(secretKeySecret, 'sk-1');
  }

  setUp(() async {
    ground = useGround();
    pictures = MemoryPictureStore();
    lovartPictureStore = pictures;
    fake = FakeClient();
    lovartClient = () => fake;
    final registry = createRegistry([lovartPlugin], store: MemorySwitches());
    registry.setEnabled('lovart', true);
    usePlugins(registry);
  });

  tearDown(() {
    lovartPictureStore = null;
    lovartClient = () => LovartClient.kept();
    usePluginGround(PluginGround());
    usePlugins(createRegistry(const []));
  });

  test('offers an image in the +\'s list while it is on, under its own mark, the words to draw selected', () {
    final insert = plugins.inserts().single;
    expect((insert.id, insert.words, insert.text), ('lovart-image', 'An image by Lovart', '{image: what to draw}'));
    expect(insert.text.substring(insert.select!.from, insert.select!.to), 'what to draw');
    expect(identical(insert.icon, lovartIcon), isTrue);
    plugins.setEnabled('lovart', false);
    expect(plugins.inserts(), isEmpty);
  });

  group('cues', () {
    test('a cue becomes its picture, kept before its line is written, named lovart-…', () async {
      await keys();
      final note = TestNote('# Ideas\n\nThe cover {image: a fox in one line} goes here.');
      expect(await makeCue(note, imageCues(note.body()).single), isTrue);
      expect(fake.asked, ['a fox in one line\n\nMake one image.']);
      final name = pictures.kept.keys.single;
      expect(name, matches(RegExp(r'^lovart-[0-9a-f-]{36}\.png$')));
      expect(madeByLovart(name), isTrue);
      expect(note.body(), '# Ideas\n\nThe cover goes here.\n![a fox in one line](image/$name)');
    });

    test('says what is missing rather than asking Lovart without keys', () async {
      final note = TestNote('{image: a chair}');
      expect(await makeCue(note, imageCues(note.body()).single), isFalse);
      expect(fake.asked, isEmpty);
      expect(note.said.single, contains('Lovart keys'));
    });

    test('Make images makes every cue in order; a refusal leaves its cue and goes on, a credits failure stops', () async {
      await keys();
      final note = TestNote('{image: one}\n{image: two}');
      await makeAllCues(note);
      expect(fake.asked.length, 2);
      expect(imageCues(note.body()), isEmpty);
      expect(note.said.last, 'Made 2 images with Lovart.');

      final refused = TestNote('{image: no}\n{image: yes}');
      var n = 0;
      lovartClient = () => FakeClient(fails: n++ == 0 ? const LovartRefused('Not that one.') : null);
      await makeAllCues(refused);
      expect(imageCues(refused.body()).map((c) => c.prompt), ['no']);
      expect(refused.said, contains('Lovart made no image: Not that one.'));

      final broke = TestNote('{image: a}\n{image: b}');
      final out = FakeClient(fails: const LovartFailure('Insufficient credits.', status: 402, code: 2012));
      lovartClient = () => out;
      await makeAllCues(broke);
      expect(out.asked, hasLength(1));
      expect(broke.said.last, 'Insufficient credits.');
    });

    test('a costly step waiting is said with its cost and the cue stays', () async {
      await keys();
      fake.fails = const LovartNeedsConfirmation(cost: 30, threadId: 't');
      final note = TestNote('{image: a film}');
      await makeAllCues(note);
      expect(note.body(), '{image: a film}');
      expect(note.said.last, contains('about 30 credits'));
    });

    test('the actions show where they can do something, and wait for the keys', () async {
      final make = lovartPlugin.noteActions.firstWhere((a) => a.id == 'lovart-cues');
      expect(make.visible('n', 'no cues'), isFalse);
      expect(make.visible('n', 'a {image: cue}'), isTrue);
      expect(make.enabled('n', 'a {image: cue}'), isFalse);
      await keys();
      expect(make.enabled('n', 'a {image: cue}'), isTrue);
      expect(make.hint('n', '{image: a}{image: b}'), contains('2 {image: …} become pictures'));
    });
  });

  test('Inspiration images asks for a moodboard of four and adds them under ## Inspiration', () async {
    await keys();
    fake.count = 4;
    final note = TestNote('# Brand refresh\n\nWarmer, more hand-made.');
    await makeInspiration(note);
    expect(fake.asked.single, contains('moodboard of 4'));
    final names = pictures.kept.keys.toList();
    expect(note.body(), '# Brand refresh\n\nWarmer, more hand-made.\n\n## Inspiration\n\n${[for (final n in names) '![Inspiration](image/$n)'].join('\n')}');
    expect(note.said.last, 'Added 4 inspiration images.');
  });

  group('design meetings', () {
    late Map<String, Note> notes;
    late LovartMeetings meetings;
    const design = '# Logo review\n\n## Summary\n\nWe compared three marks and a palette.\n\n- [ ] Sam: refine the mark';

    setUp(() {
      notes = {'m1': Note(id: 'm1', body: design, createdAt: 0, updatedAt: 0, revision: 3)};
      meetings = LovartMeetings(
        getNote: (id) async => notes[id],
        update: (id, body, revision) async {
          expect(revision, notes[id]!.revision);
          return notes[id] = notes[id]!.copyWith(body: body, revision: revision + 1);
        },
      );
    });

    test('nothing until the switch is on, and never without keys', () async {
      await keys();
      expect(await meetings.meetingSummarized('m1', design), isFalse);
      setDesignMeetings(true);
      await lovart.host.secrets.write(accessKeySecret, null);
      expect(await meetings.meetingSummarized('m1', design), isFalse);
      expect(fake.asked, isEmpty);
    });

    test('a design meeting gets its inspiration in the closed note, once', () async {
      await keys();
      setDesignMeetings(true);
      fake.count = 4;
      expect(await meetings.meetingSummarized('m1', design), isTrue);
      expect(notes['m1']!.body, startsWith('$design\n\n## Inspiration\n\n![Inspiration](image/lovart-'));
      expect(notes['m1']!.revision, 4);
      // A summary made again asks nothing more.
      expect(await meetings.meetingSummarized('m1', notes['m1']!.body), isFalse);
      expect(fake.asked, hasLength(1));
    });

    test('a meeting that is not about design is left alone', () async {
      await keys();
      setDesignMeetings(true);
      const standup = '# Engineering standup\n\n## Summary\n\nThe deploy went out; the login bug is fixed.';
      notes['s1'] = Note(id: 's1', body: standup, createdAt: 0, updatedAt: 0);
      expect(await meetings.meetingSummarized('s1', standup), isFalse);
      expect(fake.asked, isEmpty);
    });

    test('nothing while the plugin is off', () async {
      await keys();
      setDesignMeetings(true);
      plugins.setEnabled('lovart', false);
      expect(await meetings.meetingSummarized('m1', design), isFalse);
    });
  });

  group('the Lovart page', () {
    Finder field(String label) => find.descendant(of: find.byWidgetPredicate((w) => w is PlainField && w.label == label), matching: find.byType(EditableText));

    Future<void> type(WidgetTester tester) async {
      await tester.enterText(field('Lovart access key'), ' ak-typed ');
      await tester.enterText(field('Lovart secret key'), 'sk-typed');
      await tester.pump();
    }

    testWidgets('refuses keys Lovart refuses, and keeps nothing', (tester) async {
      ground = useGround((request) async => FetchResponse.json(401, {'message': 'bad signature'}));
      await pumpPane(tester, const LovartPane());
      expect(actionEnabled(tester, 'Keep them'), isFalse);
      await type(tester);
      await press(tester, action('Keep them'));
      expect(ground.asked.single.url.path, '/v1/openapi/mode/query');
      expect(textOf(tester), contains('Lovart refused those keys'));
      expect(ground.secrets.held, isEmpty);
      await away(tester);
    });

    testWidgets('keeps keys that work, trimmed, then only says they are kept, until Forget is pressed twice', (tester) async {
      ground = useGround((request) async => FetchResponse.json(200, {'code': 0, 'data': {}}));
      await pumpPane(tester, const LovartPane());
      expect(lovartPlugin.settings!.summary(), 'Not set up');
      await type(tester);
      await press(tester, action('Keep them'));
      expect(ground.secrets.held, {accessKeySecret: 'ak-typed', secretKeySecret: 'sk-typed'});
      expect(textOf(tester), contains('The keys work.'));
      expect(textOf(tester), isNot(contains('sk-typed')));
      expect(lovartPlugin.settings!.summary(), 'Keys kept');
      await press(tester, action('Forget'));
      await press(tester, action('Tap again'));
      expect(ground.secrets.held, isEmpty);
      expect(field('Lovart access key'), findsOneWidget);
      await away(tester);
    });

    testWidgets('switches Inspiration for design meetings, off until then', (tester) async {
      await pumpPane(tester, const LovartPane());
      expect(designMeetingsOn(), isFalse);
      await tester.ensureVisible(find.byKey(const ValueKey('lovart-design-meetings')));
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('lovart-design-meetings')), matching: find.byType(GlacierSwitch)));
      await settle(tester);
      expect(designMeetingsOn(), isTrue);
      await away(tester);
    });
  });
}
