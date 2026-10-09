import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/app/widgets.dart';
import 'package:ghost_md/art/ghost.dart';
import 'package:ghost_md/capture/ui/capture_cards.dart';
import 'package:ghost_md/capture/ui/capture_screen.dart';
import 'package:ghost_md/capture/ui/live_page.dart';
import 'package:ghost_md/capture/ui/say_card.dart';
import 'package:ghost_md/core/preferences.dart' show preferences;
import 'package:ghost_md/shell/header_pane.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';
import 'support/harness.dart';

/// The recorder held to the page: the screen at rest, hearing, a command's chip, the confirm card and the landing,
/// each with the scripted voice speaking through the engine's own Whisper path over `SimulatedBackend`, and its
/// rectangles asserted to half a pixel against what the web app's page gave in Chromium
/// (`test/capture_ui/reference/capture_reference.mjs`, which wrote `fixtures/<state>-<size>.json` and the pictures
/// beside them). A picture of each, light and dark, is written to `shots/` to be looked at beside the page's.
///
/// The states are the script's: the same `simulate` and `say` queries, the same three notes, read at the same moment
/// (a line of the page, a chip's words), with ghostly typing off as the script had it, since a letter half out of
/// its smoke is not a moment two engines share. The page had no status bar and no tab bar over it, so neither is
/// given here.
///
/// One thing is allowed for. `--app-line`, the ring round the chip and the confirm card, is 1.5px. A phone's browser
/// draws that as three device pixels at 2, and so does this port (sheet/css.dart `snapBorder`); the measuring
/// Chromium, whose device scale is emulated, floors it to one CSS pixel. So a ringed box is a pixel taller here than
/// in the fixture, and what stands over it a pixel higher: each case says which rectangles that moves (`ringed`),
/// and they are held to half a pixel of where the thicker ring puts them.
///
/// What is not held, and why:
/// - a rectangle's width where the page's element is a block and this port's is its words (the hint, a card's
///   lines): its place and height are held;
/// - the ghost's width: the page's element is the picture, here its box is the column and the picture is centred in
///   it;
/// - the lines of the note at the wide size, where the page's editor is given a measure this port's column does not
///   have yet (stage 10, the wide layouts): the recorder's own lines, cards and buttons are held at both sizes.
/// Where the thicker ring puts a rectangle, from where the fixture has it: see the library's comment.
class Ring {
  const Ring({this.dx = 0, this.dy = 0, this.dw = 0, this.dh = 0});

  /// A ringed box that hugs its words and stands on what is under it: half a pixel wider each side, a pixel taller.
  static const Ring box = Ring(dx: -0.5, dy: -1, dw: 1, dh: 1);

  final double dx, dy, dw, dh;
}

