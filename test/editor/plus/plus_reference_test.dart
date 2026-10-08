// The + and its list held to the web page: every case test/editor/plus/fixtures/reference.mjs measured in Chromium
// (the web `Editor` with its + and `AddList`, light and dark) drawn here the same way, and the +'s box and its
// drawing's, the card's, each row's, its icon's, its words' and its chevron's, a step's title and field and the
// line that says nothing was found, compared with the page's to half a pixel. Each case's picture is written to
// shots/ to be looked at beside the page's own (fixtures/<name>.png).
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/app_icon.dart';
import 'package:ghost_md/art/icons.dart';
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/editor/plus/plus.dart';
import 'package:ghost_md/editor/view/line.dart';

import 'support.dart';

/// How far a rectangle may be from the page's, in logical pixels.
const double tolerance = 0.5;

/// The clock reference.mjs held the page at.
DateTime clock() => DateTime(2026, 9, 28, 14, 5);

/// The five effects the web app's marks plugin has on (plugins/marks/index.tsx), as its registry hands them over.
const List<PlusEffect> effects = <PlusEffect>[
  PlusEffect(name: 'Heat', delimiter: '🔥🔥', cue: 'heated', icon: Lucide.flame),
  PlusEffect(name: 'Frost', delimiter: '❄️❄️', cue: 'frosted', icon: Lucide.snowflake),
  PlusEffect(name: 'Wave', delimiter: '🌊🌊', cue: 'wavy'),
  PlusEffect(name: 'Shimmer', delimiter: '✨✨', cue: 'shimmering', icon: Lucide.sparkles),
  PlusEffect(name: 'Haunt', delimiter: '👻👻', cue: 'haunted', icon: Lucide.ghost),
];

/// What the page's list was given for a case: everything a browser can do, less what the case leaves out.
AddConfig configOf(Map<String, dynamic> json) {
  final bare = json['bare'] as bool;
  return AddConfig(
    onPicture: bare ? null : () {},
    onPlace: bare ? null : () {},
    onVideo: json['video'] as bool ? () {} : null,
    titles: bare ? null : () => const <String>['Lisbon', 'Lisbon, day two', 'Porto'],
    canvases: bare ? null : () => const <String>['Cabin weekend'],
    own: 'Lisbon, day two',
    localOnly: json['localOnly'] as bool,
    effects: effects,
    boards: true,
    databases: true,
    tickets: true,
    blanks: true,
  );
}

/// The letters of a text as the page measures a range of them: from the first line's start to the longest line's
/// end, every line down.
Rect lettersOf(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(find.descendant(of: text, matching: find.byType(RichText)));
  // The longest line without the space a line ends in, which hangs past its end on the page too.
  final painter = TextPainter(text: paragraph.text, textDirection: TextDirection.ltr)..layout(maxWidth: paragraph.size.width);
  final width = painter.computeLineMetrics().map((line) => line.width).reduce((a, b) => a > b ? a : b);
  painter.dispose();
  return MatrixUtils.transformRect(paragraph.getTransformTo(null), Rect.fromLTWH(0, 0, width, paragraph.size.height));
}

Finder get rowViews => find.byWidgetPredicate((widget) => widget.runtimeType.toString() == '_RowView');
Finder within(Finder of, Finder matching) => find.descendant(of: of, matching: matching);

