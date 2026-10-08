import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle, sameTitle;
import 'package:glacier/glacier.dart';

import '../sidebar/support.dart';

export '../sidebar/support.dart' show away, near, pumpPage, settle;
export '../support/render.dart' show loadAppFonts, shot;

/// The moment the web page's pictures were taken at (tool/book_reference.mjs `NOW`): a Thursday afternoon.
final DateTime probeNow = DateTime(2026, 10, 8, 15, 30);

String _two(int n) => n.toString().padLeft(2, '0');

/// An entry written at that wall clock, with those words, named by the minute (the web tests' `entryAt`).
Note entryAt(int y, int m, int d, int h, int min, [String words = 'Words.']) {
  final title = '$y-${_two(m)}-${_two(d)} ${_two(h)}.${_two(min)}';
  final at = DateTime(y, m, d, h, min).millisecondsSinceEpoch;
  return Note(id: 'e-$title', body: '---\ntitle: "$title"\ndate: $y-${_two(m)}-${_two(d)}T${_two(h)}:${_two(min)}\n---\n# Day\n\n**${_two(h)}:${_two(min)}** $words', createdAt: at, updatedAt: at);
}

/// The library the web page was measured over (tool/book_reference.mjs): a notebook with a preface, a nested page,
/// a page not written and a canvas; a notebook with a key and a ticket; a journal of five months and a page planned.
class ProbeLibrary {
  static const String book = '---\ntitle: "Field guide"\nbook: true\n---\n# Field guide\n\nWhat lives on the **coast path**, a page each.\n\n- [[Introduction]]\n- [[Trees]]\n  - [[Oaks]]\n- [[Birds]]\n- [[Route map]]\n\nSee also the tide tables.\n';
  static const String keyed = '---\ntitle: "Ghost.md"\nbook: true\nkey: GHO\n---\n# Ghost.md\n\n- [[Fix the login loop]]\n- [[Write the docs]]\n';
  static final List<Note> entries = [
    entryAt(2026, 10, 8, 9, 12, 'Coffee on the step before anyone was up, and the long list for the week written out.'),
    entryAt(2026, 10, 7, 21, 40, 'Dinner with Sam.'),
    entryAt(2026, 10, 7, 8, 10, 'Rain.'),
    entryAt(2026, 9, 28, 14, 5, 'Walked along the river after lunch.'),
    entryAt(2026, 8, 30, 10, 0, 'Packed the car.'),
    entryAt(2026, 7, 15, 9, 0),
    entryAt(2026, 6, 15, 9, 0),
  ];
  static final String journal =
      '---\ntitle: "Diary"\nbook: true\njournal: true\ntemplate: ${jsonEncode('# {{date}}\n\n**{{time}}** ')}\n---\n# Diary\n\n${[for (final e in entries.reversed) '- [[${noteTitle(e.body)}]]'].join('\n')}\n- [[Packing list]]\n';

  static Note _note(String id, String body) => Note(id: id, body: body, createdAt: 0, updatedAt: 0);

  static final List<Note> notes = [
    _note('book', book),
    _note('intro', '# Introduction\n\nStart here. The path runs north from the harbour.\n'),
    _note('trees', '# Trees\n\nThe wind bends them all one way.\n\n- Oak\n- Ash\n'),
    _note('oaks', '# Oaks\n\nOld ones by the wall.\n'),
    _note('map', '---\ntitle: "Route map"\n---\n{"nodes":[],"edges":[]}'),
    _note('rivers', '# Rivers\n\nTwo of them.\n'),
    _note('keyed', keyed),
    _note('t1', '---\ntype: ticket\nid: GHO-12\nstatus: In progress\n---\n# Fix the login loop\n'),
    _note('t2', '# Write the docs\n'),
    _note('diary', journal),
    ...entries,
  ];

  static Note? titled(String title) => notes.where((n) => sameTitle(noteTitle(n.body), title)).firstOrNull;
  static bool known(String title) => titled(title) != null;
  static String? bodyOf(String title) => titled(title)?.body;

  /// Every note's title but a journal's entries, as the page's picker is handed them (App.tsx `pageTitles`).
  static List<String> titles() => [for (final n in notes) if (!n.id.startsWith('e-')) noteTitle(n.body)];
}

/// What the web page measured for one page at one width (test/book_ui/fixtures/`name`.json, written by
/// tool/book_reference.mjs): each named thing's rectangles, moved so the view's own box starts at the corner.
class Measured {
  Measured._(this._things, this.origin);

  /// [root] names the view's own box in the fixture; a fixture that did not measure it takes its corner [from]
  /// another of the same page.
  factory Measured.load(String name, {String root = 'book', String? from}) {
    Map<String, List<Map<String, dynamic>>> read(String file) =>
        (jsonDecode(File('test/book_ui/fixtures/$file.json').readAsStringSync()) as Map<String, dynamic>).map((key, value) => MapEntry(key, (value as List).cast<Map<String, dynamic>>()));
    final raw = read(name);
    final first = (from == null ? raw : read(from))[root]!.first;
    return Measured._(raw, Offset((first['x'] as num).toDouble(), (first['y'] as num).toDouble()));
  }

  final Map<String, List<Map<String, dynamic>>> _things;
  final Offset origin;

  int count(String name) => _things[name]?.length ?? 0;

  /// The [at]th thing called [name]: left, top, width, height, from the view's corner.
  List<double> rect(String name, [int at = 0]) {
    final thing = _things[name]![at];
    double n(String key) => (thing[key] as num).toDouble();
    return [n('x') - origin.dx, n('y') - origin.dy, n('w'), n('h')];
  }

  String text(String name, [int at = 0]) => _things[name]![at]['text'] as String;
}

/// [child] at the top of a page that scrolls, on the page's paper, under the app's theme: the note's page, as far
/// as a notebook's view knows of it.
Future<void> pumpView(WidgetTester tester, Widget child, {Size size = const Size(390, 844), String theme = 'light', ScrollController? scroll}) => pumpPage(
      tester,
      BackScope(
        child: Builder(
          builder: (context) => ColoredBox(
            color: context.tokens.color('glacier-bg'),
            child: SingleChildScrollView(controller: scroll, child: child),
          ),
        ),
      ),
      size: size,
      theme: theme,
    );

/// The rectangle of what [finder] finds, on the screen.
Rect rectOf(WidgetTester tester, Finder finder) => tester.getRect(finder);

/// The kit's button that says [label] to a screen reader (`button(label)` of the web's test/render.tsx).
Finder button(String label) => find.byWidgetPredicate((widget) => widget is GlacierPressable && widget.semanticLabel == label, description: 'the button "$label"');

/// Whether the button that says [label] takes no press (`button(label).disabled`).
bool disabled(WidgetTester tester, String label) => tester.widget<GlacierPressable>(button(label)).onPressed == null;

/// A tap on the button that says [label], and the frame after it.
Future<void> press(WidgetTester tester, String label) async {
  await tester.ensureVisible(button(label));
  await tester.pump();
  await tester.tap(button(label));
  await tester.pump();
}

/// How long a grip is held before its row lifts, and a little.
const Duration heldLong = Duration(milliseconds: 230);

/// A grip pressed and held with a mouse, moved [by] down the page and let go there (`dragGrip`).
Future<void> dragGrip(WidgetTester tester, Finder grip, double by) async {
  final from = tester.getCenter(grip);
  final mouse = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await tester.pump(heldLong);
  await mouse.moveTo(from + Offset(0, by));
  await tester.pump();
  await mouse.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}
