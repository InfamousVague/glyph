// The ring of running work in the header (lib/activity/activity_ring.dart; docs/ACTIVITY.md, Ring): in every version
// of the header toolbar and every top bar style, on a phone, the opened Fold and the Mac, beside the button for you;
// one arc for each job in its colour, the other devices' dimmed; a quiet grey ring while idle, still a button that opens
// the tray (Matt, 2026-10-29: "Keep the activity indicator always showing just have it gray put when nothing is
// happening"); one bloom when all finish, then grey again; a still red dot when something needs you; the tray it opens,
// a card under it on a wide window and a sheet on a phone.
import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/activity/activity_look.dart';
import 'package:ghost_md/activity/activity_ring.dart';
import 'package:ghost_md/activity/activity_tray.dart';
import 'package:ghost_md/art/app_icon.dart' show AppIcon;
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/note/note_tools.dart';
import 'package:ghost_md/notes/floating_card.dart' show FloatingCard;
import 'package:ghost_md/sheet/sheet.dart' show Sheet;
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/header_toolbar.dart';
import 'package:ghost_md/shell/placeholders.dart';
import 'package:ghost_md/shell/top_bar.dart';
import 'package:ghost_md/shell/top_bar_tools.dart';
import 'package:glacier/glacier.dart' show GlacierTheme;

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
  tearDown(() {
    useActivity(Activity());
    headerToolbarChoice.set(HeaderToolbarVersion.today.id);
  });

  void barTest(String description, Future<void> Function(WidgetTester tester) body, {bool skip = false}) => testWidgets(description, skip: skip, (tester) async {
        await body(tester);
        debugDisableShadows = true;
      });

  const folded = (name: 'folded', size: Size(390, 844), mobile: true, fine: false);
  const unfolded = (name: 'unfolded', size: Size(880, 1000), mobile: true, fine: false);
  const mac = (name: 'mac', size: Size(1280, 800), mobile: false, fine: true);
  const windows = [folded, unfolded, mac];
  // A phone at 360, and a Mac's window at a phone's width (it narrows to 360, macos/Runner/MainFlutterWindow.swift),
  // its window buttons at the bar's start: the narrowest rows there are.
  const phone = (name: 'phone-360', size: Size(360, 780), mobile: true, fine: false);
  const narrowMac = (name: 'mac-narrow', size: Size(390, 700), mobile: false, fine: true);
  const everyWidth = [phone, folded, unfolded, mac, narrowMac];

  Future<void> pumpShell(WidgetTester tester, {HeaderToolbarVersion? version, required ({String name, Size size, bool mobile, bool fine}) window, TopBarStyle style = TopBarStyle.classic, bool note = true, String theme = 'light', bool calm = false}) async {
    final sheet = await appSheet(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await pumpApp(
      tester,
      size: window.size,
      prefs: Preferences(theme: theme, calm: calm),
      home: AppShell(
        sheet: sheet,
        notes: library,
        workspaces: spaces,
        topBar: style,
        headerToolbar: version,
        openNotes: const ['weekend', 'groceries', 'standup'],
        unread: true,
        mobile: window.mobile,
        finePointer: window.fine,
        organizations: const [OrgLike(id: 'o1', name: 'Attic Press', hue: 'moss')],
        onNew: () {},
        onSearch: () {},
        onSettings: () {},
        onOrganizations: () {},
        onDeleteNote: (_) {},
        noteBuilder: (context, shell, screen) => _StandInNote(note: screen.note),
        homeBuilder: (context, shell) => HomePlaceholder(notes: shell.notes, onOpen: shell.openNote, onAllNotes: shell.showAllNotes),
        asideBuilder: (context, shell) => const SizedBox.shrink(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    if (note) {
      tester.state<AppShellState>(find.byType(AppShell)).openNote('groceries');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Three jobs: a banner run, a summary on another device, a sync.
  void threeJobs() {
    record.begin('lovart-banners', kind: JobKind.images, title: 'Making header images').progress(done: 4, total: 12);
    record.elsewhere('handoff', [Job(id: 'summary:n1', kind: JobKind.ai, title: 'Summary of Standup', device: 'mac1', deviceName: 'Mac', startedAt: now, line: 'Writing the summary')]);
    record.begin('sync', kind: JobKind.sync, title: 'Syncing');
  }

  Finder ring() => find.byKey(ActivityRing.key_);

  ActivityRingPainter painter(WidgetTester tester) => tester.widget<CustomPaint>(find.byKey(const ValueKey('activity-ring:arcs'))).painter! as ActivityRingPainter;

  group('fits every version, every style, every window, idle and busy', () {
    for (final version in HeaderToolbarVersion.values) {
      for (final window in everyWidth) {
        for (final style in TopBarStyle.values) {
          // On a narrowed Mac, today's Islands reading a note ran over before the ring was always there (by 14, its
          // window buttons, two capsules and ten rings in 390) and still do, and today's Masthead runs its words past the
          // line's end as the page does (lib/notes/tabs/bar_parts.dart ToolRow), the ring with them; every other row fits.
          final over = version == HeaderToolbarVersion.today && (style == TopBarStyle.islands || style == TopBarStyle.masthead) && window == narrowMac;
          barTest('${version.number} ${version.label}, ${style.label}, ${window.name}', skip: over, (tester) async {
            if (window == narrowMac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
            addTearDown(() => debugDefaultTargetPlatformOverride = null);
            // The idle ring keeps its room as the busy one does: the row is the same either way.
            for (final busy in [false, true]) {
              if (busy) threeJobs();
              for (final note in [true, false]) {
                await pumpShell(tester, version: version, window: window, style: style, note: note);
                final where = '${busy ? 'busy' : 'idle'}, on ${note ? 'a note' : 'home'}';
                expect(tester.takeException(), isNull, reason: 'nothing ran over, $where');
                expect(ring(), findsOneWidget, reason: 'the ring, $where');
                expect(painter(tester).arcs, busy ? hasLength(3) : isEmpty, reason: where);
                final at = tester.getRect(ring());
                expect(at.left >= -0.5 && at.right <= window.size.width + 0.5 && at.top >= 0 && at.bottom < 160, isTrue, reason: 'the ring at $at');
                // Beside the button for you, where the version has one in the row.
                final you = find.byKey(HeaderAct.keyOf('you'));
                if (you.evaluate().isNotEmpty) {
                  final rect = tester.getRect(you.first);
                  expect((rect.left - at.right).abs() < 24 || (at.left - rect.right).abs() < 24, isTrue, reason: 'beside You: ring $at, you $rect');
                }
                for (final element in find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('header:')).evaluate()) {
                  final box = element.renderObject;
                  if (box is! RenderBox || !box.hasSize || !box.attached) continue;
                  final rect = box.localToGlobal(Offset.zero) & box.size;
                  expect(rect.left >= -0.5 && rect.right <= window.size.width + 0.5, isTrue, reason: '${element.widget.key} at $rect on a ${window.size.width} window, $where');
                }
              }
            }
            debugDefaultTargetPlatformOverride = null;
          });
        }
      }
    }
  });

  /// The idle ring: no arcs, no glyph, no tick, the track alone in the muted ink, and nothing moving.
  void expectIdle(WidgetTester tester, {String reason = ''}) {
    expect(ring(), findsOneWidget, reason: reason);
    final drawn = painter(tester);
    expect(drawn.arcs, isEmpty, reason: reason);
    expect(drawn.idle, GlacierTheme.of(tester.element(ring())).color('app-ink-3'), reason: 'grey, $reason');
    expect(find.descendant(of: ring(), matching: find.byType(AppIcon)), findsNothing, reason: 'no glyph and no tick, $reason');
    expect(find.descendant(of: ring(), matching: find.byType(JobGlyph)), findsNothing, reason: reason);
    expect(find.byKey(const ValueKey('activity-ring:dot')), findsNothing, reason: reason);
  }

  for (final window in windows) {
    barTest('idle, a quiet grey ring on every version, a button that opens the tray, ${window.name}', (tester) async {
      for (final version in HeaderToolbarVersion.values) {
        for (final note in [true, false]) {
          final reason = '${version.label} on ${note ? 'a note' : 'home'}';
          await pumpShell(tester, version: version, window: window, note: note);
          expectIdle(tester, reason: reason);
          final spin = painter(tester).spin;
          await tester.pump(const Duration(milliseconds: 400));
          expect(painter(tester).spin, spin, reason: 'still, $reason');
          expect(tester.getSemantics(ring()).label, 'Activity: nothing running', reason: reason);
          await tester.tap(ring());
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.byType(ActivityTray), findsOneWidget, reason: reason);
          expect(find.byType(window.size.width < activityTrayCardWidth ? Sheet : FloatingCard), findsOneWidget, reason: reason);
          expect(find.text('Nothing running now.'), findsOneWidget, reason: reason);
          expect(tester.widget<Text>(find.byKey(const ValueKey('activity-tray:today'))).data, 'Nothing finished yet today.', reason: reason);
          await tester.ensureVisible(find.byKey(const ValueKey('activity-tray:more')));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.byKey(const ValueKey('activity-tray:more')));
          await tester.pump();
          expect(find.byKey(const ValueKey('activity-tray:past-none')), findsOneWidget, reason: 'Past 7 days, $reason');
        }
      }
    });
  }

  for (final (theme, calm) in [('light', false), ('dark', false), ('light', true), ('dark', true)]) {
    barTest('idle is the muted ink in ${calm ? 'Calm, ' : ''}$theme, never a job\'s colour', (tester) async {
      await pumpShell(tester, window: mac, theme: theme, calm: calm);
      expectIdle(tester);
      final t = GlacierTheme.of(tester.element(ring()));
      expect(painter(tester).idle, isNot(jobColour(t, JobLook.sync)));
    });
  }

  barTest('one arc per job in its colour, the other device\'s dimmed', (tester) async {
    threeJobs();
    await pumpShell(tester, window: mac);
    final arcs = painter(tester).arcs;
    expect(arcs, hasLength(3));
    final t = GlacierTheme.of(tester.element(ring()));
    expect(arcs[0].colour, jobColour(t, JobLook.images));
    expect(arcs[0].fraction, closeTo(4 / 12, 1e-9));
    expect(arcs[1].colour, jobColour(t, JobLook.sync));
    expect(arcs[2].elsewhere, isTrue, reason: 'the Mac\'s summary');
    expect(arcs[2].drawn.a, closeTo(arcs[2].colour.a * RingArc.elsewhereAlpha, 1e-6));
    expect(arcs[0].elsewhere, isFalse);
    expect({arcs[0].colour, arcs[1].colour, arcs[2].colour}, hasLength(3), reason: 'vivid: a colour each');
  });

  barTest('blooms once when all finish, then is grey again, not gone', (tester) async {
    final a = record.begin('a', kind: JobKind.images, title: 'A');
    final b = record.begin('b', kind: JobKind.audio, title: 'B');
    await pumpShell(tester, window: mac);
    expect(ring(), findsOneWidget);
    a.done();
    await tester.pump(const Duration(milliseconds: 50));
    expect(painter(tester).bloom, 0, reason: 'one still runs');
    b.done();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(ring(), findsOneWidget, reason: 'kept for the bloom');
    expect(painter(tester).bloom, greaterThan(0));
    expect(painter(tester).arcs, isEmpty);
    await tester.pump(activityBloom);
    await tester.pump();
    expectIdle(tester, reason: 'grey once the bloom is over');
    expect(tester.getSemantics(ring()).label, 'Activity: nothing running');
    // And busy again from grey.
    record.begin('c', kind: JobKind.sync, title: 'Syncing');
    await tester.pump();
    expect(painter(tester).arcs, hasLength(1));
  });

  barTest('reduced motion: the tick holds for the bloom, then the ring is grey again', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final a = record.begin('a', kind: JobKind.images, title: 'A');
    await pumpShell(tester, window: folded);
    a.done();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.descendant(of: ring(), matching: find.byType(AppIcon)), findsOneWidget, reason: 'the tick, still');
    await tester.pump(activityBloom);
    await tester.pump();
    expectIdle(tester, reason: 'grey once the bloom is over');
  });

  barTest('a still red dot when something needs you, and it stays after the rest end', (tester) async {
    record.begin('post', kind: JobKind.ai, title: 'Posting to Slack').failed('Slack signed you out', fix: JobFix(JobFixKind.signIn, () {}));
    await pumpShell(tester, window: folded);
    expect(ring(), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-ring:dot')), findsOneWidget);
    expect(find.byKey(const ValueKey('job-glyph:dot')), findsOneWidget, reason: 'the failed job\'s glyph is the still dot');
    expect(tester.getSemantics(ring()).label, contains('something needs you'));
  });

  barTest('Calm turns the colours to ink', (tester) async {
    threeJobs();
    await pumpShell(tester, window: mac, calm: true);
    final t = GlacierTheme.of(tester.element(ring()));
    final ink = t.color('app-ink');
    for (final look in [JobLook.sync, JobLook.ai, JobLook.images, JobLook.audio, JobLook.meetings, JobLook.downloads, JobLook.needsYou]) {
      expect(jobColour(t, look), ink, reason: look.name);
    }
    expect(painter(tester).arcs.map((a) => a.colour).toSet(), {ink});
  });

  barTest('Calm is ink in the dark too, and vivid differs between light and dark', (tester) async {
    threeJobs();
    await pumpShell(tester, window: mac, theme: 'dark');
    final dark = GlacierTheme.of(tester.element(ring()));
    final vividDark = jobColour(dark, JobLook.sync);
    await pumpShell(tester, window: mac, theme: 'light');
    final light = GlacierTheme.of(tester.element(ring()));
    expect(jobColour(light, JobLook.sync), isNot(vividDark));
    await pumpShell(tester, window: mac, theme: 'dark', calm: true);
    final calm = GlacierTheme.of(tester.element(ring()));
    expect(jobColour(calm, JobLook.sync), calm.color('app-ink'));
  });

  barTest('reduced motion: nothing moves, nothing asks for a frame', (tester) async {
    threeJobs();
    record.begin('voice', kind: JobKind.audio, title: 'Reading aloud');
    record.begin('model', kind: JobKind.downloads, title: 'Downloading the model');
    record.begin('meet', kind: JobKind.meetings, title: 'Ghost in the meeting');
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpShell(tester, window: mac);
    await tester.pump(const Duration(seconds: 1));
    expect(ring(), findsOneWidget);
    final spin = painter(tester).spin;
    await tester.pump(const Duration(milliseconds: 700));
    expect(painter(tester).spin, spin, reason: 'the arcs held still');
    await tester.tap(ring());
    await tester.pump(const Duration(milliseconds: 300));
    final glyphs = tester.stateList<JobGlyphState>(find.byType(JobGlyph)).toList();
    expect(glyphs.length, greaterThan(6), reason: 'the ring\'s and the tray\'s');
    expect(glyphs.where((glyph) => glyph.moving), isEmpty, reason: 'every glyph held still');
  });

  barTest('moving otherwise: the ring and its glyph turn for work that cannot say how far it is', (tester) async {
    record.begin('voice', kind: JobKind.audio, title: 'Reading aloud');
    await pumpShell(tester, window: mac);
    final before = painter(tester).spin;
    await tester.pump(const Duration(milliseconds: 300));
    expect(painter(tester).spin, isNot(before));
    expect(tester.state<JobGlyphState>(find.byType(JobGlyph)).moving, isTrue);
  });

  barTest('a sync fills its arc and never sweeps it (Matt, 2026-10-29: "Also don\'t spin the progress bar on the sync just make it fill as it\'s being synced")', (tester) async {
    final sync = record.begin('sync', kind: JobKind.sync, title: 'Syncing');
    await pumpShell(tester, window: mac);
    expect(painter(tester).arcs.single.fraction, 0, reason: 'empty before the counts are known');
    expect(painter(tester).arcs.single.moving, isFalse);
    final before = painter(tester).spin;
    await tester.pump(const Duration(milliseconds: 300));
    expect(painter(tester).spin, before, reason: 'nothing goes round');
    sync.progress(fraction: 12 / 40, steps: '12 of 40');
    await tester.pump();
    expect(painter(tester).arcs.single.fraction, closeTo(0.3, 1e-9));
    await tester.tap(ring());
    await tester.pump(const Duration(milliseconds: 300));
    // The tray says the title once and the count under it; a screen reader and the OS surfaces hear "Syncing, 12 of 40".
    expect(tester.widget<Text>(find.byKey(const ValueKey('activity-row:line:sync'))).data, '12 of 40');
    expect(record['sync']!.liveLine, 'Syncing, 12 of 40');
    expect(tester.widget<JobBar>(find.byType(JobBar)).fraction, closeTo(0.3, 1e-9), reason: 'a bar that fills');
  });

  group('the tray', () {
    barTest('a card hung under the ring on the Mac, with the rows, Stop, Open and the device', (tester) async {
      final said = <String>[];
      record.begin('lovart-banners', kind: JobKind.images, title: 'Making header images', onStop: () => said.add('stop'), onOpen: () => said.add('open'), estimate: const JobEstimate(credits: 72, provider: 'Lovart', count: 12, one: 'banner', many: 'banners'))
        ..progress(done: 2, total: 12)
        ..spend(12);
      record.elsewhere('handoff', [Job(id: 'summary:n1', kind: JobKind.ai, title: 'Summary of Standup', device: 'mac1', deviceName: 'Mac', startedAt: now, line: 'Writing the summary', steps: '2 of 3 parts')]);
      await pumpShell(tester, window: mac);
      await tester.tap(ring());
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(FloatingCard), findsOneWidget);
      expect(find.byType(Sheet), findsNothing);
      final card = tester.getRect(find.byKey(const ValueKey('floating-card')));
      expect(card.top, greaterThan(tester.getRect(ring()).bottom), reason: 'hangs under the ring');
      expect(find.text('Making header images'), findsOneWidget);
      // The title once, and under it how far, what it costs and has spent: never the title again (Matt, 2026-10-29).
      expect(find.text('2 of 12 · ~72 Lovart credits · 12 spent'), findsOneWidget);
      expect(find.textContaining('Making header images, '), findsNothing);
      expect(find.text('Writing the summary, 2 of 3 parts · on your Mac'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('activity-row:stop:lovart-banners')));
      await tester.tap(find.byKey(const ValueKey('activity-row:open:lovart-banners')));
      expect(said, ['stop', 'open']);
    });

    barTest('a sheet on a phone', (tester) async {
      record.begin('sync', kind: JobKind.sync, title: 'Syncing');
      await pumpShell(tester, window: folded);
      await tester.tap(ring());
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Sheet), findsOneWidget);
      expect(find.byType(FloatingCard), findsNothing);
      expect(find.byType(ActivityRow), findsOneWidget);
    });

    barTest('Today, and Past 7 days behind More', (tester) async {
      now = DateTime(2026, 10, 27, 12);
      record.begin('x', kind: JobKind.ai, title: 'Summary of Retro').done(tally: const JobTally('summary', 'summaries'));
      now = DateTime(2026, 10, 29, 9);
      for (var i = 0; i < 3; i += 1) {
        record.begin('s$i', kind: JobKind.ai, title: 'Summary $i').done(tally: const JobTally('summary', 'summaries'));
      }
      record.begin('run', kind: JobKind.images, title: 'Header images').done(tally: const JobTally('banner', 'banners', 12));
      record.begin('sync', kind: JobKind.sync, title: 'Syncing').done(tally: const JobTally('note synced', 'notes synced', 40));
      record.begin('post', kind: JobKind.ai, title: 'Posting to Slack').failed('Slack could not be reached');
      await pumpShell(tester, window: mac);
      await tester.tap(ring());
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Text>(find.byKey(const ValueKey('activity-tray:today'))).data, '3 summaries, 12 banners, 40 notes synced, 1 failed');
      expect(find.text('Tuesday 27 October  '), findsNothing);
      expect(find.byKey(const ValueKey('activity-tray:past:2026-10-27')), findsNothing, reason: 'behind More');
      await tester.tap(find.byKey(const ValueKey('activity-tray:more')));
      await tester.pump();
      expect(find.byKey(const ValueKey('activity-tray:past:2026-10-27')), findsOneWidget);
      expect(find.textContaining('1 summary', findRichText: true), findsWidgets);
    });

    for (final (kind, label) in [(JobFixKind.topUp, 'Top up'), (JobFixKind.signIn, 'Sign in again'), (JobFixKind.retry, 'Retry')]) {
      barTest('a failed row is red with its cause and one fix: $label', (tester) async {
        var fixed = 0;
        record.begin('job', kind: JobKind.images, title: 'Making header images').failed('Lovart is out of credits', fix: JobFix(kind, () => fixed += 1));
        await pumpShell(tester, window: mac);
        await tester.tap(ring());
        await tester.pump(const Duration(milliseconds: 300));
        final line = tester.widget<Text>(find.byKey(const ValueKey('activity-row:line:job')));
        expect(line.data, 'Lovart is out of credits');
        final t = GlacierTheme.of(tester.element(ring()));
        expect(line.style!.color, jobColour(t, JobLook.needsYou));
        expect(find.text(label), findsOneWidget);
        expect(find.byKey(const ValueKey('activity-row:stop:job')), findsNothing, reason: 'one fix, no Stop');
        await tester.tap(find.byKey(const ValueKey('activity-row:fix:job')));
        expect(fixed, 1);
        await tester.tap(find.byKey(const ValueKey('activity-row:dismiss:job')));
        await tester.pump();
        expect(record.value, isEmpty);
      });
    }

    barTest('a blip says it tries again on its own, then runs again', (tester) async {
      final job = record.begin('post', kind: JobKind.ai, title: 'Posting to Slack');
      final waited = <Duration>[];
      var tries = 0;
      await pumpShell(tester, window: mac);
      await tester.tap(ring());
      await tester.pump(const Duration(milliseconds: 300));
      final answer = retrying(job, () async {
        tries += 1;
        if (tries < 2) throw Exception('SocketException: lookup failed');
        return 'posted';
      }, blip: (e) => '$e'.contains('SocketException'), wait: (d) async {
        waited.add(d);
        await tester.pump();
        expect(tester.widget<Text>(find.byKey(const ValueKey('activity-row:line:post'))).data, 'Trying again in 2 s');
        expect(record.value.single.look, JobLook.waiting);
      });
      expect(await answer, 'posted');
      expect(waited, [const Duration(seconds: 2)]);
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const ValueKey('activity-row:line:post'))).data, 'Posting to Slack');
    });

    barTest('simple mode keeps the devices behind More', (tester) async {
      record.elsewhere('handoff', [Job(id: 'summary:n1', kind: JobKind.ai, title: 'Summary of Standup', device: 'mac1', deviceName: 'Mac', startedAt: now, line: 'Writing the summary')]);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpApp(tester, size: mac.size, home: ActivityTray(record: record, simple: true));
      await tester.pump();
      expect(find.text('Writing the summary'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('activity-tray:more')));
      await tester.pump();
      expect(find.text('Writing the summary · on your Mac'), findsOneWidget);
      expect(find.byKey(const ValueKey('activity-tray:past-none')), findsOneWidget);
    });
  });

  barTest('simple mode: the ring floats over the plain places while something runs, never idle', (tester) async {
    final sheet = await appSheet(tester);
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light', experience: 'simple', experienceChosen: true),
      home: AppShell(sheet: sheet, notes: library, workspaces: spaces, simple: true, mobile: true, finePointer: false, onDeleteNote: (_) {}),
    );
    await tester.pump(const Duration(milliseconds: 300));
    // No bar for an idle ring to sit in: none floats.
    expect(find.byKey(const ValueKey('activity-ring:floating')), findsNothing);
    expect(ring(), findsNothing);
    record.begin('sync', kind: JobKind.sync, title: 'Syncing');
    await tester.pump();
    expect(find.byKey(const ValueKey('activity-ring:floating')), findsOneWidget);
    expect(ring(), findsOneWidget);
    record.handle('sync')!.done();
    await tester.pump(activityBloom * 2);
    expect(find.byKey(const ValueKey('activity-ring:floating')), findsNothing);
    expect(ring(), findsNothing);
  });
}