void main() {
  setUpAll(loadAppFonts);

  final only = Platform.environment['PLUS_CASE'];
  final names = Directory('test/editor/plus/fixtures').listSync().whereType<File>().where((f) => f.path.endsWith('.json')).map((f) => f.uri.pathSegments.last.replaceAll('.json', '')).toList()..sort();
  for (final name in names) {
    if (only != null && only.isNotEmpty && !name.contains(only)) continue;
    plusTest('$name: the +, the card and its rows where the page has them', (tester) async {
      final json = fixture(name);
      final controller = PlusController();
      final view = editorOf(json['doc'] as String, controller.extension);
      await pumpPlus(tester, view, controller: controller, config: configOf(json), theme: json['theme'] as String, clock: clock, coarse: true);
      await tester.pump(const Duration(milliseconds: 700));
      final plus = plusOf(view);
      final button = find.byType(PlusButton);
      final problems = <String>[];
      var worst = 0.0;
      void hold(String what, Rect? own, Object? page) {
        if (page == null) {
          if (own != null) problems.add('$what: here $own, not on the page');
          return;
        }
        final want = rectOf(page);
        if (own == null) {
          problems.add('$what: not here, the page $want');
          return;
        }
        final off = apart(own, want);
        if (off > worst) worst = off;
        if (off > tolerance) problems.add('$what: $own, the page $want (${off.toStringAsFixed(2)})');
      }

      // The lines the + is measured against.
      final lines = tester.renderObjectList<RenderEditorLine>(find.byType(EditorLine)).toList()..sort((a, b) => a.from - b.from);
      final wantLines = (json['lines'] as List).cast<Map<String, dynamic>>();
      expect(lines.length, wantLines.length);

      // Opened as the page's was.
      final open = json['open'] as String?;
      if (open == 'slash') {
        expect(sendKey(view, LogicalKeyboardKey.slash, character: '/'), isTrue);
      } else if (open != null) {
        await tester.tap(button, kind: open == 'pointer' ? PointerDeviceKind.mouse : PointerDeviceKind.touch);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      for (final step in (json['steps'] as List).cast<String>()) {
        await tester.tap(find.text(step).hitTestable());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      }
      for (final key in (json['keys'] as List).cast<String>()) {
        expect(sendKey(view, key == 'ArrowDown' ? LogicalKeyboardKey.arrowDown : LogicalKeyboardKey.arrowUp), isTrue);
        await tester.pump(const Duration(milliseconds: 60));
      }
      final typed = json['type'] as String?;
      if (typed != null) {
        await tester.enterText(find.byType(EditableText), typed);
        await tester.pump(const Duration(milliseconds: 120));
      }
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();

      // The +.
      final wantPlus = json['plus'] as Map<String, dynamic>;
      expect(plus.look.name, wantPlus['state']);
      expect(plus.lead, wantPlus['lead']);
      expect(plus.expanded, wantPlus['expanded']);
      hold('the +', tester.getRect(button), wantPlus['rect']);
      hold('the +’s strokes', tester.getRect(within(button, find.byType(AnimatedRotation))), wantPlus['svg']);

      // The card.
      final wantList = json['list'] as Map<String, dynamic>?;
      final wantRows = (json['rows'] as List).cast<Map<String, dynamic>>();
      if (wantList == null) {
        expect(find.byType(AddList), findsNothing);
      } else {
        final list = tester.state<AddListState>(find.byType(AddList));
        hold('the card', list.cardRect, wantList['rect']);
        hold('the rows that scroll', tester.getRect(find.byType(SingleChildScrollView).last), wantList['rows']);
        expect(list.keyed, wantList['keys'], reason: 'data-keys');
        final card = tester.renderObject<RenderAddCard>(find.byType(AddCard));
        final cap = wantList['maxBlockSize'] as String;
        if (cap.isEmpty) {
          expect(card.cap, isNull, reason: 'no cap on the rows');
        } else {
          expect(card.cap, closeTo(double.parse(cap.replaceAll('px', '')), tolerance), reason: 'the cap on the rows');
        }
        final rows = rowViews.evaluate().toList();
        expect(rows.length, wantRows.length, reason: 'as many rows as the page drew');
        for (var i = 0; i < rows.length && i < wantRows.length; i += 1) {
          final want = wantRows[i];
          final row = find.byElementPredicate((element) => identical(element, rows[i]));
          final label = '${want['words']}';
          final texts = tester.widgetList<Text>(within(row, find.byType(Text))).toList();
          expect(texts.first.data, want['words'], reason: 'row $i');
          expect(texts.length > 1 ? texts[1].data : null, want['why'], reason: 'row $i’s reason');
          hold('[$label] row', tester.getRect(row), want['rect']);
          final icon = within(row, find.byWidgetPredicate((w) => w is AppIcon || w is DrawnIconView));
          hold('[$label] icon', tester.getRect(icon.first), want['drawing']);
          hold('[$label] words', lettersOf(tester, within(row, find.byType(Text)).first), want['letters']);
          if (want['whyBox'] != null) {
            final why = tester.getRect(within(row, find.byType(Text)).at(1));
            final wanted = rectOf(want['whyBox']);
            // The reason's own letters: the page's box runs to the row's end.
            hold('[$label] reason', Rect.fromLTRB(why.left, why.top, wanted.right, why.bottom), want['whyBox']);
          }
          hold('[$label] chevron', want['onward'] == null ? null : tester.getRect(icon.last), want['onward']);
          // The face: its size and weight, and the inks.
          final style = texts.first.style!;
          expect(style.fontSize, closeTo((want['size'] as num).toDouble(), 0.01), reason: '[$label] size');
          expect(style.fontWeight!.value.toString(), want['weight'], reason: '[$label] weight');
        }
        // What is held at the card's top and foot is no part of what scrolls.
        final scroller = find.byType(SingleChildScrollView).last;
        for (var i = 0; i < rows.length && i < wantRows.length; i += 1) {
          final inside = find.descendant(of: scroller, matching: find.byElementPredicate((element) => identical(element, rows[i]))).evaluate().isNotEmpty;
          expect(!inside, wantRows[i]['held'], reason: '${wantRows[i]['words']} held');
        }
        final wantField = json['field'] as Map<String, dynamic>?;
        if (wantField != null) {
          // The field's box is its border's: the decorated box round the words.
          final field = find.ancestor(of: find.byType(EditableText), matching: find.byType(DecoratedBox)).first;
          hold('the field', tester.getRect(field), wantField['rect']);
          expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, wantField['value']);
          if ((wantField['value'] as String).isEmpty) expect(find.text(wantField['placeholder'] as String), findsOneWidget);
        } else {
          expect(find.byType(EditableText), findsNothing);
        }
        final wantTitle = json['title'] as Map<String, dynamic>?;
        if (wantTitle != null) {
          final title = tester.getRect(find.text(wantTitle['words'] as String));
          final wanted = rectOf(wantTitle['rect']);
          hold('the title', Rect.fromLTRB(title.left, title.top, wanted.right, title.bottom), wantTitle['rect']);
        }
        final wantNone = json['none'] as Map<String, dynamic>?;
        if (wantNone != null) {
          // The page's box is its padding's; a paragraph's margins, which the palette's has, are outside it.
          final none = tester.getRect(find.ancestor(of: find.text(wantNone['words'] as String), matching: find.byType(Padding)).first);
          final margin = json['open'] == 'slash' ? (wantNone['size'] as num).toDouble() : 0.0;
          hold('nothing found', Rect.fromLTRB(none.left, none.top + margin, none.right, none.bottom - margin), wantNone['rect']);
        }
      }
      // ignore: avoid_print
      print('$name: worst ${worst.toStringAsFixed(3)} px over ${wantRows.length} rows');
      expect(problems, isEmpty, reason: problems.join('\n'));
      await shot(tester, name);
    });
  }
}
