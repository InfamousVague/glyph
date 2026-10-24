import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/meeting_shelf.dart';
import 'package:ghost_md/tapes/tape_art.dart';
import 'package:glacier/glacier.dart';

import '../core/make_note.dart';
import '../support/render.dart';
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

  group('a long title', () {
    testWidgets('stays inside the label: one line, smaller before it is cut, centred clear of the A mark', (tester) async {
      // A face the tests have loaded, so the widths are a real face's.
      final font = Tokens.resized(const TextStyle(fontFamily: 'Maple Mono'), 13);
      // A short one at the full size, whole.
      final short = tapeCentredTitle('Standup', font);
      expect(short.didExceedMaxLines, isFalse);
      expect(short.text!.style!.fontSize, closeTo(tapeTitleSize, 0.01));
      short.dispose();
      // A middling one smaller, still whole, on one line.
      final middling = tapeCentredTitle('Meeting, Oct 23 11:09', font);
      expect(middling.didExceedMaxLines, isFalse);
      expect(middling.text!.style!.fontSize, lessThan(tapeTitleSize));
      expect(middling.computeLineMetrics(), hasLength(1));
      middling.dispose();
      // A long one at the smallest size and cut, no wider than its room either side of the middle.
      final words = tapeCentredTitle(longTitle, font);
      expect(words.didExceedMaxLines, isTrue);
      expect(words.text!.style!.fontSize, closeTo(tapeTitleMinSize, 0.01));
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
