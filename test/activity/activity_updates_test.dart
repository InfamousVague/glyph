// The app's own update in the activity tray alone, under the ring's badge, and plugins' marks on their work (Matt,
// 2026-10-30: "show the updates stuff in the activity drawer only now with a badge and when an update is available show
// the badge and use plugin vendor logo icons for activity updates related to plugins"; docs/ACTIVITY.md, Updates and
// Plugin marks).
//
// The badge comes and goes with the update's stage (available, downloading, ready, installed, failed), idle or busy,
// in Calm and simple mode; the red dot takes its corner. The tray's Update section is its first thing. Each plugin's
// job wears that plugin's mark in its row, its Today line, its chip and the ring's middle; the app's own work keeps its
// kind's glyph; a store-shot build draws no mark at all. On a phone and the Mac.
//
// Pictures, not held: `FEATURE_SHOTS=1 flutter test --update-goldens test/activity/activity_updates_test.dart` writes
// them into build/feature-shots/activity-updates/.
import 'dart:io';

import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/activity/activity_chips.dart';
import 'package:ghost_md/activity/activity_look.dart';
import 'package:ghost_md/activity/activity_ring.dart';
import 'package:ghost_md/activity/job_mark.dart';
import 'package:ghost_md/app/ghost_app.dart' show GhostApp;
import 'package:ghost_md/art/app_icon.dart' show AppIcon;
import 'package:ghost_md/art/brand_marks.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/meet/meet_api.dart' show MeetBooking, MeetState;
import 'package:ghost_md/meet/meet_in.dart' show meetBotJobs;
import 'package:ghost_md/plugins/lovart/banner_run.dart' show BannerClaim, bannerJobsElsewhere;
import 'package:ghost_md/plugins/lovart/making.dart' show lovartPictureJob;
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/placeholders.dart';
import 'package:glacier/glacier.dart' show GlacierTheme;

