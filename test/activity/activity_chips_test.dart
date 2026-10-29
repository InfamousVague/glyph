// The result chips, the cost ask and the chime (lib/activity/activity_chips.dart, activity_cost.dart,
// activity_chime.dart; docs/ACTIVITY.md, Results, Cost, Sound).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/activity/activity_chime.dart';
import 'package:ghost_md/activity/activity_chips.dart';
import 'package:ghost_md/activity/activity_cost.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/placeholders.dart';
import 'package:ghost_md/sounds/sound_pack.dart';

import '../notes/bar_support.dart';
import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  late DateTime now;
  late Activity record;
  setUp(() {
    now = DateTime(2026, 10, 29, 10);
    record = Activity(clock: () => now, store: () => MemoryStored());
    useActivity(record);
  });
  tearDown(() => useActivity(Activity()));

  void shotTest(String description, Future<void> Function(WidgetTester tester) body) => testWidgets(description, (tester) async {
        await body(tester);
        debugDisableShadows = true;
      });

  const phone = Size(390, 844);
  const mac = Size(1280, 800);

  Future<void> pumpShell(WidgetTester tester, {Size size = phone, bool mobile = true, Widget Function(BuildContext context)? home}) async {
    final sheet = await appSheet(tester);
    await pumpApp(
      tester,
      size: size,
      home: AppShell(
        sheet: sheet,
        notes: library,
        workspaces: spaces,
        mobile: mobile,
        finePointer: !mobile,
        onDeleteNote: (_) {},
        homeBuilder: (context, shell) => home?.call(context) ?? HomePlaceholder(notes: shell.notes, onOpen: shell.openNote, onAllNotes: shell.showAllNotes),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder chips() => find.byType(ChipFace);

  /// Past the chip's slide and the sheet's rise: the first frame only starts their clocks.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i += 1) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  group('chips', () {
    for (final (name, size, mobile) in [('phone', phone, true), ('mac', mac, false)]) {
      shotTest('a job that ends with a result while you are elsewhere gives a chip, and View opens it ($name)', (tester) async {
        await pumpShell(tester, size: size, mobile: mobile);
        var opened = 0;
        record.begin('banner:n1', kind: JobKind.images, title: 'Header image for Plan').done(result: JobResult('Banner ready', onOpen: () => opened += 1));
        await settle(tester);
        expect(chips(), findsOneWidget);
        expect(find.text('Banner ready'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('activity-chip:action:banner:n1')));
        await tester.pump(const Duration(milliseconds: 100));
        expect(opened, 1);
        expect(chips(), findsNothing, reason: 'gone as it is acted on');
      });
    }

    shotTest('none while you are looking at it, none without a result, none for another device', (tester) async {
      await pumpShell(tester);
      record.begin('a', kind: JobKind.images, title: 'A', shownHere: () => true).done(result: const JobResult('Banner ready'));
      record.begin('b', kind: JobKind.sync, title: 'Syncing').done(tally: const JobTally('note synced', 'notes synced', 3));
      record.begin('c', kind: JobKind.images, title: 'C').done(result: const JobResult('Quiet'), quiet: true);
      await settle(tester);
      expect(chips(), findsNothing);
    });

    shotTest('a batch gives one chip', (tester) async {
      await pumpShell(tester);
      final run = record.begin('lovart-banners', kind: JobKind.images, title: 'Making header images', personStarted: true);
      for (var i = 1; i <= 12; i += 1) {
        run.progress(done: i, total: 12);
      }
      run.done(result: const JobResult('12 header images made'), tally: const JobTally('banner', 'banners', 12));
      await settle(tester);
      expect(chips(), findsOneWidget);
    });

    shotTest('at most two stack, the newest on top; a swipe puts one away; each goes on its own', (tester) async {
      await pumpShell(tester);
      for (final id in ['one', 'two', 'three']) {
        record.begin(id, kind: JobKind.ai, title: id).done(result: JobResult('$id ready'));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle(tester);
      expect(chips(), findsNWidgets(2));
      expect(find.text('one ready'), findsNothing);
      expect(tester.getRect(find.text('three ready')).top, lessThan(tester.getRect(find.text('two ready')).top));
      await tester.drag(find.text('three ready'), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(chips(), findsOneWidget);
      await tester.pump(chipFor);
      await tester.pumpAndSettle();
      expect(chips(), findsNothing);
    });

    for (final (name, size, mobile) in [('phone', phone, true), ('mac', mac, false)]) {
      shotTest('two stack cleanly: one width, one end edge, one over the other with a gap, actions in line ($name)', (tester) async {
        await pumpShell(tester, size: size, mobile: mobile);
        record.begin('banner:n9', kind: JobKind.images, title: 'Header image for Trip notes').done(result: JobResult('Banner ready', onOpen: () {}));
        record.begin('summary:n8', kind: JobKind.ai, title: 'Summary of Standup').done(result: JobResult('Summarized “Standup”', action: 'Open', onOpen: () {}));
        await settle(tester);
        final faces = tester.widgetList<ChipFace>(chips()).toList();
        expect(faces, hasLength(2));
        final top = tester.getRect(chips().first), under = tester.getRect(chips().last);
        expect(top.right, closeTo(under.right, 0.01), reason: 'the same end edge');
        expect(top.width, closeTo(under.width, 0.01), reason: 'as wide as the wider');
        expect(under.top - top.bottom, greaterThanOrEqualTo(6), reason: 'a gap, never overlapping');
        expect(tester.getRect(find.byKey(const ValueKey('activity-chip:close:banner:n9'))).right, closeTo(tester.getRect(find.byKey(const ValueKey('activity-chip:close:summary:n8'))).right, 0.01), reason: 'the crosses in line');
      });
    }

    shotTest('one alone is as wide as its words', (tester) async {
      await pumpShell(tester);
      record.begin('banner:n9', kind: JobKind.images, title: 'Header image for Trip notes').done(result: JobResult('Banner ready', onOpen: () {}));
      await settle(tester);
      final alone = tester.getRect(chips());
      record.begin('summary:n8', kind: JobKind.ai, title: 'Summary of Standup').done(result: JobResult('Summarized “Standup” and its three to-dos', action: 'Open', onOpen: () {}));
      await settle(tester);
      expect(tester.getRect(chips().last).width, greaterThan(alone.width), reason: 'stacked with a wider one, it takes its width');
    });

    shotTest('a failure says its cause, red, with its fix', (tester) async {
      await pumpShell(tester);
      var fixed = 0;
      record.begin('voice', kind: JobKind.audio, title: 'Reading aloud').failed('ElevenLabs is out of credits', fix: JobFix(JobFixKind.topUp, () => fixed += 1));
      await settle(tester);
      expect(find.text('ElevenLabs is out of credits'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('activity-chip:action:voice')));
      expect(fixed, 1);
    });

    for (final (name, size, mobile) in [('phone', phone, true), ('mac', mac, false)]) {
      shotTest('never over the dock nor the keyboard ($name)', (tester) async {
        // Where the page's dock stands (lib/shell/page_dock.dart `PageDockFrame`): a column of rings at the foot's end.
        await pumpShell(tester, size: size, mobile: mobile, home: (context) => const Stack(children: [Positioned(right: 16, bottom: 36, child: SizedBox(key: ValueKey('dock'), width: 56, height: 220))]));
        tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 2);
        addTearDown(tester.view.resetViewInsets);
        record.begin('a', kind: JobKind.ai, title: 'A').done(result: const JobResult('Summary ready'));
        record.begin('b', kind: JobKind.images, title: 'B').done(result: const JobResult('Banner ready'));
        await settle(tester);
        expect(chips(), findsNWidgets(2));
        final keyboardTop = size.height - 300;
        for (final chip in tester.widgetList(chips()).toList().asMap().keys) {
          final rect = tester.getRect(chips().at(chip));
          expect(rect.bottom, lessThan(keyboardTop), reason: 'over the keyboard: $rect');
          final dock = find.byKey(const ValueKey('dock'));
          if (dock.evaluate().isNotEmpty) expect(rect.overlaps(tester.getRect(dock)), isFalse, reason: 'over the dock: $rect');
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.top, greaterThan(36), reason: 'under the notch and the header');
        }
      });
    }
  });

  group('the cost ask', () {
    Future<BuildContext> host(WidgetTester tester, {Size size = phone}) async {
      late BuildContext context;
      await pumpApp(tester, size: size, home: Builder(builder: (c) {
        context = c;
        return const SizedBox.expand();
      }));
      return context;
    }

    shotTest('a small job just runs: nothing asked', (tester) async {
      final context = await host(tester);
      final answer = askJobCost(context, const JobEstimate(credits: 18, provider: 'Lovart', count: 3, one: 'banner'), title: 'Make header images?');
      await tester.pump();
      expect(find.byKey(const ValueKey('cost-ask')), findsNothing);
      expect(await answer, isTrue);
    });

    for (final (name, size) in [('phone', phone), ('mac', mac)]) {
      shotTest('over 20 credits it asks, Start starts ($name)', (tester) async {
        final context = await host(tester, size: size);
        final answer = askJobCost(context, const JobEstimate(credits: 72, provider: 'Lovart', duration: Duration(minutes: 4), count: 12, one: 'banner', many: 'banners'), title: 'Make header images?');
        await settle(tester);
        expect(find.byKey(const ValueKey('cost-ask')), findsOneWidget);
        expect(find.text('12 banners · ~72 Lovart credits · ~4 min'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('cost-ask-start')));
        await settle(tester);
        expect(await answer, isTrue);
        expect(find.byKey(const ValueKey('cost-ask')), findsNothing);
      });
    }

    shotTest('over 2 minutes it asks, Cancel starts nothing', (tester) async {
      final context = await host(tester);
      final answer = askJobCost(context, const JobEstimate(duration: Duration(minutes: 3)), title: 'Write it up?');
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('cost-ask-cancel')));
      await settle(tester);
      expect(await answer, isFalse);
    });
  });

  group('the chime', () {
    late PreferencesStore prefs;
    late List<String> heard;
    setUp(() {
      prefs = PreferencesStore()..startWithoutStorage();
      heard = [];
      startActivityChime(record: record, prefs: prefs, play: (event) => heard.add(event.id), tap: () => heard.add('tap'));
    });

    test('a long job the person started: a chime and a tap', () {
      record.begin('run', kind: JobKind.images, title: 'Run', personStarted: true);
      now = now.add(const Duration(seconds: 45));
      record.handle('run')!.done();
      expect(heard, ['job-done', 'tap']);
    });

    test('nothing for a short one, one it started itself, nor sync', () {
      record.begin('short', kind: JobKind.images, title: 'Short', personStarted: true);
      now = now.add(const Duration(seconds: 5));
      record.handle('short')!.done();
      record.begin('own', kind: JobKind.images, title: 'Own');
      now = now.add(const Duration(minutes: 5));
      record.handle('own')!.done();
      record.begin('sync', kind: JobKind.sync, title: 'Syncing', personStarted: true);
      now = now.add(const Duration(minutes: 5));
      record.handle('sync')!.done();
      expect(heard, isEmpty);
    });

    test('off with the app\'s sounds', () {
      prefs.value = prefs.value.copyWith(interfaceSounds: false);
      record.begin('run', kind: JobKind.images, title: 'Run', personStarted: true);
      now = now.add(const Duration(minutes: 1));
      record.handle('run')!.done();
      expect(heard, isEmpty);
    });

    test('the pack has the chime', () {
      expect(soundPackOf('ghostly').asset(SoundEvent.jobDone, apple: false), 'assets/sounds/ghostly/job-done.ogg');
    });
  });
}
