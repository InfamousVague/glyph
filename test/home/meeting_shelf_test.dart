import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/meeting_shelf.dart';
import 'package:ghost_md/tapes/previews.dart';
import 'package:ghost_md/tapes/tape_art.dart';
import 'package:glacier/glacier.dart';

import '../core/make_note.dart';
import '../support/edges.dart';
import '../support/render.dart';
import '../tapes/fake_player.dart';
import 'support.dart';

/// The shelf of meetings on the home page (GHST-112; Matt, 2026-10-23: "Add a shelf for meeting recordings and show
/// the note title on the cassette"): which meetings it holds and in what order, the title on each label, a tap, the
/// rules for simple mode and a search; and pictures at a phone's size (390 x 844) and a wide window's (1200 x 800),
/// light and dark, written to build/feature-shots/shelf/ to be looked at, not held as goldens.
void main() {
  setUpAll(loadAppFonts);

  const hour = 3600000;
  const day = 24 * hour;
  const longTitle = 'Quarterly planning with the whole design and engineering team, and the long list of what slipped';

  /// Meetings and a voice note among the seeded library: the standup this morning, a retro yesterday, a long-titled
  /// planning last week, one whose tape is on another device, and a meeting with no tape at all.
  List<Note> library() => [
        ...seedLibrary(),
        makeNote('mt-standup', body: '# Standup\n\nWhat we did.', createdAt: seedNow - 2 * hour, updatedAt: seedNow - 2 * hour, recordingMs: 12 * 60000 + 40000),
        makeNote('mt-retro', body: '# Sprint retro\n\nWhat went well.', createdAt: seedNow - day, updatedAt: seedNow - day, recordingMs: 48 * 60000),
        makeNote('mt-planning', body: '# $longTitle\n\nThe plan.', createdAt: seedNow - 6 * day, updatedAt: seedNow - 6 * day, recordingMs: 62 * 60000 + 3000),
        makeNote('mt-elsewhere', body: '# Client call\n\nRecorded on the laptop.', createdAt: seedNow - 3 * day, updatedAt: seedNow - 3 * day, recordingMs: 25 * 60000),
        makeNote('mt-untaped', body: '# Booked, never taped', createdAt: seedNow - hour, updatedAt: seedNow - hour),
        makeNote('mt-voice', body: '# A voice note', createdAt: seedNow - hour, updatedAt: seedNow - hour, source: NoteSource.capture, recordingMs: 40000),
      ];

  // The retro started before its note was made; the rest by their notes.
  final meetings = <String, num>{'mt-standup': seedNow - 2 * hour, 'mt-retro': seedNow - day - hour, 'mt-planning': seedNow - 6 * day, 'mt-elsewhere': seedNow - 3 * day, 'mt-untaped': seedNow - hour};

  ({SampleLibrary library, WorkspaceStore workspaces, Asked asked}) made() =>
      (library: SampleLibrary(library(), clock: () => seedNow), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), asked: Asked());

  Future<void> away(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  List<String> tapesShown(WidgetTester tester) => [
        for (final element in find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('meeting-tape-')).evaluate())
          (element.widget.key! as ValueKey<String>).value.substring('meeting-tape-'.length),
      ];

  group('which meetings', () {
    test('the meetings with a tape, here or known, the newest first; never another tape, nor one without', () {
      expect(ids(shelvedMeetings(library(), meetings)), ['mt-standup', 'mt-retro', 'mt-elsewhere', 'mt-planning']);
    });

    test('the meeting being recorded leads, tape or not; an archived one is gone', () {
      expect(ids(shelvedMeetings(library(), meetings, live: 'mt-untaped')), ['mt-untaped', 'mt-standup', 'mt-retro', 'mt-elsewhere', 'mt-planning']);
      final archived = [for (final n in library()) n.id == 'mt-standup' ? n.copyWith(archivedAt: () => seedNow) : n];
      expect(ids(shelvedMeetings(archived, meetings)), ['mt-retro', 'mt-elsewhere', 'mt-planning']);
    });

    test('none with no meetings', () {
      expect(shelvedMeetings(library(), const {}), isEmpty);
    });

    test('a screen reader hears the title, the day and the length', () {
      final standup = library().firstWhere((n) => n.id == 'mt-standup');
      expect(meetingSaid(standup, meetings), startsWith('Meeting, Standup, '));
      expect(meetingSaid(standup, meetings), endsWith(', 12:40'));
      expect(meetingSaid(standup, meetings, live: true), endsWith(', recording now'));
    });
  });

  group('on the home page', () {
    testWidgets('shows the meetings newest first with their titles on the cassettes, and no other tape', (tester) async {
      final it = made();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: meetings));
      await settle(tester);
      expect(find.byKey(const ValueKey('meeting-shelf')), findsOneWidget);
      expect(find.bySemanticsLabel('Meetings, 4'), findsOneWidget);
      expect(tapesShown(tester), ['mt-standup', 'mt-retro', 'mt-elsewhere', 'mt-planning']);
      final titles = [for (final art in tester.widgetList<TapeArt>(find.descendant(of: find.byKey(const ValueKey('meeting-shelf')), matching: find.byType(TapeArt)))) art.title];
      expect(titles, ['Standup', 'Sprint retro', 'Client call', longTitle]);
      expect(find.bySemanticsLabel(RegExp(r'^Meeting, Standup, .*, 12:40$')), findsOneWidget);
      expect(find.byKey(const ValueKey('meeting-tape-mt-voice')), findsNothing);
      expect(find.byKey(const ValueKey('meeting-tape-mt-untaped')), findsNothing);
      // Twelve or fewer: no See all.
      expect(find.byKey(const ValueKey('meeting-shelf-all')), findsNothing);
      await away(tester);
    });

    // Matt, 2026-10-25: "when scrolled all the way to the right the blur over the cassettes should disappear from
    // the right". The row's ends are the tab row's: soft while there are cassettes past them, and only then.
    testWidgets('the row\'s ends are soft only with cassettes past them: the right one goes as the row reaches its end, the left one comes', (tester) async {
      final it = made();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: meetings), size: const Size(390, 844));
      await settle(tester);
      final shelf = find.byKey(const ValueKey('meeting-shelf'));
      final row = tester.widget<SingleChildScrollView>(find.byKey(const ValueKey('meeting-shelf-row'))).controller!;
      BlurSides sides() => tester.widget<BlurSides>(find.descendant(of: shelf, matching: find.byType(BlurSides)));
      // The ends as drawn: the strips' masks, at the row's two ends.
      List<EdgeSide> ends() => [
            for (final strip in edgeStripsUnder(tester, shelf))
              if (strip case EdgeBlurStrip(:final side)) side else if (strip case EdgeFadeStrip(:final rect)) rect.left <= 0 ? EdgeSide.left : EdgeSide.right,
          ];
      final width = tester.getSize(find.byKey(const ValueKey('meeting-shelf-row'))).width;
      List<EdgeFade> fades() => [for (final strip in edgeStripsUnder(tester, shelf)) if (strip case EdgeFadeStrip(:final fade)) fade else if (strip case EdgeBlurStrip(:final fade?)) fade];

      // At its start: more to the right, none to the left.
      expect(row.position.maxScrollExtent, greaterThan(blurSidesDepth * 2), reason: 'four cassettes are wider than a phone');
      expect((sides().start, sides().end, sides().endShown), (false, true, 1.0));
      expect(ends(), [EdgeSide.right]);
      expect(fades().first.at(width - 0.5), lessThan(0.1), reason: 'the last cassette in view fades out at the row\'s right end');

      // Between: both.
      row.jumpTo(row.position.maxScrollExtent / 2);
      await tester.pump();
      expect((sides().start, sides().end, sides().startShown, sides().endShown), (true, true, 1.0, 1.0));
      expect(ends()..sort((a, b) => a.index - b.index), [EdgeSide.left, EdgeSide.right]);

      // Nearly there: the right end on its way out.
      row.jumpTo(row.position.maxScrollExtent - blurSidesDepth / 2);
      await tester.pump();
      expect(sides().endShown, closeTo(0.5, 1e-6));
      expect(fades().first.at(width - 0.5), greaterThan(0), reason: 'half the fade, its edge less clear');

      // At the end: the right end gone, the left one there.
      row.jumpTo(row.position.maxScrollExtent);
      await tester.pump();
      expect((sides().start, sides().end, sides().startShown), (true, false, 1.0));
      expect(ends(), [EdgeSide.left]);
      expect(fades().single.at(width - 0.5), 1, reason: 'the last cassette whole to the row\'s end');

      // And back at the start, the left one gone again.
      row.jumpTo(0);
      await tester.pump();
      expect(ends(), [EdgeSide.right]);
      expect(tester.takeException(), isNull);
      await away(tester);
    });

    testWidgets('a row that fits has no ends at all', (tester) async {
      final it = made();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: meetings), size: const Size(1200, 800));
      await settle(tester);
      final shelf = find.byKey(const ValueKey('meeting-shelf'));
      expect(tester.widget<SingleChildScrollView>(find.byKey(const ValueKey('meeting-shelf-row'))).controller!.position.maxScrollExtent, 0);
      expect(edgeStripsUnder(tester, shelf), isEmpty);
      await away(tester);
    });

    testWidgets('a tap opens the note at its tape (Matt, 2026-10-24)', (tester) async {
      final it = made();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: meetings));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('meeting-tape-mt-retro')));
      await settle(tester);
      expect(it.asked.said, contains('open mt-retro at its tape'));
      expect(it.asked.said, isNot(contains('open mt-retro')));
      await away(tester);
    });

    // Matt, 2026-10-24: "when we hover a tape, start playing it's audio and animate the cassete on desktop".
    testWidgets('a mouse resting on a cassette plays its tape and turns its reels; passing over plays nothing; leaving stops it', (tester) async {
      final it = made();
      final player = FakeTapePlayer(lengths: const {'mt-retro': 48 * 60000});
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: meetings, tapePlayer: player));
      await settle(tester);
      TapeArt art(String id) => tester.widget<TapeArt>(find.descendant(of: find.byKey(ValueKey('meeting-tape-$id')), matching: find.byType(TapeArt)));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      // At rest it is rewound, where a hover starts it, so its reels keep their sizes when it plays (Matt,
      // 2026-10-24: "when hovering tapes the size of the reels jumps when the tape starts playing").
      expect(art('mt-retro').positionMs, 0);
      // Passing over the standup on the way: shorter than the dwell, so nothing loads.
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('meeting-tape-mt-standup'))));
      await tester.pump(meetingHoverDwell ~/ 2);
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('meeting-tape-mt-retro'))));
      await tester.pump(meetingHoverDwell);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      expect(player.calls, ['load mt-retro', 'play']);
      expect(art('mt-retro').playing, isTrue, reason: 'its reels turn');
      expect(art('mt-retro').positionMs, 0, reason: 'the tape winds from the start with the playhead');
      expect(art('mt-standup').playing, isFalse);
      // Away: it stops, rewound again.
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 200));
      expect(player.calls.last, 'pause');
      expect(art('mt-retro').playing, isFalse);
      expect(art('mt-retro').positionMs, 0);
      await away(tester);
    });

    testWidgets('nothing with no meetings', (tester) async {
      final it = made();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked));
      await settle(tester);
      expect(find.byKey(const ValueKey('meeting-shelf')), findsNothing);
      await away(tester);
    });

    testWidgets('not in simple mode', (tester) async {
      final it = made();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: meetings, simple: true));
      await settle(tester);
      expect(find.byKey(const ValueKey('meeting-shelf')), findsNothing);
      await away(tester);
    });

    testWidgets('not while searching, and back when the search is cleared', (tester) async {
      final it = made();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: meetings));
      await settle(tester);
      await tester.enterText(find.byType(EditableText), 'retro');
      await settle(tester);
      expect(find.byKey(const ValueKey('meeting-shelf')), findsNothing);
      await tester.enterText(find.byType(EditableText), '');
      await settle(tester);
      expect(find.byKey(const ValueKey('meeting-shelf')), findsOneWidget);
      await away(tester);
    });

    testWidgets('more than twelve: twelve on the shelf, and See all opens the tapes', (tester) async {
      final many = [for (var i = 0; i < 15; i += 1) makeNote('m$i', body: '# Meeting $i', createdAt: seedNow - i * hour, updatedAt: seedNow - i * hour, recordingMs: 60000)];
      final it = (library: SampleLibrary(many, clock: () => seedNow), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(const WorkspaceSheet())), asked: Asked());
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: {for (final n in many) n.id: n.createdAt}));
      await settle(tester);
      expect(find.bySemanticsLabel('Meetings, 15'), findsOneWidget);
      expect(tapesShown(tester), hasLength(meetingShelfMost));
      await tester.tap(find.byKey(const ValueKey('meeting-shelf-all')));
      await settle(tester);
      expect(it.asked.said, contains('all tapes'));
      await away(tester);
    });

    testWidgets('the meeting being recorded leads, saying so', (tester) async {
      final it = made();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: meetings, recording: 'mt-untaped'));
      await tester.pump(const Duration(milliseconds: 800));
      expect(tapesShown(tester).first, 'mt-untaped');
      expect(find.textContaining('Recording now'), findsWidgets);
      await away(tester);
    });
  });

  // Matt, 2026-10-24: "preload meeting audio on desktop for the visible cassets so hovering is instant to play".
  group('loaded ahead on a computer', () {
    final lengths = {for (final n in library()) if (n.recordingMs != null) n.id: n.recordingMs!};
    final many = [for (var i = 0; i < 12; i += 1) makeNote('m$i', body: '# Meeting $i', createdAt: seedNow - i * hour, updatedAt: seedNow - i * hour, recordingMs: 60000 + i)];
    final manyMeetings = <String, num>{for (final n in many) n.id: n.createdAt};
    final manyLengths = {for (final n in many) n.id: n.recordingMs!};

    /// The players kept for the shelf, each a fake that knows every recording in [known].
    ({TapePreviews previews, List<FakeTapePlayer> players}) previewsOf(Map<String, int> known) {
      final players = [for (var i = 0; i < tapePreviewsMost; i += 1) FakeTapePlayer(lengths: known)];
      return (previews: TapePreviews(players), players: players);
    }

    List<String> callsOf(List<FakeTapePlayer> players) => [for (final p in players) ...p.calls];
    int loads(List<FakeTapePlayer> players) => callsOf(players).where((c) => c.startsWith('load ')).length;

    /// The cassettes any of whose width the row shows, left to right.
    List<String> inView(WidgetTester tester) {
      final row = tester.getRect(find.byKey(const ValueKey('meeting-shelf-row')));
      return [
        for (final id in tapesShown(tester))
          if (tester.getRect(find.byKey(ValueKey('meeting-tape-$id'))).overlaps(row)) id,
      ];
    }

    /// The row's scroll position.
    ScrollPosition rowAt(WidgetTester tester) =>
        tester.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('meeting-shelf-row')), matching: find.byType(Scrollable))).position;

    ({SampleLibrary library, WorkspaceStore workspaces, Asked asked}) madeMany() =>
        (library: SampleLibrary(many, clock: () => seedNow), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(const WorkspaceSheet())), asked: Asked());

    /// [body] on a Mac, the platform put back after it whatever happens.
    Future<void> onMac(WidgetTester tester, Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await body();
        await away(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    Future<TestGesture> mouseOn(WidgetTester tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      return mouse;
    }

    testWidgets('the cassettes in view, and one past them, are loaded; the others are not', (tester) async {
      await onMac(tester, () async {
        final it = madeMany();
        final kept = previewsOf(manyLengths);
        await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: manyMeetings, tapePreviews: kept.previews));
        await settle(tester);
        final seen = inView(tester);
        expect(seen, isNotEmpty);
        expect(seen.length, lessThan(meetingShelfMost - 1), reason: 'a phone-wide window shows a few');
        final shown = tapesShown(tester);
        final next = shown[shown.indexOf(seen.last) + 1];
        expect(kept.previews.ready, {...seen, next});
        expect(kept.previews.held, isNot(contains(shown.last)));
        expect(loads(kept.players), seen.length + 1, reason: 'each once');
      });
    });

    testWidgets('scrolling lets go of what left the view and loads what came into it, once the row keeps still', (tester) async {
      await onMac(tester, () async {
        final it = madeMany();
        final kept = previewsOf(manyLengths);
        await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: manyMeetings, tapePreviews: kept.previews));
        await settle(tester);
        final before = kept.previews.ready;
        expect(before, contains('m0'));
        rowAt(tester).jumpTo(rowAt(tester).maxScrollExtent);
        // Still moving: nothing yet.
        await tester.pump(meetingPreviewSettle ~/ 2);
        expect(kept.previews.ready, before);
        await settle(tester);
        final seen = inView(tester);
        expect(seen, contains('m11'));
        final shown = tapesShown(tester);
        expect(kept.previews.ready, {...seen, shown[shown.indexOf(seen.first) - 1]});
        expect(kept.previews.held, isNot(contains('m0')));
        expect(callsOf(kept.players), contains('release'), reason: 'those scrolled away were let go');
      });
    });

    testWidgets('a mouse resting on one loaded ahead plays it with nothing loaded, and leaves the memos’ player alone', (tester) async {
      await onMac(tester, () async {
        final it = made();
        final kept = previewsOf(lengths);
        // A note open beside the shelf, its memo paused part of the way through on the memos' player.
        final memos = FakeTapePlayer(lengths: lengths);
        await memos.load('mt-standup');
        await memos.seek(5000);
        final memosBefore = [...memos.calls];
        await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: meetings, tapePlayer: memos, tapePreviews: kept.previews));
        await settle(tester);
        expect(kept.previews.ready, contains('mt-retro'));
        final slot = kept.players.firstWhere((p) => p.loaded == 'mt-retro');
        slot.calls.clear();
        final loaded = loads(kept.players);
        TapeArt art() => tester.widget<TapeArt>(find.descendant(of: find.byKey(const ValueKey('meeting-tape-mt-retro')), matching: find.byType(TapeArt)));
        final mouse = await mouseOn(tester);
        await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('meeting-tape-mt-retro'))));
        // The rest is still the rest: nothing plays before it ends.
        await tester.pump(meetingHoverDwell ~/ 2);
        expect(slot.calls, isEmpty);
        await tester.pump(meetingHoverDwell ~/ 2);
        await tester.pump();
        expect(slot.calls, ['play'], reason: 'played the moment the rest ended, with no load');
        expect(loads(kept.players), loaded);
        expect(art().playing, isTrue);
        await tester.pump(const Duration(milliseconds: 300));
        expect(art().positionMs, 300, reason: 'the tape winds with the player that plays');
        await mouse.moveTo(Offset.zero);
        await tester.pump(const Duration(milliseconds: 200));
        expect(slot.calls, ['play', 'pause', 'seek 0'], reason: 'stopped, and at its start again for the next rest');
        expect(art().playing, isFalse);
        expect(kept.previews.ready, contains('mt-retro'), reason: 'still loaded');
        // And again: played at once, from the start.
        await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('meeting-tape-mt-retro'))));
        await tester.pump(meetingHoverDwell);
        await tester.pump();
        expect(slot.calls.last, 'play');
        expect(art().positionMs, 0);
        expect(loads(kept.players), loaded);
        await mouse.moveTo(Offset.zero);
        await tester.pump(const Duration(milliseconds: 200));
        expect(memos.calls, memosBefore, reason: 'the memos’ player was never asked a thing');
        expect(memos.position.value, 5000);
        expect(memos.loaded, 'mt-standup');
      });
    });

    testWidgets('a recording that is not here is fetched from nowhere: its load fails once, and its hover loads as before', (tester) async {
      await onMac(tester, () async {
        final it = made();
        // The retro's recording stayed on the laptop that made it (Sync meeting recordings off there): the shelf's
        // players cannot load it. The memos' player can, standing for a copy that has come since.
        final kept = previewsOf({...lengths}..remove('mt-retro'));
        final memos = FakeTapePlayer(lengths: lengths);
        await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: meetings, tapePlayer: memos, tapePreviews: kept.previews));
        await settle(tester);
        expect(kept.previews.held, isNot(contains('mt-retro')));
        expect(kept.previews.ready, contains('mt-standup'));
        int tries() => callsOf(kept.players).where((c) => c == 'load mt-retro').length;
        expect(tries(), 1);
        // The view settling again asks no more of it.
        rowAt(tester).jumpTo(1);
        await settle(tester);
        rowAt(tester).jumpTo(0);
        await settle(tester);
        expect(tries(), 1);
        final mouse = await mouseOn(tester);
        await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('meeting-tape-mt-retro'))));
        await tester.pump(meetingHoverDwell);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
        expect(memos.calls, ['load mt-retro', 'play'], reason: 'loaded on the hover, as before');
        expect(tester.takeException(), isNull);
        await mouse.moveTo(Offset.zero);
        await tester.pump(const Duration(milliseconds: 200));
      });
    });

    testWidgets('nothing is loaded while the app is hidden, and what is in view again when it is back', (tester) async {
      await onMac(tester, () async {
        final it = made();
        final kept = previewsOf(lengths);
        await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: meetings, tapePreviews: kept.previews));
        await settle(tester);
        final before = kept.previews.ready;
        expect(before, isNotEmpty);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await settle(tester);
        expect(kept.previews.held, isEmpty);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await settle(tester);
        expect(kept.previews.ready, before);
      });
    });

    testWidgets('the shelf gone lets go of everything', (tester) async {
      await onMac(tester, () async {
        final it = made();
        final kept = previewsOf(lengths);
        await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: meetings, tapePreviews: kept.previews));
        await settle(tester);
        expect(kept.previews.held, isNotEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(kept.previews.held, isEmpty);
        for (final p in kept.players) {
          if (p.calls.isNotEmpty) expect(p.calls.last, 'release');
        }
      });
    });

    testWidgets('on a phone nothing is loaded ahead, and a hover loads as before', (tester) async {
      final it = made();
      final kept = previewsOf(lengths);
      final memos = FakeTapePlayer(lengths: lengths);
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: meetings, tapePlayer: memos, tapePreviews: kept.previews));
      await settle(tester);
      expect(kept.previews.held, isEmpty);
      expect(callsOf(kept.players), isEmpty);
      final mouse = await mouseOn(tester);
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('meeting-tape-mt-retro'))));
      await tester.pump(meetingHoverDwell);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      expect(memos.calls, ['load mt-retro', 'play']);
      await mouse.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 200));
      await away(tester);
    });

    test('which cassettes are in view: those the row shows, then one past each end', () {
      expect(meetingsInView(count: 12, offset: 0, viewport: 400, gap: 16), [0, 1, 2]);
      expect(meetingsInView(count: 12, offset: 300, viewport: 400, gap: 16), [1, 2, 3, 4, 0]);
      expect(meetingsInView(count: 3, offset: 0, viewport: 2000, gap: 16), [0, 1, 2]);
      expect(meetingsInView(count: 0, offset: 0, viewport: 400), isEmpty);
    });

    test('the previews: as many as there are players, and one lent kept until it is handed back', () async {
      final players = [for (var i = 0; i < 2; i += 1) FakeTapePlayer(lengths: const {'a': 1000, 'b': 1000, 'c': 1000})];
      final previews = TapePreviews(players);
      previews.want(['a', 'b', 'c']);
      await Future<void>.delayed(Duration.zero);
      expect(previews.ready, {'a', 'b'});
      previews.want(['c', 'a']);
      await Future<void>.delayed(Duration.zero);
      expect(previews.ready, {'a', 'c'});
      final lent = await previews.take('c');
      expect(lent, isNotNull);
      expect(await previews.take('c'), isNull, reason: 'lent already');
      // Scrolled away while it plays: kept until it is handed back, then let go.
      previews.want(['a']);
      expect(previews.held, {'a', 'c'});
      previews.done(lent!);
      expect(previews.held, {'a'});
      expect(await previews.take('zz'), isNull);
    });
  });

  group('a long title', () {
    testWidgets('stays inside the label: one line, the one size for every title, cut, centred clear of the A mark', (tester) async {
      // Matt, 2026-10-24: "make the titles on the cassetes consistent sizes don't make them smaller to fit more text".
      // A face the tests have loaded, so the widths are a real face's.
      final font = Tokens.resized(const TextStyle(fontFamily: 'Maple Mono'), 13);
      // A short one at the full size, whole.
      final short = tapeCentredTitle('Standup', font);
      expect(short.didExceedMaxLines, isFalse);
      expect(short.text!.style!.fontSize, closeTo(tapeTitleSize, 0.01));
      short.dispose();
      // A middling one at the same size, on one line.
      final middling = tapeCentredTitle('Meeting, Oct 23 11:09', font);
      expect(middling.text!.style!.fontSize, closeTo(tapeTitleSize, 0.01));
      expect(middling.computeLineMetrics(), hasLength(1));
      middling.dispose();
      // A long one at the same size and cut, no wider than its room either side of the middle.
      final words = tapeCentredTitle(longTitle, font);
      expect(words.didExceedMaxLines, isTrue);
      expect(words.text!.style!.fontSize, closeTo(tapeTitleSize, 0.01));
      expect(words.width, lessThanOrEqualTo(tapeCentredWidth));
      expect(tapeMiddle - words.width / 2, greaterThanOrEqualTo(tapeTitleLeft));
      expect((tapeLabelTop + tapeTitleRule) / 2 + words.height / 2, lessThan(tapeTitleRule));
      words.dispose();
      // One word too long for the line is cut at the edge, not run off it.
      final word = tapeCentredTitle('Supercalifragilisticexpialidociousnessmeetingnotes', font);
      expect(word.width, lessThanOrEqualTo(tapeCentredWidth));
      word.dispose();
    });

    testWidgets('and its cassette stays the shelf’s width', (tester) async {
      final it = made();
      await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: meetings), size: const Size(390, 844), ratio: 2);
      await settle(tester);
      final tape = tester.getSize(find.byKey(const ValueKey('meeting-tape-mt-planning')));
      expect(tape.width, meetingTapeWidth);
      expect(tester.takeException(), isNull);
      await away(tester);
    });
  });

  group('pictures', () {
    for (final (size, sized) in [(const Size(390, 844), 'phone'), (const Size(1200, 800), 'wide')]) {
      for (final theme in ['light', 'dark']) {
        testWidgets('the shelf under the search, $sized $theme', (tester) async {
          final it = made();
          await pumpHome(tester, Home(library: it.library, workspaces: it.workspaces, asked: it.asked, meetings: meetings, recording: null), size: size, theme: theme, ratio: 2);
          await settle(tester);
          expect(find.byKey(const ValueKey('meeting-shelf')), findsOneWidget);
          await _snap(tester, 'shelf-$sized-$theme');
          await away(tester);
        });
      }
    }
  });
}

/// The screen as it is, written to build/feature-shots/shelf/[name].png (test/organize/support.dart `snap`).
Future<void> _snap(WidgetTester tester, String name) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  final boundary = tester.binding.renderViews.first;
  final bytes = await tester.runAsync(() async {
    final layer = boundary.debugLayer! as OffsetLayer;
    final image = await layer.toImage(boundary.paintBounds);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  File('build/feature-shots/shelf/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}