import '../notes/bar_support.dart';
import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  final shots = Platform.environment.containsKey('FEATURE_SHOTS');
  const folder = '../../build/feature-shots/activity-updates';
  const phone = (name: 'phone', size: Size(390, 844), mobile: true, fine: false);
  const mac = (name: 'mac', size: Size(1280, 800), mobile: false, fine: true);

  late DateTime now;
  late Activity record;
  setUp(() {
    now = DateTime(2026, 10, 30, 10);
    record = Activity(clock: () => now, store: () => MemoryStored());
    useActivity(record);
  });
  tearDown(() {
    useActivity(Activity());
    debugStoreShots = null;
  });

  /// A test of the shell, its debug switches put back before the binding checks them.
  void shellTest(String description, Future<void> Function(WidgetTester tester) body, {bool skip = false}) => testWidgets(description, skip: skip, (tester) async {
        try {
          await body(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
          debugDisableShadows = true;
        }
      });

  Future<void> pumpShell(WidgetTester tester, ({String name, Size size, bool mobile, bool fine}) window, {String theme = 'light', bool calm = false}) async {
    if (window == mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
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
        openNotes: const ['weekend', 'groceries', 'standup'],
        mobile: window.mobile,
        finePointer: window.fine,
        onNew: () {},
        onSearch: () {},
        onSettings: () {},
        onOrganizations: () {},
        onDeleteNote: (_) {},
        noteBuilder: (context, shell, screen) => NotePlaceholder(note: screen.note),
        homeBuilder: (context, shell) => HomePlaceholder(notes: shell.notes, onOpen: shell.openNote, onAllNotes: shell.showAllNotes),
        asideBuilder: (context, shell) => const SizedBox.shrink(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder ring() => find.byKey(ActivityRing.key_);
  Finder badge() => find.byKey(const ValueKey('activity-ring:update'));
  Finder dot() => find.byKey(const ValueKey('activity-ring:dot'));

  Future<void> openTray(WidgetTester tester) async {
    await tester.tap(ring());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  var installs = 0, restarts = 0, checks = 0;
  void install() => installs += 1;
  void restart() => restarts += 1;
  void check() => checks += 1;
  UpdateOffer offer(UpdateStage stage, {String? notes, String? message}) =>
      UpdateOffer(stage: stage, version: '2.3.86', running: '2.3.85', notes: notes, message: message, onInstall: install, onRestart: restart, onCheck: check);

  group('the badge', () {
    for (final window in [phone, mac]) {
      shellTest('comes and goes with the update: available, downloading, ready, installed, failed, ${window.name}', (tester) async {
        await pumpShell(tester, window);
        expect(badge(), findsNothing);
        expect(tester.getSemantics(ring()).label, 'Activity: nothing running');

        // Available: on the idle grey ring, at its corner, with its words.
        record.update = offer(UpdateStage.available);
        await tester.pump();
        expect(badge(), findsOneWidget);
        expect(find.byKey(const ValueKey('activity-ring:idle-check')), findsOneWidget, reason: 'the ring is idle all the same');
        expect(tester.getSemantics(ring()).label, 'Activity: nothing running, update available');
        final r = tester.getRect(ring()), b = tester.getRect(badge());
        expect(b.center.dx, greaterThan(r.center.dx), reason: 'at the end corner');
        expect(b.center.dy, lessThan(r.center.dy), reason: 'at the top');

        // Downloading: the badge stays, and the download's arc runs green.
        record.update = offer(UpdateStage.downloading);
        final job = record.begin(appUpdateJobId, kind: JobKind.downloads, title: 'Downloading the update', fraction: 0.4);
        await tester.pump();
        expect(badge(), findsOneWidget);
        expect(tester.getSemantics(ring()).label, 'Activity: 1 job running, update available');

        // Ready (the Mac's, in place for a restart): still.
        job.done();
        record.update = offer(UpdateStage.ready);
        await tester.pump(const Duration(seconds: 1));
        expect(badge(), findsOneWidget);

        // Installed: nothing newer, and the badge goes.
        record.update = const UpdateOffer(stage: UpdateStage.upToDate, running: '2.3.86');
        await tester.pump();
        expect(badge(), findsNothing);
        expect(tester.getSemantics(ring()).label, 'Activity: nothing running');

        // Failed: the update still waits, but its red row's dot wins the corner.
        record.update = offer(UpdateStage.failed, message: 'The installer did not start.');
        record.begin(appUpdateJobId, kind: JobKind.downloads, title: 'Downloading the update').failed('The installer did not start.', fix: JobFix(JobFixKind.retry, install));
        await tester.pump();
        expect(dot(), findsOneWidget);
        expect(badge(), findsNothing, reason: 'red wins the corner');
        expect(tester.getSemantics(ring()).label, 'Activity: something needs you, update available');

        // Gone with it: no update.
        record.dismiss(appUpdateJobId);
        record.update = null;
        await tester.pump();
        expect((badge().evaluate().length, dot().evaluate().length), (0, 0));
      });
    }

    shellTest('is the downloads\' green, and in Calm the ink', (tester) async {
      for (final calm in [false, true]) {
        record.update = offer(UpdateStage.available);
        await pumpShell(tester, phone, calm: calm);
        final t = GlacierTheme.of(tester.element(badge()));
        final drawn = (tester.widget<Container>(badge()).decoration! as BoxDecoration).color;
        expect(drawn, jobColour(t, JobLook.downloads));
        expect(drawn == t.color('app-ink'), calm, reason: calm ? 'Calm draws it in ink' : 'vivid, the downloads\' green');
        expect(tester.widget<AppIcon>(find.descendant(of: badge(), matching: find.byType(AppIcon))).icon.name, 'arrow-up');
      }
    });

    test('simple mode floats the ring for it, as for a job: the plain pages have no bar to hold an idle one', () {
      final shown = activityShown;
      var told = 0;
      void heard() => told += 1;
      shown.addListener(heard);
      expect(shown.value, isFalse);
      record.update = offer(UpdateStage.available);
      expect(shown.value, isTrue);
      record.update = const UpdateOffer(stage: UpdateStage.upToDate);
      expect(shown.value, isFalse);
      // Asked open at the update from Settings, it floats while that tray is up.
      record.showUpdate();
      expect(shown.value, isTrue);
      record.updateSeen();
      expect(shown.value, isFalse);
      expect(told, 4);
      shown.removeListener(heard);
    });
  });

  group('the tray\'s Update section', () {
    for (final window in [phone, mac]) {
      shellTest('is the tray\'s first thing while the badge is up: its line, what\'s new, its one action, ${window.name}', (tester) async {
        record.begin('lovart-banners', kind: JobKind.images, title: 'Making header images', plugin: 'lovart').progress(done: 4, total: 12);
        record.update = offer(UpdateStage.available, notes: 'The tray says what the app is doing.');
        await pumpShell(tester, window);
        await openTray(tester);
        final section = find.byKey(const ValueKey('activity-tray:update'));
        expect(section, findsOneWidget);
        expect(find.text('Ghost.md 2.3.86 is ready'), findsOneWidget);
        expect(find.text('The tray says what the app is doing.'), findsOneWidget);
        expect(tester.getRect(section).top, lessThan(tester.getRect(find.byKey(const ValueKey('activity-row:lovart-banners'))).top));
        expect(find.text('Install'), findsOneWidget);
        await tester.tap(find.text('Install'));
        expect(installs, greaterThan(0));
      });
    }

    shellTest('holds the download as its own row with its bar, drawn once, and the failure red with Retry', (tester) async {
      record.update = offer(UpdateStage.downloading);
      final job = record.begin(appUpdateJobId, kind: JobKind.downloads, title: 'Downloading the update', fraction: 0)..progress(fraction: 0.5, steps: '22 MB of 44 MB');
      await pumpShell(tester, phone);
      await openTray(tester);
      final section = find.byKey(const ValueKey('activity-tray:update'));
      expect(find.text('Downloading Ghost.md 2.3.86'), findsOneWidget);
      expect(find.byKey(const ValueKey('activity-row:update')), findsOneWidget, reason: 'once, in the section');
      expect(find.descendant(of: section, matching: find.byKey(const ValueKey('activity-row:update'))), findsOneWidget);
      expect(find.descendant(of: section, matching: find.byKey(const ValueKey('job-bar'))), findsOneWidget);
      expect(find.byKey(const ValueKey('activity-tray:idle')), findsNothing, reason: 'the download is something running');
      expect(find.byKey(const ValueKey('activity-tray:update:action')), findsNothing, reason: 'nothing to press while it comes down');

      job.failed('Connection reset by peer', fix: JobFix(JobFixKind.retry, install));
      record.update = offer(UpdateStage.failed, message: 'Connection reset by peer');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Ghost.md 2.3.86 didn’t install'), findsOneWidget);
      expect(find.descendant(of: section, matching: find.byKey(const ValueKey('activity-row:fix:update'))), findsOneWidget);
      expect(find.byKey(const ValueKey('activity-tray:update:action')), findsNothing, reason: 'the row\'s Retry is the one fix');
      await tester.tap(find.descendant(of: section, matching: find.byKey(const ValueKey('activity-row:fix:update'))));
      expect(installs, greaterThan(0));
    });

    shellTest('opened from Settings it says where the check stands with nothing waiting, and is closed again with the tray', (tester) async {
      record.update = const UpdateOffer(stage: UpdateStage.upToDate, running: '2.3.85');
      await pumpShell(tester, mac);
      await openTray(tester);
      expect(find.byKey(const ValueKey('activity-tray:update')), findsNothing, reason: 'nothing waits, and nobody asked');
      await tester.tap(ring());
      await tester.pump(const Duration(milliseconds: 300));
      record.showUpdate();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Ghost.md 2.3.85 is up to date'), findsOneWidget);
      expect(record.updateWanted, isTrue);
      await tester.tap(ring());
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('activity-tray:update')), findsNothing);
      expect(record.updateWanted, isFalse);
    });

    test('says each stage in its words, with its one action', () {
      final said = {for (final stage in UpdateStage.values) stage: (offer(stage).words, offer(stage).action, offer(stage).badge)};
      expect(said, {
        UpdateStage.notChecked: ('Not checked for updates yet', 'Check again', false),
        UpdateStage.checking: ('Checking for updates…', null, false),
        UpdateStage.upToDate: ('Ghost.md 2.3.85 is up to date', 'Check again', false),
        UpdateStage.checkFailed: ('Couldn’t check for updates', 'Check again', false),
        UpdateStage.available: ('Ghost.md 2.3.86 is ready', 'Install', true),
        UpdateStage.downloading: ('Downloading Ghost.md 2.3.86', null, true),
        UpdateStage.installing: ('Ghost.md 2.3.86 is waiting on Android', 'Open', true),
        UpdateStage.needsPermission: ('Let Ghost.md install apps, then come back', 'Install', true),
        UpdateStage.ready: ('Ghost.md 2.3.86 is downloaded', 'Restart to update', true),
        UpdateStage.restarting: ('Restarting into Ghost.md 2.3.86', null, true),
        UpdateStage.failed: ('Ghost.md 2.3.86 didn’t install', 'Try again', true),
      });
      offer(UpdateStage.ready).onAction!();
      offer(UpdateStage.checkFailed).onAction!();
      expect((restarts, checks), (1, 1));
    });
  });

  group('plugins\' marks on their work', () {
    // Every plugin whose work is on the record, and the one mark it wears: its company's (a BrandMarkIcon), or its
    // glyph where it has none.
    const jobs = <(String id, JobKind kind, String plugin, bool brand)>[
      ('lovart-banners', JobKind.images, 'lovart', true),
      ('summary:a', JobKind.ai, 'claude', true),
      ('summary:b', JobKind.ai, 'openai', false),
      ('summary:c', JobKind.ai, 'gemini', true),
      ('summary:d', JobKind.ai, 'aster', false),
      ('summary:e', JobKind.ai, 'custom-ai', false),
      ('voice-over:a', JobKind.audio, 'elevenlabs', true),
      ('slack-post:a', JobKind.meetings, 'slack', false),
      ('discord-post:a', JobKind.meetings, 'discord', true),
      ('fetch:notion', JobKind.sync, 'notion', true),
      ('fetch:github', JobKind.sync, 'github', true),
      ('calendar:google', JobKind.sync, 'calendar', true),
      ('meet:a', JobKind.meetings, 'google-meet', true),
      ('meet:b', JobKind.meetings, 'zoom', false),
      ('todoist:a', JobKind.sync, 'todoist', true),
      ('things:a', JobKind.sync, 'things', true),
    ];

    Finder mark(String plugin) => find.byKey(ValueKey('job-mark:$plugin'));

    for (final window in [phone, mac]) {
      shellTest('each wears its mark in its tray row and in Today, the app\'s own work its glyph, ${window.name}', (tester) async {
        for (final (id, kind, plugin, _) in jobs) {
          record.begin(id, kind: kind, title: 'Work of $plugin', plugin: plugin);
        }
        record.begin('sync', kind: JobKind.sync, title: 'Syncing');
        record.begin('meeting-recording', kind: JobKind.audio, title: 'Recording');
        record.begin('model:qwen', kind: JobKind.downloads, title: 'Downloading Qwen');
        // Today: a banner and a post that ended.
        record.begin('banner:n1', kind: JobKind.images, title: 'Header image for Trip', plugin: 'lovart').done(tally: const JobTally('banner', 'banners'));
        record.begin('slack:n1', kind: JobKind.meetings, title: 'Posting Standup to Slack', plugin: 'slack').done(tally: const JobTally('Slack post', 'Slack posts'));
        await pumpShell(tester, window);
        await openTray(tester);
        for (final (id, _, plugin, brand) in jobs) {
          final row = find.byKey(ValueKey('activity-row:$id'));
          await tester.ensureVisible(row);
          expect(find.descendant(of: row, matching: mark(plugin)), findsOneWidget, reason: '$plugin in its row');
          expect(find.descendant(of: row, matching: find.byType(BrandMarkIcon)), brand ? findsOneWidget : findsNothing, reason: '$plugin: ${brand ? 'its company\'s mark' : 'its glyph'}');
        }
        // Google Meet's on its tile, white, where the row has one.
        final meet = find.descendant(of: find.byKey(const ValueKey('activity-row:meet:a')), matching: find.byType(BrandMarkIcon));
        expect(tester.widget<BrandMarkIcon>(meet).color, const Color(0xFFFFFFFF));
        // The rest's in their brand's colour on the paper (Lovart's has none: the ink).
        final claude = find.descendant(of: find.byKey(const ValueKey('activity-row:summary:a')), matching: find.byType(BrandMarkIcon));
        expect(tester.widget<BrandMarkIcon>(claude).color, brandMark('claude')!.colour);
        // The app's own keep their kind's glyphs.
        for (final (id, kind) in [('sync', 'sync'), ('meeting-recording', 'audio'), ('model:qwen', 'downloads')]) {
          final row = find.byKey(ValueKey('activity-row:$id'));
          await tester.ensureVisible(row);
          expect(find.descendant(of: row, matching: find.byKey(ValueKey('job-glyph:$kind'))), findsOneWidget, reason: id);
          expect(find.descendant(of: row, matching: find.byType(JobMark)), findsNothing, reason: id);
        }
        // Today's lines.
        final today = find.byKey(const ValueKey('activity-tray:today'));
        await tester.ensureVisible(today);
        expect(record.log.today.rows.map((r) => r.plugin), ['slack', 'lovart']);
        expect(find.byKey(const ValueKey('job-mark:lovart')), findsNWidgets(3), reason: 'the run\'s row, the banner\'s line, and the ring\'s middle, the run leading');
        expect(find.byKey(const ValueKey('job-mark:slack')), findsNWidgets(2));
      });
    }

    shellTest('a plugin\'s job wears its mark in the ring\'s middle while it leads, and a chip of its too', (tester) async {
      await pumpShell(tester, phone);
      final job = record.begin('voice-over:n2', kind: JobKind.audio, title: 'Reading “Trip” aloud', plugin: 'elevenlabs');
      await tester.pump();
      expect(find.descendant(of: ring(), matching: mark('elevenlabs')), findsOneWidget);
      expect(find.descendant(of: ring(), matching: find.byKey(const ValueKey('job-glyph:audio'))), findsNothing);
      job.done(result: JobResult('Voice-over ready', action: 'Open', onOpen: () {}));
      await tester.pump(const Duration(milliseconds: 400));
      final chip = find.byType(ChipFace);
      expect(chip, findsOneWidget);
      expect(find.descendant(of: chip, matching: mark('elevenlabs')), findsOneWidget);
      expect(find.descendant(of: chip, matching: find.byKey(const ValueKey('activity-chip:dot'))), findsNothing);
      // A plain job's chip keeps its dot; a plugin's failure keeps the red dot too.
      record.begin('sync', kind: JobKind.sync, title: 'Syncing').done(result: const JobResult('Synced'));
      record.begin('slack-post:n1', kind: JobKind.meetings, title: 'Posting to Slack', plugin: 'slack').failed('Not posted to #team.');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('activity-chip:dot')), findsNWidgets(2));
      expect(find.byKey(const ValueKey('activity-chip:mark')), findsNothing);
      await tester.pump(chipFor);
      await tester.pump(const Duration(seconds: 1));
    });

    test('a chip of a plugin\'s job carries its plugin', () {
      final job = record.begin('banner:n1', kind: JobKind.images, title: 'Header image', plugin: 'lovart');
      Job? ended;
      record.events.listen((e) => ended = e.kind == JobEventKind.ended ? e.job : ended);
      job.done(result: const JobResult('Banner ready'));
      expect(ActivityChip.of(ended!)?.plugin, 'lovart');
    });

    shellTest('a waiting plugin job wears its mark dimmed, and one that needs you the red dot', (tester) async {
      record.begin('voice-over:a', kind: JobKind.audio, title: 'Reading aloud', plugin: 'elevenlabs').waiting(WaitingOn.wifi);
      record.begin('summary:a', kind: JobKind.ai, title: 'Summary', plugin: 'claude').waiting(WaitingOn.credits);
      await pumpShell(tester, phone);
      await openTray(tester);
      final waiting = find.descendant(of: find.byKey(const ValueKey('activity-row:voice-over:a')), matching: mark('elevenlabs'));
      expect(find.descendant(of: waiting, matching: find.byType(Opacity)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('activity-row:summary:a')), matching: find.byKey(const ValueKey('job-glyph:dot'))), findsOneWidget);
    });

    shellTest('a store-shot build (GHOST_STORE_NEUTRAL) draws no mark: every job its kind\'s glyph', (tester) async {
      debugStoreShots = true;
      for (final (id, kind, plugin, _) in jobs) {
        record.begin(id, kind: kind, title: 'Work of $plugin', plugin: plugin);
      }
      await pumpShell(tester, mac);
      record.begin('banner:n1', kind: JobKind.images, title: 'Header image', plugin: 'lovart').done(result: JobResult('Banner ready', onOpen: () {}), tally: const JobTally('banner', 'banners'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(ChipFace), findsOneWidget);
      expect(find.byKey(const ValueKey('activity-chip:dot')), findsOneWidget);
      await openTray(tester);
      expect(find.byType(JobMark), findsNothing);
      expect(find.byType(BrandMarkIcon), findsNothing);
      for (final (id, kind, _, _) in jobs) {
        final row = find.byKey(ValueKey('activity-row:$id'));
        await tester.ensureVisible(row);
        expect(find.descendant(of: row, matching: find.byKey(ValueKey('job-glyph:${kind.name}'))), findsOneWidget, reason: id);
      }
      expect(markedPlugin('lovart'), isNull);
      await tester.pump(chipFor);
      await tester.pump(const Duration(seconds: 1));
    });

    test('where each job begins it says whose it is', () {
      // Lovart's pictures and another device's run.
      expect(lovartPictureJob('lovart-cue:k', noteId: 'n1', title: 'Image').job?.plugin, 'lovart');
      expect(bannerJobsElsewhere(const BannerClaim(by: 'mac1', name: 'Mac', at: 0, done: 2, total: 5)).single.plugin, 'lovart');
      // The meeting bot, by the service it is in.
      MeetBooking booking(String id, String kind) => MeetBooking(id: id, kind: kind, startsAt: 0, endsAt: 1, state: MeetState.inCall);
      expect([for (final job in meetBotJobs([booking('a', 'meet'), booking('b', 'zoom'), booking('c', 'discord')])) job.plugin], ['google-meet', 'zoom', 'discord']);
      // Ended, the log keeps it, and reads it back.
      final logged = LoggedJob.fromJson(LoggedJob(title: 't', kind: JobKind.images, failed: false, at: now, plugin: 'lovart').toJson());
      expect(logged?.plugin, 'lovart');
      expect(LoggedJob.fromJson(LoggedJob(title: 't', kind: JobKind.sync, failed: false, at: now).toJson())?.plugin, isNull);
      // A job begun again keeps its plugin.
      record.begin('fetch:notion', kind: JobKind.sync, title: 'Reading from Notion', plugin: 'notion');
      record.begin('fetch:notion', kind: JobKind.sync, title: 'Reading from Notion');
      expect(record['fetch:notion']?.plugin, 'notion');
    });
  });

  // ---- pictures -----------------------------------------------------------------------------------------------------

  Future<void> picture(WidgetTester tester, String name) async {
    for (var i = 0; i < 4; i += 1) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await expectLater(find.byType(GhostApp), matchesGoldenFile('$folder/$name.png'));
  }

  void busy() {
    now = DateTime(2026, 10, 30, 9);
    record.begin('done1', kind: JobKind.ai, title: 'Summary of Standup', plugin: 'claude').done(tally: const JobTally('summary', 'summaries'));
    record.begin('done2', kind: JobKind.meetings, title: 'Posting Standup to Slack', plugin: 'slack').done(tally: const JobTally('Slack post', 'Slack posts'));
    now = DateTime(2026, 10, 30, 10);
    record.begin('lovart-banners', kind: JobKind.images, title: 'Making header images', plugin: 'lovart', estimate: const JobEstimate(credits: 72, provider: 'Lovart', count: 12, one: 'header image', many: 'header images'))
      ..progress(done: 5, total: 12)
      ..update(spent: 30);
    record.begin('summary:n1', kind: JobKind.ai, title: 'Summary of Design review', line: 'Writing the summary with Claude', plugin: 'claude').progress(fraction: 0.5, steps: '2 of 3 parts');
    record.begin('voice-over:n2', kind: JobKind.audio, title: 'Reading “Trip notes” aloud', line: 'Reading in Elara’s voice', plugin: 'elevenlabs').progress(done: 1, total: 3, steps: '2 of 3 parts');
    record.elsewhere('meet-bot', [Job(id: 'meet:b1', kind: JobKind.meetings, title: 'Ghost in Weekly sync', line: 'In the meeting', device: 'meet-bot', deviceName: 'meeting bot', placeWords: 'with Ghost’s meeting bot', startedAt: now, plugin: 'google-meet')]);
    record.begin('fetch:github', kind: JobKind.sync, title: 'Reading from GitHub', plugin: 'github').progress(done: 2, total: 5);
  }

  for (final window in [phone, mac]) {
    for (final theme in ['light', 'dark']) {
      final look = '${window.name}-$theme';
      shellTest('a picture: the idle ring wearing the update\'s badge, $look', (tester) async {
        record.update = offer(UpdateStage.available);
        await pumpShell(tester, window, theme: theme);
        await picture(tester, 'badge-idle-$look');
      }, skip: !shots);

      shellTest('a picture: the busy ring, a plugin\'s mark in its middle and the badge, $look', (tester) async {
        busy();
        record.update = offer(UpdateStage.available);
        await pumpShell(tester, window, theme: theme);
        await picture(tester, 'badge-busy-$look');
      }, skip: !shots);

      shellTest('a picture: the tray, the update first and plugins\' rows with their marks, $look', (tester) async {
        busy();
        record.update = offer(UpdateStage.available, notes: 'The activity tray says what the app is doing, with each plugin’s mark on its work.');
        await pumpShell(tester, window, theme: theme);
        await openTray(tester);
        await picture(tester, 'tray-$look');
      }, skip: !shots);

      shellTest('a picture: the tray with the update coming down, $look', (tester) async {
        busy();
        record.update = offer(UpdateStage.downloading);
        record.begin(appUpdateJobId, kind: JobKind.downloads, title: 'Downloading the update', line: 'Downloading', fraction: 0).progress(fraction: 0.45, steps: '20 MB of 44 MB');
        await pumpShell(tester, window, theme: theme);
        await openTray(tester);
        await picture(tester, 'tray-downloading-$look');
      }, skip: !shots);

      shellTest('a picture: chips with a plugin\'s mark, $look', (tester) async {
        await pumpShell(tester, window, theme: theme);
        record.begin('banner:n9', kind: JobKind.images, title: 'Header image for Trip notes', plugin: 'lovart').done(result: JobResult('Banner ready', onOpen: () {}));
        record.begin('slack-post:n8', kind: JobKind.meetings, title: 'Posting to Slack', plugin: 'slack').done(result: JobResult('Posted to #team', action: 'Open', onOpen: () {}));
        await picture(tester, 'chip-$look');
        await tester.pump(chipFor);
        await tester.pump(const Duration(seconds: 1));
      }, skip: !shots);
    }
  }
}