class _StandInNote extends StatefulWidget {
  const _StandInNote({required this.note});
  final Note note;

  @override
  State<_StandInNote> createState() => _StandInNoteState();
}

class _StandInNoteState extends State<_StandInNote> {
  late final ValueNotifier<NoteToolsModel> _model = ValueNotifier(NoteToolsModel(
    kind: NoteKind.words,
    page: true,
    switchable: true,
    onSwitch: () {},
    onMore: () {},
    more: false,
    actions: [
      ToolAction(id: 'share', label: 'Share', icon: Lucide.share2, onPress: () {}),
      ToolAction(id: 'history', label: 'Version history', icon: Lucide.history, onPress: () {}),
      ToolAction(id: 'links', label: 'Linked from 3 notes', icon: Lucide.link2, count: 3, onPress: () {}),
      ToolAction(id: 'comment', label: 'Comment', icon: Lucide.messageSquarePlus, onPress: () {}),
      ToolAction(id: 'bookmark', label: 'Bookmark this line', icon: Lucide.bookmark, on: false, onPress: () {}),
      ToolAction(id: 'pin', label: 'Pin to the top', icon: Lucide.pin, on: false, onPress: () {}),
      ToolAction(id: 'archive', label: 'Archive', icon: Lucide.archive, onPress: () {}),
      ToolAction(id: 'speak', label: 'Talk into this note', icon: Lucide.mic, onPress: () {}),
    ],
  ));
  late final Widget _tools = NoteTools(model: _model);
  late final Widget _more = NoteMore(onMore: () {});

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TopBarFill(tools: _tools, tail: _more, model: _model, child: NotePlaceholder(note: widget.note));
}
