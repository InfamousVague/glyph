// Header banners made by Lovart in the ghost's dotwork (lib/plugins/lovart/banners.dart, lib/core/banner.dart).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/banner.dart';
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/lovart/lovart.dart';
import 'package:ghost_md/plugins/lovart/manifest.dart' as lovart;
import 'package:ghost_md/plugins/registry.dart';
import 'package:glacier/glacier.dart' show GlacierSwitch;

import '../github/support.dart';
import 'lovart_test.dart' show FakeClient;

const String _words = 'We drove down on Friday, stayed in the old house by the river, walked the market on Saturday morning, '
    'ate far too much at the corner place, and came home on Sunday with a bag of oranges and a plan to go back in spring.';

void main() {
  late MemoryPictureStore pictures;
  late FakeClient fake;
  late Map<String, Note> notes;
  late LovartBanners banners;
  late List<String> told;

  Future<void> keys() async {
    await lovart.host.secrets.write(accessKeySecret, 'ak-1');
    await lovart.host.secrets.write(secretKeySecret, 'sk-1');
  }

  Note note(String id, String body, {int revision = 1, int? recordingMs}) => notes[id] = Note(id: id, body: body, createdAt: 0, updatedAt: 0, revision: revision, recordingMs: recordingMs);

  setUp(() async {
    useGround();
    pictures = MemoryPictureStore();
    lovartPictureStore = pictures;
    fake = FakeClient();
    lovartClient = () => fake;
    final registry = createRegistry([lovartPlugin], store: MemorySwitches());
    registry.setEnabled('lovart', true);
    usePlugins(registry);
    notes = {};
    told = [];
    banners = LovartBanners(
      getNote: (id) async => notes[id],
      update: (id, body, revision) async {
        expect(revision, notes[id]!.revision);
        return notes[id] = notes[id]!.copyWith(body: body, revision: revision + 1);
      },
      done: told.add,
    );
  });

  tearDown(() {
    lovartPictureStore = null;
    lovartClient = () => LovartClient.kept();
    usePluginGround(PluginGround());
    usePlugins(createRegistry(const []));
  });

  group('the banner in front matter', () {
    test('is a picture\'s own Markdown, quoted, so its picture travels with the note', () {
      final body = withBanner('# Trip\n\nWords.', 'lovart-img-1.png');
      expect(body, '---\nbanner: "![](image/lovart-img-1.png)"\n---\n# Trip\n\nWords.');
      expect(bannerOf(body), 'lovart-img-1.png');
      expect(imageNames(body), ['lovart-img-1.png']);
      expect(withBanner(body, null), '# Trip\n\nWords.');
      expect(bannerOf('---\nbanner: nothing here\n---\n# x'), isNull);
      expect(bannerOf('# x\n\n![](image/a.png)'), isNull);
    });

    test('is added beside what the front matter holds, and replaces a banner there', () {
      const located = '---\nlocation: 1,2\n---\n# Trip';
      final once = withBanner(located, 'a.png');
      expect(once, '---\nlocation: 1,2\nbanner: "![](image/a.png)"\n---\n# Trip');
      expect(withBanner(once, 'b.png'), '---\nlocation: 1,2\nbanner: "![](image/b.png)"\n---\n# Trip');
    });
  });

  group('the prompt', () {
    test('is the ghost\'s dotwork, with the note\'s title and opening as the subject', () {
      final prompt = bannerPrompt('---\nlocation: 1,2\n---\n# New Orleans weekend\n\n$_words\n\n![](image/x.png)');
      expect(prompt, startsWith('A wide banner illustration, 4:1 landscape, for the header of a note in Ghost.md'));
      expect(prompt, contains('A stipple dotwork illustration in full colour on pure white'));
      expect(prompt, isNot(contains('no colour')), reason: 'full colour since 2026-10-26');
      expect(prompt, contains('one small corner folded down like a dog-eared page'));
      expect(prompt, contains('A single thin curl of smoke rises from the top of its head.'));
      expect(prompt, contains('The note is titled “New Orleans weekend”.'));
      expect(prompt, contains('We drove down on Friday'));
      expect(prompt, contains('The left third is empty white.'));
      expect(prompt, isNot(contains('location: 1,2')));
      expect(prompt, isNot(contains('image/x.png')));
      expect(prompt, endsWith('Make one image.'));
    });

    test('takes only the opening of a long note', () {
      final prompt = bannerPrompt('# Long\n\n${'word ' * 2000}');
      expect(prompt.length, lessThan(bannerStyle('').length + bannerChars + 300));
    });
  });

  group('which notes have one', () {
    Note plain(String body, {int? recordingMs}) => Note(id: 'n', body: body, createdAt: 0, updatedAt: 0, recordingMs: recordingMs);

    test('a note of its own words does', () {
      expect(wantsBanner(plain('# Trip\n\n$_words')), isTrue);
      expect(wantsBanner(plain('---\nlocation: 1,2\n---\n# Trip\n\n$_words')), isTrue);
      // A spoken note with no write-up is a note.
      expect(wantsBanner(plain('# Trip\n\n$_words', recordingMs: 4000)), isTrue);
    });

    test('a short note, a ticket, a meeting, a mail, a notebook or a canvas does not, nor one with a banner', () {
      expect(wantsBanner(plain('# Groceries\n\n- [ ] milk\n- [ ] eggs')), isFalse);
      expect(wantsBanner(plain('---\ntype: ticket\n---\n# Fix it\n\n$_words')), isFalse);
      expect(wantsBanner(plain('# Standup\n\nGhost was in this meeting on 18 Oct, 14:00 to 14:45.\n\n$_words')), isFalse);
      expect(wantsBanner(plain('# Standup\n\n## Summary\n\n$_words', recordingMs: 60000)), isFalse);
      expect(wantsBanner(plain('---\nfrom: "Sam <sam@example.com>"\n---\n# Invite\n\n$_words')), isFalse);
      expect(wantsBanner(plain('---\nbook: true\n---\n# Book\n\n$_words')), isFalse);
      expect(wantsBanner(plain('{"nodes":[],"edges":[]}')), isFalse);
      expect(wantsBanner(plain(withBanner('# Trip\n\n$_words', 'a.png'))), isFalse);
      expect(wantsBanner(Note(id: 'n', body: '# Trip\n\n$_words', createdAt: 0, updatedAt: 0, archivedAt: 5)), isFalse);
    });
  });

  group('made as a note is left', () {
    test('on by default once Lovart is added; written into the note as it is then, once', () async {
      await keys();
      expect(bannersOn(), isTrue);
      note('t1', '# Trip\n\n$_words', revision: 3);
      expect(await banners.noteLeft('t1'), isTrue);
      expect(fake.asked.single, bannerPrompt('# Trip\n\n$_words'));
      final name = pictures.kept.keys.single;
      expect(name, startsWith('lovart-'));
      expect(notes['t1']!.body, '---\nbanner: "![](image/$name)"\n---\n# Trip\n\n$_words');
      expect(notes['t1']!.revision, 4);
      expect(told, ['t1']);
      expect(lovartBannerMaking.value, isEmpty);
      // Taken off, it is not made again by itself.
      note('t1', '# Trip\n\n$_words', revision: 5);
      expect(await banners.noteLeft('t1'), isFalse);
      expect(fake.asked, hasLength(1));
    });

    test('keeps only the first picture when Lovart makes more', () async {
      await keys();
      fake.count = 3;
      note('t1', '# Trip\n\n$_words');
      expect(await banners.noteLeft('t1'), isTrue);
      expect(pictures.kept, hasLength(1));
    });

    test('nothing with the switch off, the plugin off, no keys, or for a note that is not one to have it', () async {
      note('t1', '# Trip\n\n$_words');
      expect(await banners.noteLeft('t1'), isFalse, reason: 'no keys');
      await keys();
      setBanners(false);
      expect(await banners.noteLeft('t1'), isFalse, reason: 'switched off');
      setBanners(true);
      plugins.setEnabled('lovart', false);
      expect(await banners.noteLeft('t1'), isFalse, reason: 'plugin off');
      plugins.setEnabled('lovart', true);
      note('s1', '# Groceries\n\n- [ ] milk');
      expect(await banners.noteLeft('s1'), isFalse, reason: 'too short');
      expect(await banners.noteLeft('gone'), isFalse, reason: 'no such note');
      expect(fake.asked, isEmpty);
    });

    test('a failure is said to the log, writes nothing, and is not asked again', () async {
      await keys();
      final warned = <String>[];
      banners = LovartBanners(getNote: (id) async => notes[id], update: (id, body, revision) async => throw StateError('no'), warn: warned.add);
      fake.fails = const LovartFailure('Your Lovart credits have run out.');
      note('t1', '# Trip\n\n$_words');
      expect(await banners.noteLeft('t1'), isFalse);
      expect(warned.single, contains('credits'));
      fake.fails = null;
      expect(await banners.noteLeft('t1'), isFalse);
      expect(fake.asked, hasLength(1));
    });

    test('a banner given by hand meanwhile stands', () async {
      await keys();
      note('t1', '# Trip\n\n$_words');
      fake.onAsk = () => note('t1', withBanner('# Trip\n\n$_words', 'mine.png'), revision: 2);
      expect(await banners.noteLeft('t1'), isFalse);
      expect(bannerOf(notes['t1']!.body), 'mine.png');
    });
  });

  group('a run over the recent notes', () {
    setUp(() {
      lovartBannerRun.value = null;
      lovartBannerSource = (notes: () => notes.values.toList(), banners: banners);
    });
    tearDown(() => lovartBannerSource = null);

    Note dated(String id, String body, int at) => notes[id] = Note(id: id, body: body, createdAt: 0, updatedAt: at);

    test('picks the newest notes that are ones to have a banner, at most a hundred', () {
      for (var i = 0; i < 120; i += 1) {
        dated('n$i', '# Note $i\n\n$_words', i);
      }
      dated('ticket', '---\ntype: ticket\n---\n# Fix\n\n$_words', 500);
      dated('meeting', '# Standup\n\nGhost was in this meeting on 18 Oct, 14:00 to 14:45.\n\n$_words', 501);
      dated('short', '# Milk', 502);
      final picked = bannerCandidates(notes.values.toList());
      expect(picked, hasLength(100));
      expect(picked.first.id, 'n119');
      expect(picked.last.id, 'n20');
    });

    test('gives each its banner, says how far it is, and leaves done ones alone after', () async {
      await keys();
      for (var i = 0; i < 5; i += 1) {
        dated('n$i', '# Note $i\n\n$_words', i);
      }
      final seen = <int>[];
      void hear() => seen.add(lovartBannerRun.value!.done);
      lovartBannerRun.addListener(hear);
      await runBanners();
      lovartBannerRun.removeListener(hear);
      expect(fake.asked, hasLength(5));
      expect([for (final n in notes.values) bannerOf(n.body) != null], everyElement(isTrue));
      expect((lovartBannerRun.value!.done, lovartBannerRun.value!.made, lovartBannerRun.value!.running), (5, 5, false));
      expect(seen, containsAllInOrder([0, 1, 2, 3, 4, 5]));
      await runBanners();
      expect(lovartBannerRun.value!.total, 0);
      expect(fake.asked, hasLength(5));
    });

    test('credits spent stop it, and the notes not made are tried again next time', () async {
      await keys();
      for (var i = 0; i < 6; i += 1) {
        dated('n$i', '# Note $i\n\n$_words', i);
      }
      fake.fails = const LovartFailure('Your Lovart credits have run out.');
      await runBanners();
      expect(lovartBannerRun.value!.running, isFalse);
      expect(lovartBannerRun.value!.made, 0);
      expect(lovartBannerRun.value!.stopped, contains('credits'));
      expect(fake.asked.length, lessThanOrEqualTo(3));
      fake.fails = null;
      await runBanners();
      expect(lovartBannerRun.value!.made, 6);
    });

    test('says what is missing without keys', () async {
      await runBanners();
      expect(lovartBannerRun.value!.stopped, contains('Lovart keys'));
      expect(fake.asked, isEmpty);
    });
  });

  group('Header image, on the note\'s cog', () {
    test('writes front matter before a note with none', () async {
      await keys();
      final open = TestNote('# Trip\n\n$_words');
      await makeBanner(open);
      final name = pictures.kept.keys.single;
      expect(open.body(), '---\nbanner: "![](image/$name)"\n---\n# Trip\n\n$_words');
      expect(open.said.first, 'Lovart is making a header image…');
    });

    test('adds to front matter there is, and makes it again where there is one', () async {
      await keys();
      final open = TestNote('---\nlocation: 1,2\n---\n# Trip\n\nWords.');
      await makeBanner(open);
      final first = pictures.kept.keys.single;
      expect(open.body(), '---\nlocation: 1,2\nbanner: "![](image/$first)"\n---\n# Trip\n\nWords.');
      await makeBanner(open);
      final second = pictures.kept.keys.last;
      expect(second, isNot(first));
      expect(open.body(), '---\nlocation: 1,2\nbanner: "![](image/$second)"\n---\n# Trip\n\nWords.');
    });

    test('says what is missing rather than asking Lovart without keys', () async {
      final open = TestNote('# Trip\n\n$_words');
      await makeBanner(open);
      expect(fake.asked, isEmpty);
      expect(open.said.single, contains('Lovart keys'));
    });

    test('is a row of the cog', () {
      final row = lovartPlugin.noteActions.singleWhere((action) => action.id == 'lovart-banner');
      expect(row.label, 'Header image');
      expect(row.hint('n', '# Trip'), contains('Lovart keys'));
    });
  });

  group('the Lovart page', () {
    testWidgets('switches Header images for notes, on until then', (tester) async {
      await pumpPane(tester, const LovartPane());
      expect(bannersOn(), isTrue);
      final row = find.byKey(const ValueKey('lovart-banners'));
      await tester.ensureVisible(row);
      await tester.tap(find.descendant(of: row, matching: find.byType(GlacierSwitch)));
      await settle(tester);
      expect(bannersOn(), isFalse);
      await away(tester);
    });
  });
}
