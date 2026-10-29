// Header banners made by Lovart in the ghost's dotwork (lib/plugins/lovart/banners.dart, lib/core/banner.dart), and
// the run over the recent notes as the app's own job (lib/plugins/lovart/banner_run.dart).
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/summary_handoff.dart' show SummaryDevice;
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/banner.dart';
import 'package:ghost_md/core/book.dart' show bookNoteBody;
import 'package:ghost_md/core/images.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart' show MemoryStored;
import 'package:ghost_md/sync/prefs.dart' show merged;
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/lovart/lovart.dart';
import 'package:ghost_md/plugins/lovart/manifest.dart' as lovart;
import 'package:ghost_md/plugins/registry.dart';
import 'package:glacier/glacier.dart' show GlacierSwitch;

import '../github/support.dart';
import 'lovart_test.dart' show FakeClient;

const String _words = 'We drove down on Friday, stayed in the old house by the river, walked the market on Saturday morning, '
    'ate far too much at the corner place, and came home on Sunday with a bag of oranges and a plan to go back in spring.';

/// Lovart on a plan of one job at a time: a job asked while another runs is refused, code 2011.
class _OneAtATime extends FakeClient {
  int running = 0, most = 0, refused = 0;

  @override
  Future<List<Uint8List>> generate(String prompt, {Duration timeout = lovartTimeout}) async {
    if (running > 0) {
      refused += 1;
      throw const LovartFailure('Concurrent job limit reached.', code: 2011);
    }
    running += 1;
    if (running > most) most = running;
    try {
      await Future<void>.delayed(Duration.zero);
      return super.generate(prompt, timeout: timeout);
    } finally {
      running -= 1;
    }
  }
}

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
      expect(prompt, startsWith('A wide 16:9 landscape illustration, 1920 by 1080 pixels, never square'));
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
      expect(wantsBanner(plain('---\nbook: true\njournal: true\n---\n# Journal\n\n$_words')), isFalse);
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

    test('is a job of its own on the app\'s record: "Header image for Trip", then "Banner ready · View" where the note is not on screen', () async {
      final record = Activity(store: () => MemoryStored());
      useActivity(record);
      addTearDown(() => useActivity(Activity()));
      final opened = <String>[];
      activityRoutes
        ..openNote = opened.add
        ..showing = ((id) => false);
      addTearDown(() => activityRoutes
        ..openNote = null
        ..showing = null);
      await keys();
      final seen = <Job>[];
      final hearing = record.events.listen((e) => seen.add(e.job ?? seen.last));
      fake.onAsk = () => expect(record['banner:t1']?.title, 'Header image for Trip');
      note('t1', '# Trip\n\n$_words');
      expect(await banners.noteLeft('t1'), isTrue);
      await hearing.cancel();
      final ended = seen.lastWhere((job) => job.state == JobState.done);
      expect(ended.result!.words, 'Banner ready');
      expect(ended.shownHere!(), isFalse);
      ended.result!.onOpen!();
      expect(opened, ['t1']);
      expect(record.log.today.words, '1 banner');
      fake.onAsk = null;
      // Credits gone: red, with Top up; Lovart busy a moment is no failure.
      fake.fails = const LovartFailure('Your Lovart credits have run out.', code: 2012);
      note('t2', '# Trip two\n\n$_words');
      expect(await banners.noteLeft('t2'), isFalse);
      expect(record['banner:t2']!.state, JobState.failed);
      expect(record['banner:t2']!.fix!.kind, JobFixKind.topUp);
      fake.fails = const LovartFailure('Concurrent job limit reached.', code: 2011);
      note('t3', '# Trip three\n\n$_words');
      expect(await banners.noteLeft('t3'), isFalse);
      expect(record['banner:t3'], isNull);
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

    test('Lovart busy leaves the note to be asked again when it is next left', () async {
      await keys();
      fake.fails = const LovartFailure('Concurrent job limit reached.', code: 2011);
      note('t1', '# Trip\n\n$_words');
      expect(await banners.noteLeft('t1'), isFalse);
      fake.fails = null;
      expect(await banners.noteLeft('t1'), isTrue);
      expect(fake.asked, hasLength(2));
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
      lovartBannerJob = BannerJob(notes: () => notes.values.toList(), banners: banners);
    });
    tearDown(() => lovartBannerJob = null);

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

    test('Lovart at its limit of jobs at once slows the run to what it takes, and the run finishes', () async {
      await keys();
      for (var i = 0; i < 6; i += 1) {
        dated('n$i', '# Note $i\n\n$_words', i);
      }
      // A plan that takes one job at a time: a second asked while one runs is refused as Lovart refuses it.
      final busy = _OneAtATime();
      lovartClient = () => busy;
      final waits = <Duration>[];
      lovartBannerJob = BannerJob(notes: () => notes.values.toList(), banners: banners, wait: (wait) async => waits.add(wait));
      await runBanners();
      expect((lovartBannerRun.value!.made, lovartBannerRun.value!.running, lovartBannerRun.value!.stopped), (6, false, null));
      expect(busy.refused, greaterThan(0));
      expect(busy.most, 1, reason: 'never more than one at once once it had said so');
      expect(waits, isNotEmpty);
      expect([for (final n in notes.values) bannerOf(n.body) != null], everyElement(isTrue));
    });

    test('a limit that never lifts stops the run, saying so, and keeps the rest for later', () async {
      await keys();
      for (var i = 0; i < 2; i += 1) {
        dated('n$i', '# Note $i\n\n$_words', i);
      }
      fake.fails = const LovartFailure('You have reached the concurrent job limit for your plan.', code: 2011);
      expect(fake.fails!.busy, isTrue);
      lovartBannerJob = BannerJob(notes: () => notes.values.toList(), banners: banners, wait: (_) async {});
      await runBanners();
      expect(lovartBannerRun.value!.running, isFalse);
      expect(lovartBannerRun.value!.stopped, contains('limit of jobs at once'));
      expect(lovartBannerRun.value!.made, 0);
      fake.fails = null;
      await runBanners();
      expect(lovartBannerRun.value!.made, 2);
    });

    test('a connection lost a moment waits and goes on, not stopping the run', () async {
      await keys();
      for (var i = 0; i < 3; i += 1) {
        dated('n$i', '# Note $i\n\n$_words', i);
      }
      var lost = 2;
      fake.onAsk = () {
        if (lost > 0) {
          lost -= 1;
          fake.fails = const LovartFailure(lovartUnreachable);
        } else {
          fake.fails = null;
        }
      };
      lovartBannerJob = BannerJob(notes: () => notes.values.toList(), banners: banners, wait: (_) async {});
      await runBanners();
      expect((lovartBannerRun.value!.made, lovartBannerRun.value!.stopped), (3, null));
    });

    test('reads Lovart\'s refusals as busy only where they are', () {
      expect(const LovartFailure('x', status: 429).busy, isTrue);
      expect(const LovartFailure('x', status: 409).busy, isTrue);
      expect(const LovartFailure('x', code: 2011).busy, isTrue);
      expect(const LovartFailure('Too many concurrent tasks').busy, isTrue);
      expect(const LovartFailure('Your Lovart credits have run out.', code: 2012).busy, isFalse);
      expect(const LovartFailure('Lovart didn’t accept these keys.', status: 401).busy, isFalse);
    });

    test('says what is missing without keys', () async {
      await runBanners();
      expect(lovartBannerRun.value!.stopped, contains('Lovart keys'));
      expect(fake.asked, isEmpty);
    });
  });

  group('the run as the app\'s own job', () {
    late GatedClient gated;
    late FakeJobs jobs;
    late BannerJob job;

    Note dated(String id, String body, int at) => notes[id] = Note(id: id, body: body, createdAt: 0, updatedAt: at);

    void five() {
      for (var i = 0; i < 5; i += 1) {
        dated('n$i', '# Note $i\n\n$_words', i);
      }
    }

    BannerJob made({BannerClaims? claims}) => BannerJob(notes: () => notes.values.toList(), banners: banners, background: jobs, claims: claims);

    setUp(() async {
      await keys();
      gated = GatedClient();
      lovartClient = () => gated;
      jobs = FakeJobs();
      lovartBannerRun.value = null;
      lovartBannerMaking.value = const {};
      lovartBannerJob = job = made();
    });
    tearDown(() {
      gated.openAll();
      lovartBannerJob = null;
      lovartBannerMaking.value = const {};
    });

    testWidgets('starts from the page and goes on once the page is closed', (tester) async {
      five();
      await pumpPane(tester, const LovartPane());
      final row = find.byKey(const ValueKey('lovart-banner-run'));
      await tester.ensureVisible(row);
      await tester.tap(find.descendant(of: row, matching: find.text('Make them')));
      await tester.pump();
      // Five at about 6 credits each is over 20: asked first, with what it should cost and take (docs/ACTIVITY.md).
      expect(lovartBannerRun.value, isNull, reason: 'nothing started before Start');
      expect(find.text('5 header images · ~30 Lovart credits · ~2 min'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cost-ask-start')));
      await tester.pump();
      expect(lovartBannerRun.value!.running, isTrue);
      await tester.pump();
      expect(find.descendant(of: row, matching: find.text('Stop')), findsOneWidget);
      expect(find.textContaining('Making header images · 0 of 5'), findsOneWidget);
      // Settings closed while Lovart is still at work.
      await away(tester);
      expect(job.running, isTrue);
      gated.openAll();
      for (var i = 0; i < 20 && job.running; i += 1) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(job.running, isFalse);
      expect([for (final n in notes.values) bannerOf(n.body) != null], everyElement(isTrue));
      expect((lovartBannerRun.value!.made, lovartBannerRun.value!.running), (5, false));
      expect(jobs.ends.single, 'Header images made for 5 notes · about 30 credits');
      expect(keptBannerQueue(), isNull, reason: 'a run that ended takes its queue with it');
    });

    test('says how far it is, to the page, the line and the phone, three at a time', () async {
      five();
      final running = job.start();
      await pumpEvents();
      expect(gated.waiting, 3, reason: 'three asked of Lovart at once');
      expect(lovartBannerRun.value!.done, 0);
      expect(bannerRunLine(lovartBannerRun.value!), 'Making header images · 0 of 5');
      gated.openOne();
      await pumpEvents();
      expect(lovartBannerRun.value!.done, 1);
      expect(gated.waiting, 3, reason: 'the next one asked as soon as one is done');
      expect(jobs.said.last, (title: 'Making header images', text: '1 of 5', done: 1, total: 5));
      gated.openAll();
      await running;
      expect(jobs.said.map((r) => r.done), containsAllInOrder([0, 1, 2, 3, 4, 5]));
      expect(jobs.ends, ['Header images made for 5 notes · about 30 credits']);
    });

    test('Stop ends it after the pictures being made, and leaves the rest for another run', () async {
      five();
      final running = job.start();
      await pumpEvents();
      stopBannerRun();
      gated.openAll();
      await running;
      final run = lovartBannerRun.value!;
      expect((run.made, run.asked, run.running), (3, true, false));
      expect(gated.asked, hasLength(3));
      expect(bannerRunEndWords(run), 'Header images stopped · 3 made · about 18 credits');
      expect(jobs.ends.single, 'Header images stopped · 3 made · about 18 credits');
      expect(keptBannerQueue(), isNull);
      // The two it did not reach are the next run's.
      expect(bannerCandidates(notes.values.toList()).map((n) => n.id), unorderedEquals(['n0', 'n1']));
    });

    group('on the app\'s record of running work (docs/ACTIVITY.md)', () {
      late Activity record;
      setUp(() => useActivity(record = Activity(store: () => MemoryStored())));
      tearDown(() => useActivity(Activity()));

      test('one job for the run: begun, how far, the credits it should cost and has spent, one chip as it ends', () async {
        five();
        final running = job.start();
        await pumpEvents();
        final begun = record[bannerJobId]!;
        expect((begun.kind, begun.title, begun.personStarted, begun.estimate!.credits), (JobKind.images, 'Making header images', true, 30));
        expect(begun.liveLine, 'Making header images, 0 of 5');
        gated.openOne();
        await pumpEvents();
        expect(record[bannerJobId]!.fraction, closeTo(1 / 5, 1e-9));
        expect(record[bannerJobId]!.spent, lovartCreditsPerImage);
        final ended = <Job>[];
        final hearing = record.events.where((e) => e.kind == JobEventKind.ended).listen((e) => ended.add(e.job!));
        gated.openAll();
        await running;
        await hearing.cancel();
        expect(record.value, isEmpty);
        expect(ended.single.result!.words, 'Header images made for 5 notes · about 30 credits');
        expect(record.log.today.words, '5 banners');
      });

      test('the tray\'s Stop is the same Stop, and a stopped run goes quietly', () async {
        five();
        final running = job.start();
        await pumpEvents();
        record[bannerJobId]!.onStop!();
        gated.openAll();
        await running;
        expect(lovartBannerRun.value!.asked, isTrue);
        expect(record.value, isEmpty, reason: 'no failure for a Stop');
        expect(record.log.today.words, '3 banners');
      });

      test('credits spent: a red row with Lovart\'s words and Top up', () async {
        five();
        gated
          ..open = true
          ..fails = const LovartFailure('Your Lovart credits have run out.', code: 2012);
        await job.start();
        final failed = record[bannerJobId]!;
        expect(failed.state, JobState.failed);
        expect(failed.cause, contains('credits'));
        expect(failed.fix!.kind, JobFixKind.topUp);
        expect(record.needsYou, isTrue);
      });

      test('picked up at launch, it is the app\'s own: no chime', () async {
        five();
        unawaited(job.start());
        await pumpEvents();
        lovartBannerMaking.value = const {};
        record.clear();
        final fresh = GatedClient()..open = true;
        lovartClient = () => fresh;
        await made().resume();
        expect(record.log.today.words, isNotEmpty);
        expect(record.lastEnded!.personStarted, isFalse);
      });
    });

    test('the phone\'s Stop is the same Stop', () async {
      five();
      final running = job.start();
      await pumpEvents();
      jobs.stopFromNotification(bannerJobId);
      gated.openAll();
      await running;
      expect(lovartBannerRun.value!.asked, isTrue);
      expect(lovartBannerRun.value!.made, 3);
    });

    test('is kept as it goes, and goes on after a restart from where it was', () async {
      five();
      unawaited(job.start());
      await pumpEvents();
      gated.openOne();
      await pumpEvents();
      // One made, three being made, one waiting: as the app is killed.
      final kept = keptBannerQueue()!;
      expect((kept.total, kept.made, kept.left.length, kept.going.length), (5, 1, 4, 3));
      final done = notes.values.where((n) => bannerOf(n.body) != null).single.id;
      expect(kept.left, isNot(contains(done)));
      // A new process: nothing being made, the old run gone with it, a new job made at launch.
      lovartBannerMaking.value = const {};
      lovartBannerRun.value = null;
      final fresh = GatedClient()..open = true;
      lovartClient = () => fresh;
      final again = made();
      await again.resume();
      expect(fresh.asked, hasLength(4), reason: 'the three that were being made and the one left; not the one done');
      final run = lovartBannerRun.value!;
      expect((run.total, run.done, run.made, run.running), (5, 5, 5, false));
      expect([for (final n in notes.values) bannerOf(n.body) != null], everyElement(isTrue));
      expect(keptBannerQueue(), isNull);
    });

    test('a kept run waits for Lovart\'s keys before it goes on', () async {
      five();
      lovart.host.storage.set(bannerRunKey, const BannerQueue(total: 5, left: ['n3', 'n4'], made: 3).toJson());
      await lovart.host.secrets.write(accessKeySecret, null);
      gated.open = true;
      await job.resume();
      expect(gated.asked, isEmpty);
      expect(keptBannerQueue(), isNotNull, reason: 'kept until it can go on');
      await keys();
      for (var i = 0; i < 10 && lovartBannerRun.value?.running != false; i += 1) {
        await pumpEvents();
      }
      expect(gated.asked, hasLength(2));
      expect((lovartBannerRun.value!.made, lovartBannerRun.value!.total), (5, 5));
    });

    test('credits spent stop it, and say why, on the line and the phone', () async {
      five();
      gated.open = true;
      gated.fails = const LovartFailure('Your Lovart credits have run out.');
      await job.start();
      final run = lovartBannerRun.value!;
      expect((run.running, run.made, run.done, run.asked), (false, 0, 0, false));
      expect(run.stopped, 'Your Lovart credits have run out.');
      expect(bannerRunEndWords(run), 'Header images stopped at 0 of 5: Your Lovart credits have run out.');
      expect(jobs.ends.single, contains('credits'));
      expect(gated.asked.length, lessThanOrEqualTo(3));
      // Nothing was given one: every note is the next run's.
      expect(bannerCandidates(notes.values.toList()), hasLength(5));
    });

    test('runs once at a time on this device', () async {
      five();
      final first = job.start();
      await pumpEvents();
      await job.start();
      await runBanners();
      gated.openAll();
      await first;
      expect(gated.asked, hasLength(5), reason: 'each note asked once');
      expect(lovartBannerRun.value!.made, 5);
    });

    group('made again, on purpose', () {
      setUp(() => gated.open = true);

      test('a note whose banner was taken off is asked again only where the run says so, never by leaving it', () async {
        five();
        // n4 had one, and it was taken off.
        lovart.host.storage.set(bannersDoneKey, ['n4']);
        await job.start();
        expect(bannerOf(notes['n4']!.body), isNull, reason: 'not by Make them alone');
        expect(lovartBannerRun.value!.made, 4);
        expect(await banners.noteLeft('n4'), isFalse, reason: 'nor by leaving it');
        expect(await job.start(takenOff: true), isNull);
        expect(bannerOf(notes['n4']!.body), isNotNull);
        expect((lovartBannerRun.value!.made, lovartBannerRun.value!.total), (1, 1));
        expect(bannersGiven(), contains('n4'));
      });

      test('black-and-white banners are made again in colour and put in their place; colour ones and changed ones stand', () async {
        dated('bw', withBanner('# Black and white\n\n$_words', 'lovart-old-bw.png'), 3);
        dated('colour', withBanner('# Colour\n\n$_words', 'lovart-colour.png'), 2);
        dated('plain', '# Plain\n\n$_words', 1);
        lovart.host.storage.set(bannersDoneKey, ['bw', 'colour']);
        final read = <String>[];
        lovartBannerJob = job = BannerJob(
          notes: () => notes.values.toList(),
          banners: banners,
          background: jobs,
          redo: (name) async {
            read.add(name);
            return name.startsWith('lovart-old-');
          },
        );
        // Without the choice, the pictures are not even read.
        await job.start();
        expect(read, isEmpty);
        expect(bannerOf(notes['bw']!.body), 'lovart-old-bw.png');
        expect(bannerOf(notes['plain']!.body), isNotNull);
        await job.start(redoOld: true);
        expect(read, unorderedEquals(['lovart-old-bw.png', 'lovart-colour.png', bannerOf(notes['plain']!.body)]));
        final redone = bannerOf(notes['bw']!.body)!;
        expect(redone, isNot('lovart-old-bw.png'));
        expect(pictures.kept, contains(redone));
        expect(notes['bw']!.body, withBanner('# Black and white\n\n$_words', redone));
        expect(bannerOf(notes['colour']!.body), 'lovart-colour.png');
        expect((lovartBannerRun.value!.made, lovartBannerRun.value!.total), (1, 1));
        // One given another banner while Lovart worked keeps it.
        notes['bw'] = notes['bw']!.copyWith(body: withBanner(notes['bw']!.body, 'lovart-old-bw2.png'));
        gated.onAsk = () => notes['bw'] = notes['bw']!.copyWith(body: withBanner(notes['bw']!.body, 'mine.png'), revision: notes['bw']!.revision + 1);
        await job.start(redoOld: true);
        expect(bannerOf(notes['bw']!.body), 'mine.png');
        expect(lovartBannerRun.value!.made, 0);
      });

      test('what each note was asked for is kept with the run, and a restart asks it the same', () async {
        dated('bw', withBanner('# Black and white\n\n$_words', 'lovart-old-bw.png'), 2);
        dated('off', '# Taken off\n\n$_words', 1);
        lovart.host.storage.set(bannersDoneKey, ['bw', 'off']);
        lovart.host.storage.set(
          bannerRunKey,
          const BannerQueue(total: 2, left: ['bw', 'off'], going: ['bw', 'off'], again: ['off'], replacing: {'bw': 'lovart-old-bw.png'}).toJson(),
        );
        await job.resume();
        expect(bannerOf(notes['bw']!.body), isNot('lovart-old-bw.png'));
        expect(bannerOf(notes['off']!.body), isNotNull);
        expect(lovartBannerRun.value!.made, 2);
        expect(bannersGiven(), containsAll(['bw', 'off']), reason: 'asked again on purpose, still given for leaving them');
      });

      testWidgets('the page\'s two choices go with Make them', (tester) async {
        five();
        lovart.host.storage.set(bannersDoneKey, ['n4']);
        await pumpPane(tester, const LovartPane());
        final takenOff = find.byKey(const ValueKey('lovart-banner-taken-off'));
        await tester.ensureVisible(takenOff);
        expect(find.byKey(const ValueKey('lovart-banner-redo')), findsOneWidget);
        await tester.tap(find.descendant(of: takenOff, matching: find.byType(GlacierSwitch)));
        await tester.pump();
        final row = find.byKey(const ValueKey('lovart-banner-run'));
        await tester.ensureVisible(row);
        await tester.tap(find.descendant(of: row, matching: find.text('Make them')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('cost-ask-start')));
        await tester.pump();
        for (var i = 0; i < 20 && job.running; i += 1) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(bannerOf(notes['n4']!.body), isNotNull);
        expect(lovartBannerRun.value!.made, 5);
        await away(tester);
      });
    });

    group('across the account\'s devices', () {
      late Preferences prefs;
      late Map<String, Object?> account;
      var at = 1000000;
      const mac = SummaryDevice(id: 'mac-1', name: 'Mac');
      const phone = SummaryDevice(id: 'phone-1', name: 'phone');

      BannerClaims on(SummaryDevice device) => BannerClaims(
            device: () => device,
            preferences: () => prefs,
            setPreferences: (change) => prefs = change(prefs),
            // The account takes this device's claim, as a sync with nothing in between does.
            syncNow: () async => account = {...account, bannerClaimKey: prefs.more[bannerClaimKey]},
            accountHeld: () => account,
            clock: () => at,
          );

      setUp(() {
        prefs = Preferences.defaults;
        account = {};
        at = 1000000;
      });

      test('a run claimed by another device is not made here too', () async {
        five();
        gated.open = true;
        // The Mac claimed it, and its claim reached this phone.
        prefs = prefs.copyWith(more: {...prefs.more, bannerClaimKey: const BannerClaim(by: 'mac-1', name: 'Mac', at: 1000000 - 60000, done: 12, total: 100).toJson()});
        account = {bannerClaimKey: prefs.more[bannerClaimKey]};
        lovartBannerJob = job = made(claims: on(phone));
        expect(await job.start(), 'Header images are being made on your Mac · 12 of 100.');
        expect(gated.asked, isEmpty);
        expect(job.elsewhere()!.name, 'Mac');
        // On the app's record of running work: the Mac's job, as far as it said (docs/ACTIVITY.md, Other devices).
        final record = Activity(store: () => MemoryStored());
        useActivity(record);
        addTearDown(() => useActivity(Activity()));
        job.tellElsewhere();
        final theirs = record.value.single;
        expect((theirs.here, theirs.deviceWords, theirs.liveLine, theirs.fraction), (false, 'on your Mac', 'Making header images, 12 of 100', 0.12));
        // Once its claim has run out (the Mac went mid-run), this device may.
        at += bannerClaimMs;
        expect(job.elsewhere(), isNull);
        job.tellElsewhere();
        expect(record.value, isEmpty);
        expect(await job.start(), isNull);
        expect(gated.asked, hasLength(5));
      });

      test('the claim is this device\'s while it runs, renewed with how far it is, and let go as it ends', () async {
        five();
        lovartBannerJob = job = made(claims: on(mac));
        final running = job.start();
        await pumpEvents();
        expect(bannerClaimOf(prefs)!.by, 'mac-1');
        expect(BannerClaim.fromJson(account[bannerClaimKey])!.by, 'mac-1', reason: 'the account holds it before Lovart is asked');
        at += bannerRenewMs;
        gated.openOne();
        await pumpEvents();
        expect((bannerClaimOf(prefs)!.done, bannerClaimOf(prefs)!.at), (1, at));
        gated.openAll();
        await running;
        expect(bannerClaimOf(prefs), isNull);
      });

      test('of two devices that claim at once, the account\'s first claim stands in the merge', () {
        final macClaim = const BannerClaim(by: 'mac-1', name: 'Mac', at: 1000000).toJson();
        final phoneClaim = const BannerClaim(by: 'phone-1', name: 'phone', at: 1000001).toJson();
        // The phone's write was refused; it reads the account's (the Mac's) and merges its own over it.
        final out = merged(const {}, {bannerClaimKey: phoneClaim}, {bannerClaimKey: macClaim}, now: 1000002);
        expect(BannerClaim.fromJson(out[bannerClaimKey])!.by, 'mac-1');
        // A claim run out is no claim: the phone's stands.
        final later = merged(const {}, {bannerClaimKey: phoneClaim}, {bannerClaimKey: macClaim}, now: 1000000 + bannerClaimMs);
        expect(BannerClaim.fromJson(later[bannerClaimKey])!.by, 'phone-1');
      });
    });
  });

  group('credits, estimated', () {
    test('about six an image, in one place, always said as about', () {
      expect(lovartCreditsPerImage, 6);
      expect(aboutCredits(1), 'about 6 credits');
      expect(aboutCredits(24), 'about 144 credits');
      expect(bannerRunLine(const BannerRun(total: 100, done: 12, made: 12)), 'Making header images · 12 of 100 · about 72 credits');
      expect(bannerRunLine(const BannerRun(total: 100)), 'Making header images · 0 of 100');
      expect(bannerRunEndWords(const BannerRun(total: 100, done: 100, made: 97, running: false)), 'Header images made for 97 notes · 3 skipped · about 582 credits');
    });

    test('the note\'s own Header image says it', () {
      final row = lovartPlugin.noteActions.singleWhere((action) => action.id == 'lovart-banner');
      return keys().then((_) => expect(row.hint('n', '# Trip'), endsWith('with your credits: about 6 credits.')));
    });

    testWidgets('Make them says what the run would cost before it starts', (tester) async {
      await keys();
      for (var i = 0; i < 4; i += 1) {
        notes['n$i'] = Note(id: 'n$i', body: '# Note $i\n\n$_words', createdAt: 0, updatedAt: i);
      }
      notes['off'] = Note(id: 'off', body: '# Taken off\n\n$_words', createdAt: 0, updatedAt: 9);
      lovart.host.storage.set(bannersDoneKey, ['off']);
      lovartBannerRun.value = null;
      lovartBannerJob = BannerJob(notes: () => notes.values.toList(), banners: banners);
      await pumpPane(tester, const LovartPane());
      expect(find.textContaining('About 24 credits for 4 notes.'), findsOneWidget);
      final takenOff = find.byKey(const ValueKey('lovart-banner-taken-off'));
      await tester.ensureVisible(takenOff);
      await tester.tap(find.descendant(of: takenOff, matching: find.byType(GlacierSwitch)));
      await tester.pump();
      expect(find.textContaining('About 30 credits for 5 notes.'), findsOneWidget);
      await away(tester);
      lovartBannerJob = null;
    });
  });

  group('redo', () {
    test('black and white, or square, is made again; wide and in colour is not', () {
      expect(bannerToRedo(colour: false, aspect: 16 / 9), isTrue);
      expect(bannerToRedo(colour: true, aspect: 1), isTrue, reason: 'Lovart\'s first ones, 1254×1254');
      expect(bannerToRedo(colour: true, aspect: 16 / 9), isFalse);
      expect(bannerToRedo(colour: true, aspect: 2.5), isFalse);
    });
  });

  group('header images for every page of a notebook', () {
    late GatedClient gated;

    Note page(String id, String title, {String? banner, String? path, String body = _words}) {
      final text = '# $title\n\n$body';
      return notes[id] = Note(id: id, body: banner == null ? text : withBanner(text, banner), createdAt: 0, updatedAt: 0, path: path);
    }

    setUp(() async {
      await keys();
      gated = GatedClient()..open = true;
      lovartClient = () => gated;
      lovartBannerRun.value = null;
      lovartBannerMaking.value = const {};
      lovartBannerJob = BannerJob(notes: () => notes.values.toList(), banners: banners, redo: (name) async => name.startsWith('lovart-old-'));
    });
    tearDown(() => lovartBannerJob = null);

    /// "Ghost.md Docs", the Ghost.md organization's notebook (Matt's case, 33 chapters), as invented pages: a team's
    /// notebook in its organization's folder, a section indented under a chapter, a nested notebook, a ticket, a
    /// short page, one with a banner in colour, one in black and white, one taken off before (marked given), and a
    /// page of the same title in the account's own notes, which is not the team's.
    Note docs() {
      const org = 'orgs/ghost';
      for (var i = 1; i <= 26; i += 1) {
        page('d$i', 'Chapter $i', path: '$org/Docs/Chapter $i.md');
      }
      page('mine', 'Chapter 1', path: 'Inbox/Chapter 1.md');
      page('section', 'Install on a phone', path: '$org/Docs/Install on a phone.md');
      page('ticket', 'Fix the docs', path: '$org/Docs/Fix the docs.md', body: '---\ntype: ticket\n---\n$_words');
      notes['ticket'] = notes['ticket']!.copyWith(body: '---\ntype: ticket\n---\n# Fix the docs\n\n$_words');
      page('short', 'Glossary', path: '$org/Docs/Glossary.md', body: 'Words.');
      page('colour', 'Colour', banner: 'lovart-new.png', path: '$org/Docs/Colour.md');
      page('bw', 'Black and white', banner: 'lovart-old-bw.png', path: '$org/Docs/Black and white.md');
      page('off', 'Taken off', path: '$org/Docs/Taken off.md');
      notes['inner'] = Note(id: 'inner', body: bookNoteBody('Appendix', ['Appendix page']), createdAt: 0, updatedAt: 0, path: '$org/Docs/Appendix.md');
      page('appendix-page', 'Appendix page', path: '$org/Docs/Appendix page.md');
      lovart.host.storage.set(bannersDoneKey, ['off', 'colour', 'bw']);
      final index = [
        for (var i = 1; i <= 26; i += 1) '$i. [[Chapter $i]]',
        '   - [[Install on a phone]]',
        '27. [[Fix the docs]]',
        '28. [[Glossary]]',
        '29. [[Colour]]',
        '30. [[Black and white]]',
        '31. [[Taken off]]',
        '32. [[Appendix]]',
        '33. [[Not written yet]]',
      ].join('\n');
      return notes['book'] = Note(id: 'book', body: '---\ntitle: "Ghost.md Docs"\nbook: true\n---\n# Ghost.md Docs\n\n$index\n', createdAt: 0, updatedAt: 0, path: '$org/Docs/Ghost.md Docs.md');
    }

    test('its pages, in order, the team\'s own, with a section and a nested notebook\'s', () {
      final book = docs();
      final pages = bookPages(book, notes.values.toList()).map((n) => n.id).toList();
      expect(pages.first, 'd1', reason: 'the team\'s Chapter 1, not the account\'s');
      expect(pages, isNot(contains('mine')));
      expect(pages.indexOf('section'), pages.indexOf('d26') + 1);
      expect(pages, containsAllInOrder(['ticket', 'short', 'colour', 'bw', 'off', 'appendix-page']));
      expect(pages, isNot(contains('book')));
      expect(pages, isNot(contains('inner')), reason: 'a notebook that is a chapter gives its pages, not itself');
    });

    test('asks for every page that is one to have one, marks aside; black-and-white made again; Redo existing, all', () async {
      final book = docs();
      final asks = await bookBannerAsks(book, notes.values.toList(), redo: lovartBannerJob!.redo);
      final ids = asks.map((a) => a.id).toList();
      expect(ids, hasLength(2 + 26 + 1 + 1 + 1 + 1), reason: 'the notebook\'s index and the appendix\'s, 26 chapters, the section, the one taken off, the black-and-white one, the appendix\'s page');
      expect(ids.take(2), ['book', 'inner'], reason: 'the notebook\'s own index first, its cover, then a nested notebook\'s');
      expect(ids, isNot(anyOf(contains('ticket'), contains('short'), contains('colour'))));
      expect(asks.firstWhere((a) => a.id == 'off'), (id: 'off', again: true, replacing: null));
      expect(asks.firstWhere((a) => a.id == 'bw'), (id: 'bw', again: true, replacing: 'lovart-old-bw.png'));
      final all = await bookBannerAsks(book, notes.values.toList(), redoAll: true);
      expect(all.firstWhere((a) => a.id == 'colour').replacing, 'lovart-new.png');
      expect(all, hasLength(33));
    });

    test('says the count and about the credits before it starts, and Not now makes nothing', () {
      docs();
      final choices = bookBannerChoices('book');
      expect(choices.map((c) => c.id), ['missing', 'all', 'not-now']);
      expect(choices[0].label, 'Make header images for 31 pages?');
      expect(choices[0].hint, startsWith('About 186 credits. Of the 2 pages with one, any in black and white or square is made again too'));
      expect(choices[1].label, 'Redo existing too: 33 pages?');
      expect(choices[1].hint, startsWith('About 198 credits.'));
      final action = lovartPlugin.noteActions.singleWhere((a) => a.id == 'lovart-book-banners');
      expect(action.label, 'Header images for every page');
      expect(action.visible('book', notes['book']!.body), isTrue);
      expect(action.visible('d1', notes['d1']!.body), isFalse);
    });

    test('runs as the app\'s job over the pages, writing each through the same writer, and Not now runs nothing', () async {
      final book = docs();
      final action = lovartPlugin.noteActions.singleWhere((a) => a.id == 'lovart-book-banners');
      final open = TestNote(book.body, noteId: 'book');
      await action.run(open, 'not-now');
      expect(gated.asked, isEmpty);
      await action.run(open, 'missing');
      expect(open.said.first, 'Making header images for 32 pages.');
      final run = lovartBannerRun.value!;
      expect((run.total, run.made, run.running), (32, 32, false));
      for (final id in ['book', 'inner', 'd1', 'd26', 'section', 'off', 'appendix-page']) {
        expect(bannerOf(notes[id]!.body), isNotNull, reason: id);
      }
      expect(bannerOf(notes['bw']!.body), isNot('lovart-old-bw.png'));
      expect(bannerOf(notes['colour']!.body), 'lovart-new.png');
      expect(bannerOf(notes['ticket']!.body), isNull);
      expect(bannerOf(notes['mine']!.body), isNull, reason: 'the account\'s own Chapter 1 is not the team\'s page');
      expect(notes.containsKey('book'), isTrue, reason: 'nothing is deleted');
      expect(notes['book']!.body, contains('book: true'), reason: 'the index is still a notebook, its banner beside');
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

/// Every microtask and zero-length wait run, as a few awaits in a row let the run take its next step.
Future<void> pumpEvents() async {
  for (var i = 0; i < 20; i += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Lovart, held: each prompt waits until it is let through, one at a time or all at once.
class GatedClient extends FakeClient {
  final List<Completer<void>> _held = [];

  /// Every prompt answered at once, from now on.
  bool open = false;

  /// How many wait now.
  int get waiting => _held.where((gate) => !gate.isCompleted).length;

  void openOne() => _held.firstWhere((gate) => !gate.isCompleted).complete();

  void openAll() {
    open = true;
    for (final gate in _held) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  @override
  Future<List<Uint8List>> generate(String prompt, {Duration timeout = lovartTimeout}) async {
    if (!open) {
      final gate = Completer<void>();
      _held.add(gate);
      await gate.future;
    }
    return super.generate(prompt, timeout: timeout);
  }
}

/// The phone's half, heard.
class FakeJobs implements BackgroundJobs {
  final List<({String title, String text, int? done, int? total})> said = [];
  final List<String> ends = [];
  void Function(String id)? _stop;


  void stopFromNotification(String id) => _stop?.call(id);

  @override
  Future<void> running(String id, {required String title, required String text, int? done, int? total}) async => said.add((title: title, text: text, done: done, total: total));

  @override
  Future<void> ended(String id, {required String title, String? text, bool quiet = false}) async => ends.add(title);

  @override
  void onStop(void Function(String id)? stop) => _stop = stop;
}