void main() {
  setUpAll(loadAppFonts);

  const notes = [
    ('attackfm', '# AttackFM\n\nThe radio app.\n\n- Fix the seek bar\n- Update the readme\n'),
    ('house', '# House TODOs\n\n- [ ] Fix the gate\n- [x] Call the plumber\n- [ ] Paint the fence\n'),
    ('shopping', '# Shopping list\n\n- Oat milk\n- Eggs\n- Coffee\n'),
  ];

  Map<String, Object?> fixture(String state, Size size) =>
      jsonDecode(File('test/capture_ui/fixtures/$state-${size.width.round()}x${size.height.round()}.json').readAsStringSync()) as Map<String, Object?>;

  /// The recorder open on [script], on a window of [size], with the page's three notes.
  Future<Capture> speak(WidgetTester tester, Map<String, String> script, Size size) async {
    final capture = Capture(tester, script: script)..insets = EdgeInsets.zero;
    capture.prefs = capture.prefs.copyWith(wisp: false, ripples: false);
    for (final (id, body) in notes) {
      capture.notes.create(id, body);
    }
    await capture.open(size: size);
    return capture;
  }

  /// The script's clock: 40 ms at a time until [holds], then two steps more, as the page's was run.
  Future<void> run(Capture capture, bool Function() holds) async {
    for (var waited = 0; waited < 20000 && !holds(); waited += 40) {
      await capture.tester.pump(const Duration(milliseconds: 40));
    }
    expect(holds(), isTrue, reason: 'the script never came to the moment the page was read at');
    capture.freeze();
    await capture.tester.pump(const Duration(milliseconds: 40));
  }

  /// The entrances over, so a card stands where it rests.
  Future<void> rest(WidgetTester tester) async {
    for (var i = 0; i < 5; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> ghost(WidgetTester tester) async {
    final found = find.descendant(of: find.byType(Ghost), matching: find.byType(Image));
    if (found.evaluate().isEmpty) return;
    await tester.runAsync(() => precacheImage(tester.widget<Image>(found.first).image, tester.element(found.first)));
    await tester.pump();
  }

  /// A picture in each theme, written beside the page's own for the eye.
  Future<void> pictures(Capture capture, String name) async {
    final tester = capture.tester;
    await ghost(tester);
    await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/$name-light.png'));
    preferences.value = preferences.value.copyWith(theme: 'dark');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/$name-dark.png'));
    await capture.close();
  }

  /// What the page gave for [names], against this screen's rectangles.
  void held(Map<String, Object?> web, Map<String, Rect?> here, {Set<String> placeOnly = const {}, Map<String, Ring> ringed = const {}, double within = 0.5}) {
    final rects = web['rects']! as Map<String, Object?>;
    final checked = <String>[];
    for (final MapEntry(key: name, value: rect) in here.entries) {
      final page = rects[name] as Map<String, Object?>?;
      expect(page, isNotNull, reason: 'the page has no $name');
      expect(rect, isNotNull, reason: 'this screen has no $name');
      final ring = ringed[name] ?? const Ring();
      final x = (page!['x']! as num).toDouble() + ring.dx, y = (page['y']! as num).toDouble() + ring.dy, w = (page['width']! as num).toDouble() + ring.dw, h = (page['height']! as num).toDouble() + ring.dh;
      final why = '$name: page ${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)} ${w.toStringAsFixed(2)} x ${h.toStringAsFixed(2)}; here ${rect!.left.toStringAsFixed(2)}, ${rect.top.toStringAsFixed(2)} ${rect.width.toStringAsFixed(2)} x ${rect.height.toStringAsFixed(2)}';
      expect(rect.top, closeTo(y, within), reason: why);
      expect(rect.height, closeTo(h, within), reason: why);
      if (!placeOnly.contains(name)) {
        expect(rect.left, closeTo(x, within), reason: why);
        expect(rect.width, closeTo(w, within), reason: why);
      } else if (name != 'ghost') {
        expect(rect.left, closeTo(x, within), reason: why);
      }
      checked.add(name);
    }
    expect(checked, isNotEmpty);
  }

  for (final size in const [Size(390, 844), Size(1200, 800)]) {
    final at = '${size.width.round()}x${size.height.round()}';
    final phone = size.width < 600;

    Rect? of(WidgetTester tester, Finder finder) => finder.evaluate().isEmpty ? null : tester.getRect(finder.first);

    /// A card's own box: the widget's, less the margin under it (`margin: 0 0 var(--glacier-space-3)`).
    Rect? card(WidgetTester tester, Finder finder) {
      final rect = of(tester, finder);
      if (rect == null) return null;
      final space = tester.element(finder.first).tokens.space(3);
      return Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom - space);
    }

    /// The recorder's own frame: the top line, its counter, the buttons.
    Map<String, Rect?> frame(WidgetTester tester) => {
          'top': of(tester, find.byType(HeaderPane)),
          'where': of(tester, find.byKey(CaptureScreen.whereKey)),
          'counter': of(tester, find.byKey(CaptureScreen.counterKey)),
          'discard': of(tester, find.byKey(CaptureScreen.discardKey)),
          'done': of(tester, find.byKey(CaptureScreen.doneKey)),
        };

    Map<String, Rect?> lines(WidgetTester tester, int count) {
      final rects = tester.state<LivePageState>(find.byType(LivePage)).lineRects;
      return {for (var i = 0; i < count; i += 1) 'line$i': i < rects.length ? rects[i] : null};
    }

    group('the recorder at $at', () {
      testWidgets('at rest: the line at the top, the empty page, the ghost, the hint, the card of things to say, and the buttons', (tester) async {
        final web = fixture('rest', size);
        final capture = await speak(tester, const {'simulate': 'say', 'say': 'Hello there.'}, size);
        await run(capture, () => capture.hasSayCard && capture.textOf(capture.sayCard).contains('Shopping list'));
        await rest(tester);
        expect(capture.isWhere('New note'), isTrue);
        held(web, {
          ...frame(tester),
          'livePage': of(tester, find.byType(LivePage)),
          'line0': tester.state<LivePageState>(find.byType(LivePage)).lineRects.firstOrNull,
          'ghost': of(tester, find.byType(Ghost)),
          'pageHint': of(tester, find.text('Tap Done to stop.')),
          'sayCard': card(tester, find.byType(SayCard)),
          'sayTitle': of(tester, find.text('THINGS TO SAY')),
          'sayLine0': of(tester, find.textContaining('Bullet point', findRichText: true)),
          'sayLine1': of(tester, find.textContaining('The next item is', findRichText: true)),
          'sayLine2': of(tester, find.textContaining('to Shopping list”', findRichText: true)),
          'sayLine3': of(tester, find.textContaining('Move this to Shopping list', findRichText: true)),
        }, placeOnly: const {
          'ghost',
          'pageHint',
        });
        await pictures(capture, 'rest-$at');
      });

      testWidgets('hearing: a title, a to-do and the phrase still being guessed, on the note’s own page', (tester) async {
        final web = fixture('hearing', size);
        final capture = await speak(tester, const {'simulate': ''}, size);
        await run(capture, () => capture.page().endsWith('For the drive we want'));
        await rest(tester);
        expect(capture.page(), '# Weekend trip\n\n- [ ] Book the cabin by Friday and the deposit is 200 dollars\n\nFor the drive we want');
        held(web, {
          ...frame(tester),
          'livePage': of(tester, find.byType(LivePage)),
          if (phone) ...lines(tester, 5),
        });
        await pictures(capture, 'hearing-$at');
      });

      testWidgets('a command being heard: the outlined chip with its dots, and its words kept off the page', (tester) async {
        final web = fixture('chip', size);
        final capture = await speak(tester, const {'simulate': 'say', 'say': 'Milk and eggs.|Hey Ghost.|Add bin bags to shopping list.'}, size);
        await run(capture, () => capture.screenText.contains('Hey Ghost : Add bin bags') || capture.screenText.contains('Hey Ghost: Add bin bags'));
        await rest(tester);
        expect(capture.page(), isNot(contains('bin bags')));
        held(web, {
          ...frame(tester),
          'livePage': of(tester, find.byType(LivePage)),
          'route': of(tester, find.byKey(const ValueKey('route-chip-hearing'))),
          if (phone) ...lines(tester, 1),
        }, ringed: const {
          'route': Ring.box,
          'livePage': Ring(dh: -1),
        });
        await pictures(capture, 'chip-$at');
      });

      testWidgets('the take moved: the filled chip, the note named in the line at the top, and Not this note', (tester) async {
        final web = fixture('chip-moved', size);
        final capture = await speak(tester, const {'simulate': 'route'}, size);
        await run(capture, () => capture.isWhere('Adding to “Shopping list”') && capture.page().contains('good coffee'));
        await rest(tester);
        expect(capture.screenText, contains('Now on'));
        held(web, {
          ...frame(tester),
          'newNote': of(tester, find.byKey(CaptureScreen.actionKey)),
          'livePage': of(tester, find.byType(LivePage)),
          'route': of(tester, find.byKey(const ValueKey('route-chip-moved'))),
          if (phone) ...lines(tester, 7),
        }, ringed: const {
          'route': Ring.box,
          'livePage': Ring(dh: -1),
        });
        await pictures(capture, 'chip-moved-$at');
      });

      testWidgets('the confirm card after Done: what the command will do, Cancel and Add', (tester) async {
        final web = fixture('confirm', size);
        final capture = await speak(tester, const {'simulate': 'say', 'say': 'Add to my note labeled Shopping list a list with sunscreen and bin bags.'}, size);
        await run(capture, () => capture.backend.said.isNotEmpty);
        await tester.pump(const Duration(milliseconds: 1000));
        await capture.done();
        await capture.until(() => capture.hasCard('Add to Shopping list'));
        await rest(tester);
        final inCard = find.byType(ConfirmCard<Object>, skipOffstage: false).evaluate().isEmpty ? capture.card('Add to Shopping list') : find.byType(ConfirmCard<Object>);
        held(web, {
          ...frame(tester),
          'livePage': of(tester, find.byType(LivePage)),
          'ghost': of(tester, find.byType(Ghost)),
          'pageHint': of(tester, find.text('Tap Done to stop.')),
          'confirm': card(tester, inCard),
          'confirmHeading': of(tester, find.text('ADD TO SHOPPING LIST')),
          'confirmLine0': of(tester, find.text('Sunscreen')),
          'confirmLine1': of(tester, find.text('Bin bags')),
          'confirmDetail': of(tester, find.text('In its list')),
          'confirmCancel': of(tester, find.widgetWithText(AppWord, 'Cancel')),
          'confirmAction': of(tester, find.widgetWithText(AppPill, 'Add')),
        }, placeOnly: const {
          'ghost',
          'pageHint',
          'confirmLine0',
          'confirmLine1',
          'confirmDetail',
        }, ringed: const {
          'livePage': Ring(dh: -1),
          'ghost': Ring(dy: -1),
          'pageHint': Ring(dy: -1),
          'confirm': Ring(dy: -1, dh: 1),
          'confirmHeading': Ring(dy: -0.5, dx: 0.5, dw: -1),
          'confirmLine0': Ring(dy: -0.5, dx: 0.5, dw: -1),
          'confirmLine1': Ring(dy: -0.5, dx: 0.5, dw: -1),
          'confirmDetail': Ring(dy: -0.5, dx: 0.5, dw: -1),
          'confirmCancel': Ring(dy: -0.5, dx: 0.5),
          'confirmAction': Ring(dy: -0.5, dx: -0.5),
        });
        await pictures(capture, 'confirm-$at');
      });

      testWidgets('the landing: a one-shot’s line arriving under its note’s last lines, with a tick, and the chip', (tester) async {
        final web = fixture('landing', size);
        final capture = await speak(tester, const {'simulate': 'say', 'say': 'Quick thought before I forget.|Hey Ghost, add ship the APK to AttackFM.|And more words.'}, size);
        await run(capture, () => find.byType(ListLanding).evaluate().isNotEmpty);
        await rest(tester);
        await rest(tester);
        held(web, {
          ...frame(tester),
          'landing': card(tester, find.byType(ListLanding)),
          'landingUndo': of(tester, find.widgetWithText(AppWord, 'Not this note')),
          'contextTitle': of(tester, find.text('ATTACKFM')),
          'contextLine0': of(tester, find.text('Fix the seek bar')),
          'contextLine1': of(tester, find.text('Update the readme')),
          'route': of(tester, find.byKey(const ValueKey('route-chip-added'))),
        }, placeOnly: const {
          'contextTitle',
          'contextLine0',
          'contextLine1',
        }, ringed: const {
          'route': Ring.box,
          'landing': Ring(dy: -1),
          'landingUndo': Ring(dy: -1),
          'contextTitle': Ring(dy: -1),
          'contextLine0': Ring(dy: -1),
          'contextLine1': Ring(dy: -1),
        });
        await pictures(capture, 'landing-$at');
      });
    });
  }

  // The Fold opened: a window of 704 x 933 at 2.625, where the page was read in the Tauri app itself, beside this
  // port on the same emulator (`fixtures/rest-704x933.json` says how). A line of `line-height: normal` is rounded
  // there in the phone's own pixels, a line of 1.35 is 18.45px, and the status bar is the whole 61px a WebView
  // makes of 159 device pixels: the top line's words stood two device pixels high and the card's foot five short
  // before each was the page's.
  group('the recorder on the Fold opened (704 x 933 at 2.625)', () {
    testWidgets('at rest stands where the page has it in the Tauri app on the same window', (tester) async {
      const size = Size(704, 933.33);
      final web = jsonDecode(File('test/capture_ui/fixtures/rest-704x933.json').readAsStringSync()) as Map<String, Object?>;
      final capture = Capture(tester, script: const {'simulate': 'say', 'say': 'Hello there.'})
        ..insets = const EdgeInsets.only(top: 61)
        ..ratio = 2.625
        ..measuredAt = 2.625;
      capture.prefs = capture.prefs.copyWith(wisp: false, ripples: false);
      for (final (id, body) in notes) {
        capture.notes.create(id, body);
      }
      await capture.open(size: size, offersMeeting: true, theme: 'dark');
      await run(capture, () => capture.hasSayCard && capture.textOf(capture.sayCard).contains('Shopping list'));
      await rest(tester);

      Rect? of(Finder finder) => finder.evaluate().isEmpty ? null : tester.getRect(finder.first);
      final say = of(find.byType(SayCard))!;
      final space = tester.element(find.byType(SayCard)).tokens.space(3);
      held(web, {
        'top': of(find.byType(HeaderPane)),
        'where': of(find.byKey(CaptureScreen.whereKey)),
        'counter': of(find.byKey(CaptureScreen.counterKey)),
        'discard': of(find.byKey(CaptureScreen.discardKey)),
        'done': of(find.byKey(CaptureScreen.doneKey)),
        'livePage': of(find.byType(LivePage)),
        'line0': tester.state<LivePageState>(find.byType(LivePage)).lineRects.firstOrNull,
        'ghost': of(find.byType(Ghost)),
        'pageHint': of(find.text('Tap Done to stop.')),
        'sayCard': Rect.fromLTRB(say.left, say.top, say.right, say.bottom - space),
        'sayTitle': of(find.text('THINGS TO SAY')),
        'sayLine0': of(find.textContaining('Bullet point', findRichText: true)),
        'sayLine1': of(find.textContaining('The next item is', findRichText: true)),
        'sayLine2': of(find.textContaining('to Shopping list”', findRichText: true)),
        'sayLine3': of(find.textContaining('Move this to Shopping list', findRichText: true)),
        'sayFoot': of(find.widgetWithText(AppWord, 'Meeting instead')),
      }, placeOnly: const {
        // The page's are blocks the width of their column and these are their words; the hint's words are the
        // side key's on the page and Done's here, a test's recorder having no phone under it.
        'ghost',
        'pageHint',
        'where',
        'counter',
        'sayTitle',
        'sayLine0',
        'sayLine1',
        'sayLine2',
        'sayLine3',
      });
      await capture.close();
    });
  });
}
