import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/academy/academy_screen.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/marks_plugin.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/shell/root_stamps.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

export '../support/render.dart';

/// What a test sees of the Academy on the screen: the calls it made out, and the haptics it fired.
class Shown {
  int done = 0;
  int cheatSheet = 0;
  final List<HapticKind> haptics = [];
}

/// A device that has kept nothing but [kept], and the Marks plugin switched on.
Registry freshDevice({Set<String>? learned, Map<String, String> kept = const {}}) {
  useStored(MemoryStored({...kept, if (learned != null) 'glyph-academy': jsonEncode(learned.toList())}));
  final registry = createRegistry(const [marksPlugin], store: MemorySwitches());
  usePlugins(registry);
  return registry;
}

/// The Academy alone on a phone's screen, under the app's theme.
Future<Shown> showAcademy(WidgetTester tester, {String theme = 'light', Size size = const Size(390, 844)}) async {
  final shown = Shown();
  await pumpApp(
    tester,
    size: size,
    prefs: AppPreferences(theme: theme),
    home: HapticsProvider(
      enabled: true,
      impl: ([kind = HapticKind.light]) => shown.haptics.add(kind),
      // As the shell lays it: the Academy takes the whole window, with no tab bar over it (`data-tabs` off).
      child: Builder(
        builder: (context) => RootStamps(
          sheet: context.tokens.sheet,
          stamps: const {'tabs': null},
          child: AcademyScreen(onDone: () => shown.done += 1, onCheatSheet: () => shown.cheatSheet += 1),
        ),
      ),
    ),
  );
  await tester.pump();
  return shown;
}

/// Takes the screen away as a test ends: pumpApp turned the shadows on for a picture, and the binding wants its own
/// switch back.
Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

Finder key(String name) => find.byKey(ValueKey(name));

/// The words of the card's title (the page's `h2`).
String title(WidgetTester tester) => tester.widget<Text>(key('academy-title')).data!;

/// Presses the button whose key is [name], brought into view first, and lets the page settle.
Future<void> press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

/// Past a press's animations, in frames; never `pumpAndSettle`, since an effect's ticker never rests.
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Types [text] into the lesson's field the way a keyboard does: straight into the field, which then tells the screen.
Future<void> typeInto(WidgetTester tester, String text) async {
  await tester.ensureVisible(key('playground-field'));
  await tester.enterText(find.descendant(of: key('playground-field'), matching: find.byType(EditableText)), text);
  await settle(tester, 4);
}

/// What is in the lesson's field.
String field(WidgetTester tester) => tester.widget<EditableText>(find.descendant(of: key('playground-field'), matching: find.byType(EditableText))).controller.text;

/// The face Chromium on a Mac draws a `<button>` in, loaded from the Mac's own fonts for the rows the page left in
/// it (academy_screen.dart's header). False where this machine has no such file.
Future<bool> loadButtonFace() async {
  const files = ['/System/Library/Fonts/Supplemental/Arial.ttf', '/System/Library/Fonts/Supplemental/Arial Bold.ttf'];
  if (!files.every((file) => File(file).existsSync())) return false;
  final loader = FontLoader('Arial');
  for (final file in files) {
    loader.addFont(File(file).readAsBytes().then((bytes) => ByteData.view(Uint8List.fromList(bytes).buffer)));
  }
  await loader.load();
  return true;
}

/// What the web page measured (fixtures/web_academy.mjs): for each named thing its rectangles and words.
class Reference {
  Reference(String name) : _json = jsonDecode(File('test/academy/fixtures/$name.json').readAsStringSync()) as Map<String, Object?>;
  final Map<String, Object?> _json;

  List<({Rect rect, String text})> of(String thing) => [
    for (final each in (_json[thing] as List? ?? const []).cast<Map<String, Object?>>())
      (rect: Rect.fromLTWH((each['x']! as num).toDouble(), (each['y']! as num).toDouble(), (each['w']! as num).toDouble(), (each['h']! as num).toDouble()), text: each['text']! as String),
  ];
}

/// Holds a screen's rectangles to the page's, to half a pixel, and says every one that is off at once.
class Held {
  Held(this.reference, {this.by = 0.5});
  final Reference reference;
  final double by;
  Offset shift = Offset.zero;
  final List<String> off = [];
  int checked = 0;

  /// The page and the screen are laid over one another where [thing] is on each: the page was drawn with no status
  /// bar over it, the screen under a test's 36 px one.
  void anchor(String thing, Rect here) => shift = reference.of(thing).first.rect.topLeft - here.topLeft;

  /// [got] against the page's [thing]: [dims] are the sides compared, `x`, `y`, `w` and `h`.
  void check(String thing, List<Rect> got, {String dims = 'xywh', int from = 0}) {
    final want = reference.of(thing);
    if (got.isEmpty) off.add('$thing: nothing on the screen');
    for (var i = 0; i < got.length; i++) {
      final at = from + i;
      if (at >= want.length) {
        off.add('$thing[$at]: not on the page');
        continue;
      }
      final page = want[at].rect, here = got[i].shift(shift);
      final misses = [
        if (dims.contains('x') && (page.left - here.left).abs() > by) 'x ${here.left.toStringAsFixed(2)} for ${page.left}',
        if (dims.contains('y') && (page.top - here.top).abs() > by) 'y ${here.top.toStringAsFixed(2)} for ${page.top}',
        if (dims.contains('w') && (page.width - here.width).abs() > by) 'w ${here.width.toStringAsFixed(2)} for ${page.width}',
        if (dims.contains('h') && (page.height - here.height).abs() > by) 'h ${here.height.toStringAsFixed(2)} for ${page.height}',
      ];
      checked += 1;
      if (misses.isNotEmpty) off.add('$thing[$at] "${want[at].text}": ${misses.join(', ')}');
    }
  }

  void done() => expect(off, isEmpty, reason: 'of $checked rectangles, off the page\'s by more than $by:\n${off.join('\n')}');
}

/// Where each thing a finder finds is on the screen, scrolled or not.
List<Rect> rectsOf(WidgetTester tester, Finder finder) => [for (final element in finder.evaluate()) tester.getRect(find.byElementPredicate((e) => identical(e, element)))];
