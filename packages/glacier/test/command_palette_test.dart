import 'dart:ui' show SemanticsRole;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart';
import 'package:glacier/src/components/field_core.dart';

import 'support/harness.dart';

const commands = <CommandDescriptor>[
  CommandDescriptor(id: 'new', label: 'New file', group: 'File', shortcut: '⌘N'),
  CommandDescriptor(id: 'open', label: 'Open…', group: 'File', keywords: 'load import'),
  CommandDescriptor(id: 'save', label: 'Save', group: 'File', disabled: true),
  CommandDescriptor(id: 'theme', label: 'Toggle theme', group: 'View', keywords: 'dark light appearance'),
  CommandDescriptor(id: 'zen', label: 'Zen mode', group: 'View'),
];

/// A parent for the palette, as an app is one: it holds whether the palette is open and, when [query] is not null,
/// what is typed; and it writes down what it was told, in order.
class Rig {
  Rig({this.open = false, this.query, this.items = commands, this.obey = true});
  bool open;
  String? query;
  List<CommandDescriptor> items;

  /// Whether the parent does as `onOpenChange` asks.
  bool obey;
  final List<String> log = [];
  late StateSetter set;

  Widget build({
    String defaultQuery = '',
    String? placeholder,
    Widget? emptyLabel,
    Widget? footer = const GlacierCommandPaletteHint(),
    GlacierCommandPaletteSize size = GlacierCommandPaletteSize.md,
    bool shortcut = true,
    TextStyle? kbdStyle,
    Widget? beside,
  }) {
    return StatefulBuilder(
      builder: (context, setState) {
        set = setState;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?beside,
            GlacierCommandPalette(
              open: open,
              onOpenChange: (next) {
                log.add('open:$next');
                if (obey) setState(() => open = next);
              },
              commands: items,
              onRun: (id) => log.add('run:$id'),
              query: query,
              defaultQuery: defaultQuery,
              onQueryChange: (next) {
                log.add('query:$next');
                if (query != null) setState(() => query = next);
              },
              placeholder: placeholder,
              emptyLabel: emptyLabel,
              footer: footer,
              size: size,
              shortcut: shortcut,
              kbdStyle: kbdStyle,
            ),
          ],
        );
      },
    );
  }
}

/// The harness's own tree in a window of another size, or over a soft keyboard.
Future<void> pumpIn(WidgetTester tester, Widget child, {Size size = const Size(390, 844), double keyboard = 0, bool reduceMotion = false}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: size, viewInsets: EdgeInsets.only(bottom: keyboard), disableAnimations: reduceMotion),
        child: GlacierTheme(
          sheet: testSheet,
          attrs: {...testAttrs, 'theme': 'light'},
          child: Overlay(initialEntries: [OverlayEntry(builder: (context) => Align(alignment: Alignment.topLeft, child: child))]),
        ),
      ),
    ),
  );
}

final Finder panel = find.byWidgetPredicate((w) => w is Semantics && w.properties.role == SemanticsRole.dialog);
final Finder list = find.byType(SingleChildScrollView);
final Finder rows = find.descendant(of: list, matching: find.byType(GlacierPressable));
final Finder field = find.byType(EditableText);

String textOf(WidgetTester tester, Finder row) => tester.widget<RichText>(find.descendant(of: row, matching: find.byType(RichText)).first).text.toPlainText();

/// The rows on screen, top to bottom, as their labels.
List<String> shown(WidgetTester tester) => [for (var i = 0; i < rows.evaluate().length; i++) textOf(tester, rows.at(i))];

/// The row the cursor is on, or null where it is on none.
String? active(WidgetTester tester) {
  for (var i = 0; i < rows.evaluate().length; i++) {
    if (tester.widget<GlacierPressable>(rows.at(i)).selected == true) return textOf(tester, rows.at(i));
  }
  return null;
}

Finder rowOf(String label) => find.ancestor(of: find.textContaining(label, findRichText: true), matching: find.byType(GlacierPressable)).first;

Future<void> open(WidgetTester tester, Rig rig) async {
  rig.set(() => rig.open = true);
  await tester.pumpAndSettle();
}

void main() {
  group('GlacierCommandPalette', () {
    testWidgets('closed, it draws nothing and takes no room', (tester) async {
      final rig = Rig();
      await pumpKit(tester, rig.build());
      expect(panel, findsNothing);
      expect(field, findsNothing);
      expect(tester.getSize(find.byType(GlacierCommandPalette)), Size.zero);
    });

    testWidgets('opens as a panel pinned near the top, with the field focused and the keyboard up', (tester) async {
      final rig = Rig();
      await pumpKit(tester, rig.build());
      await open(tester, rig);
      final t = testTokens();

      // .overlay: padding space 6, 12vh of headroom; .panel: the full width up to 32rem, no taller than
      // min(28rem, 70vh).
      final box = tester.getRect(panel);
      expect(box.top, moreOrLessEquals(844 * 0.12));
      expect(box.left, moreOrLessEquals(t.space(6)));
      expect(box.width, moreOrLessEquals(390 - t.space(6) * 2));
      expect(box.height, lessThanOrEqualTo(448));

      // The field: the kit's search field at its own md, inside the hairline and the panel's padding.
      final inset = t.len('glacier-hairline') + t.space(2);
      final search = tester.getRect(find.byType(GlacierSearchField));
      expect(search.top, moreOrLessEquals(box.top + inset));
      expect(search.left, moreOrLessEquals(box.left + inset));
      expect(search.width, moreOrLessEquals(box.width - inset * 2));
      expect(search.height, moreOrLessEquals(t.len('glacier-control-height-md')));
      expect(find.text('Type a command or search…'), findsOneWidget);
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.testTextInput.setClientArgs!['inputAction'], 'TextInputAction.search');

      // The glass: the thick material with its border and the deepest shadow, over a blur; a scrim behind.
      final glass = tester
          .widgetList<CustomPaint>(find.descendant(of: find.byType(Transform), matching: find.byType(CustomPaint)))
          .map((p) => p.painter)
          .whereType<KitBoxPainter>()
          .firstWhere((p) => p.shadows.isNotEmpty);
      expect(glass.fill, t.color('glacier-glass-thick'));
      expect(glass.border, t.color('glacier-glass-border'));
      expect(glass.radius, t.radius('2xl'));
      expect(glass.shadows, t.shadow('glacier-shadow-5'));
      expect(tester.widget<ColoredBox>(find.byType(ColoredBox).first).color, t.color('glacier-overlay'));
      // One blur, the scrim's. The panel's own backdrop-filter sees no further than the scrim, so under the glass
      // there is the scrim's colour once more (saturated, which leaves a grey as it was) and no second blur.
      expect(find.byType(BackdropFilter), findsOneWidget);
      final under = tester
          .widgetList<CustomPaint>(find.descendant(of: find.byType(Transform), matching: find.byType(CustomPaint)))
          .map((p) => p.painter)
          .whereType<KitBoxPainter>()
          .first;
      expect(under.fill, isSameColorAs(saturated(t.color('glacier-overlay'), t.len('glacier-glass-saturate'))));
      expect(under.radius, t.radius('2xl'));
    });

    testWidgets('lists every command under its heading, in the caller’s order, with the cursor on the first', (tester) async {
      final rig = Rig(open: true);
      await pumpKit(tester, rig.build());
      await tester.pumpAndSettle();
      final t = testTokens();
      expect(shown(tester), ['New file', 'Open…', 'Save', 'Toggle theme', 'Zen mode']);
      expect(active(tester), 'New file');

      // .group: upper case, xs, medium, subtle, tracked 0.04em, padded space 2 / 3 / 1.
      final heading = tester.widget<Text>(find.text('FILE'));
      expect(find.text('VIEW'), findsOneWidget);
      expect(heading.style!.fontSize, t.fontSize('xs'));
      expect(heading.style!.color, t.color('glacier-text-subtle'));
      expect(heading.style!.fontWeight, t.weight('medium'));
      expect(heading.style!.letterSpacing, moreOrLessEquals(0.04 * t.fontSize('xs')));
      final listBox = tester.getRect(list);
      expect(tester.getTopLeft(find.text('FILE')), offsetMoreOrLessEquals(listBox.topLeft + Offset(t.space(3), t.space(2))));

      // .option: sm text padded space 2 / 3, the active one filled with the hover colour at the md radius.
      final first = tester.getRect(rows.at(0));
      expect(first.width, moreOrLessEquals(listBox.width));
      final label = tester.widget<RichText>(find.descendant(of: rows.at(0), matching: find.byType(RichText)).first);
      expect(label.text.style!.fontSize, t.fontSize('sm'));
      expect(label.text.style!.color, t.color('glacier-text'));
      expect(label.maxLines, 1);
      expect(label.overflow, TextOverflow.ellipsis);
      expect(tester.getTopLeft(find.byWidget(label)).dx, moreOrLessEquals(first.left + t.space(3)));
      BoxDecoration fill(int i) => tester.widget<DecoratedBox>(find.descendant(of: rows.at(i), matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration;
      expect(fill(0).color, t.color('glacier-hover'));
      expect(fill(0).borderRadius, BorderRadius.circular(t.radius('md')));
      expect(fill(1).color, isNull);

      // A disabled row is listed, quieter.
      final save = tester.widget<RichText>(find.descendant(of: rows.at(2), matching: find.byType(RichText)).first);
      expect(save.text.style!.color, t.color('glacier-text-subtle'));

      // The shortcut is a key cap on the trailing edge, 0.8em of the row's text.
      final cap = find.descendant(of: rows.at(0), matching: find.byType(GlacierKbd));
      expect(cap, findsOneWidget);
      expect(tester.getRect(cap).right, moreOrLessEquals(first.right - t.space(3)));
      expect(tester.widget<RichText>(find.descendant(of: cap, matching: find.byType(RichText))).text.style!.fontSize, moreOrLessEquals(t.fontSize('sm') * 0.8));

      // The footer: the key hints, under a hairline.
      final hint = tester.widget<Text>(find.text('↑↓ to navigate · ↵ to run · esc to close'));
      expect(hint.style!.fontSize, t.fontSize('xs'));
      expect(hint.style!.color, t.color('glacier-text-subtle'));
    });

    testWidgets('typing filters and orders as the logic says, and re-seats the cursor', (tester) async {
      final rig = Rig(open: true);
      await pumpKit(tester, rig.build());
      await tester.pumpAndSettle();
      for (final query in ['view', 'o', 'file', 'dark', 'ZEN', 'open', 'e t']) {
        await tester.enterText(field, query);
        await tester.pump();
        final expected = matchCommands(commands, query);
        expect(expected, isNotEmpty, reason: query);
        expect(
          shown(tester),
          [for (final m in expected) m.matchedKeyword == null ? m.item.label : '${m.matchedKeyword} · ${m.item.label}'],
          reason: query,
        );
        expect(active(tester), shown(tester)[firstCommandCursor(expected)], reason: query);
      }
      expect(rig.log.where((l) => l.startsWith('query:')), ['query:', 'query:view', 'query:o', 'query:file', 'query:dark', 'query:ZEN', 'query:open', 'query:e t']);

      // "file": the label hit comes first; the two filed under File follow, and the cursor skips nothing here.
      await tester.enterText(field, 'file');
      await tester.pump();
      expect(shown(tester), ['New file', 'Open…', 'Save']);
      expect(find.text('VIEW'), findsNothing);
    });

    testWidgets('a row still offered after a letter is the row it was, and two rows of one id each have their own', (tester) async {
      final rig = Rig(open: true);
      await pumpKit(tester, rig.build());
      await tester.pumpAndSettle();
      // "Open…" is offered for nothing typed, for "o" and for "open": one row through all three, wherever it stands.
      Element row(String label) => tester.element(rowOf(label));
      final open = row('Open…');
      await tester.enterText(field, 'o');
      await tester.pump();
      expect(identical(row('Open…'), open), isTrue);
      await tester.enterText(field, 'open');
      await tester.pump();
      expect(identical(row('Open…'), open), isTrue);
      // Typed away and back, it is a row made again: nothing is kept for a command that is not offered.
      await tester.enterText(field, 'dark');
      await tester.pump();
      await tester.enterText(field, 'open');
      await tester.pump();
      expect(identical(row('Open…'), open), isFalse);
      // Two commands of one id are two rows, and no key is worn twice.
      rig.set(() => rig.items = const [CommandDescriptor(id: 'same', label: 'One'), CommandDescriptor(id: 'same', label: 'Two'), CommandDescriptor(id: 'other', label: 'Three')]);
      await tester.enterText(field, '');
      await tester.pump();
      expect(shown(tester), ['One', 'Two', 'Three']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('marks what answered the query, and leads with the keyword where only a keyword did', (tester) async {
      final rig = Rig(open: true);
      await pumpKit(tester, rig.build());
      await tester.pumpAndSettle();
      final t = testTokens();

      List<(String, Color?, FontWeight?)> runs(Finder row) {
        final out = <(String, Color?, FontWeight?)>[];
        final root = tester.widget<RichText>(find.descendant(of: row, matching: find.byType(RichText)).first).text as TextSpan;
        void walk(InlineSpan span, TextStyle style) {
          if (span is! TextSpan) return;
          final own = style.merge(span.style);
          if (span.text != null && span.text!.isNotEmpty) out.add((span.text!, own.color, own.fontWeight));
          for (final child in span.children ?? const <InlineSpan>[]) {
            walk(child, own);
          }
        }

        walk(root, const TextStyle());
        return out;
      }

      await tester.enterText(field, 'the');
      await tester.pump();
      final ink = t.color('glacier-text');
      // The only row, so the active one: its mark is the brighter solid.
      expect(runs(rows.at(0)), [
        ('Toggle ', ink, t.weight('regular')),
        ('the', t.color('glacier-accent-solid'), t.weight('semibold')),
        ('me', ink, t.weight('regular')),
      ]);

      await tester.enterText(field, 'e');
      await tester.pump();
      // A row the cursor is not on marks in the accent text; a disabled one keeps its own quiet ink, bolder.
      expect(shown(tester), ['New file', 'Open…', 'Save', 'Toggle theme', 'Zen mode']);
      expect(runs(rows.at(1)).where((r) => r.$1 == 'e').single, ('e', t.color('glacier-accent-text'), t.weight('semibold')));
      expect(runs(rows.at(2)).where((r) => r.$1 == 'e').single, ('e', t.color('glacier-text-subtle'), t.weight('semibold')));

      await tester.enterText(field, 'dark');
      await tester.pump();
      final subtle = t.color('glacier-text-subtle');
      expect(runs(rows.at(0)), [
        ('dark', t.color('glacier-accent-solid'), t.weight('semibold')),
        (' · ', subtle, t.weight('regular')),
        ('Toggle theme', subtle, t.weight('regular')),
      ]);
    });

    testWidgets('the arrow keys move the cursor, skipping a disabled row and wrapping; Home and End go to the ends', (tester) async {
      final rig = Rig(open: true);
      await pumpKit(tester, rig.build());
      await tester.pumpAndSettle();
      expect(active(tester), 'New file');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(active(tester), 'Open…');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(active(tester), 'Toggle theme', reason: 'Save is disabled');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(active(tester), 'New file', reason: 'past the last row is the first');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(active(tester), 'Zen mode');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(active(tester), 'Open…');
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(active(tester), 'Zen mode');
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(active(tester), 'New file');
      // A held key repeats.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(active(tester), 'Toggle theme');
      // The keys were the palette's: none of them moved the caret or reached the text.
      expect(tester.widget<EditableText>(field).controller.text, '');
      expect(rig.log, ['query:']);
    });

    testWidgets('Enter runs the cursor’s row: the palette is told to close first, then the command runs', (tester) async {
      final rig = Rig(open: true);
      await pumpKit(tester, rig.build());
      await tester.pumpAndSettle();
      rig.log.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(rig.log, ['open:false', 'run:open']);
      expect(panel, findsNothing, reason: 'there is no exit animation: closed is gone');
    });

    testWidgets('Enter on nothing runs nothing', (tester) async {
      final rig = Rig(open: true, items: const [CommandDescriptor(id: 'a', label: 'Only', disabled: true)]);
      await pumpKit(tester, rig.build());
      await tester.pumpAndSettle();
      rig.log.clear();
      expect(active(tester), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.enterText(field, 'zzz');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(rig.log, ['query:zzz']);
      expect(panel, findsOneWidget);
    });

    testWidgets('the soft keyboard’s action key runs the cursor’s row', (tester) async {
      final rig = Rig(open: true);
      await pumpKit(tester, rig.build());
      await tester.pumpAndSettle();
      rig.log.clear();
      await tester.enterText(field, 'zen');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(rig.log, ['query:zen', 'open:false', 'run:zen']);
    });

    testWidgets('Escape closes it and runs nothing', (tester) async {
      final rig = Rig(open: true);
      await pumpKit(tester, rig.build());
      await tester.pumpAndSettle();
      rig.log.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(rig.log, ['open:false']);
      expect(panel, findsNothing);
    });

    testWidgets('a press on the scrim closes it; a press in the panel does not, and leaves the field focused', (tester) async {
      final rig = Rig(open: true);
      await pumpKit(tester, rig.build());
      await tester.pumpAndSettle();
      rig.log.clear();
      await tester.tap(find.text('FILE'));
      await tester.tap(find.text('↑↓ to navigate · ↵ to run · esc to close'));
      await tester.tap(rowOf('Save'), warnIfMissed: false);
      await tester.pump();
      expect(rig.log, isEmpty);
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);

      await tester.tapAt(const Offset(195, 800));
      await tester.pump();
      expect(rig.log, ['open:false']);
      expect(panel, findsNothing);
    });

    testWidgets('a tap runs a row; a mouse moves the cursor by hovering and runs on the way down', (tester) async {
      final rig = Rig(open: true);
      await pumpKit(tester, rig.build());
      await tester.pumpAndSettle();
      rig.log.clear();
      await tester.tap(rowOf('Zen mode'));
      await tester.pump();
      expect(rig.log, ['open:false', 'run:zen']);

      // A parent that keeps it open shows what the press did to the cursor, and that one press is one run.
      final stay = Rig(open: true, obey: false);
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpKit(tester, stay.build());
      await tester.pumpAndSettle();
      stay.log.clear();
      await tester.tap(rowOf('Toggle theme'));
      await tester.pump();
      expect(stay.log, ['open:false', 'run:theme']);
      expect(active(tester), 'Toggle theme');

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(rowOf('Open…')));
      await tester.pump();
      expect(active(tester), 'Open…');
      await mouse.moveTo(tester.getCenter(rowOf('Save')));
      await tester.pump();
      expect(active(tester), 'Open…', reason: 'a disabled row does not take the cursor');
      await mouse.moveTo(tester.getCenter(rowOf('Zen mode')));
      await tester.pump();
      expect(active(tester), 'Zen mode');

      stay.log.clear();
      await mouse.down(tester.getCenter(rowOf('Zen mode')));
      expect(stay.log, ['open:false', 'run:zen'], reason: 'mousedown, not click');
      await mouse.up();
      await tester.pump();
      expect(stay.log, ['open:false', 'run:zen'], reason: 'and the release is not a second run');

      // The next touch is a tap again.
      stay.log.clear();
      await tester.tap(rowOf('New file'));
      expect(stay.log, ['open:false', 'run:new']);
    });

    testWidgets('nothing matching shows the empty line, or the caller’s own', (tester) async {
      final rig = Rig(open: true);
      await pumpKit(tester, rig.build());
      await tester.pumpAndSettle();
      final t = testTokens();
      await tester.enterText(field, 'xyzzy');
      await tester.pump();
      expect(list, findsNothing);
      final empty = find.text('No matching commands');
      final paragraph = tester.widget<RichText>(find.descendant(of: empty, matching: find.byType(RichText)));
      expect(paragraph.text.style!.fontSize, t.fontSize('sm'));
      expect(paragraph.text.style!.color, t.color('glacier-text-subtle'));
      expect(paragraph.textAlign, TextAlign.center);
      // .empty: padding space 6 / space 3, below the field and the panel's gap.
      final search = tester.getRect(find.byType(GlacierSearchField));
      expect(tester.getRect(empty).top, moreOrLessEquals(search.bottom + t.space(2) + t.space(6)));
      expect(tester.getRect(empty).center.dx, moreOrLessEquals(195));

      final own = Rig(open: true, query: 'xyzzy');
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpKit(tester, own.build(emptyLabel: const Text('Nothing by that name.'), placeholder: 'What would you like to do?', footer: null));
      await tester.pumpAndSettle();
      expect(find.text('No matching commands'), findsNothing);
      final said = tester.widget<RichText>(find.descendant(of: find.text('Nothing by that name.'), matching: find.byType(RichText)));
      expect(said.text.style!.color, t.color('glacier-text-subtle'), reason: 'the caller’s words inherit the empty line’s style');
      expect(find.text('↑↓ to navigate · ↵ to run · esc to close'), findsNothing, reason: 'footer: null drops the strip');
      own.set(() => own.query = '');
      await tester.pump();
      expect(find.text('What would you like to do?'), findsOneWidget);
    });

    testWidgets('a controlled query is the parent’s; an uncontrolled one starts over at each opening', (tester) async {
      // As Ghost.md drives it: the parent holds the query and builds the list from it.
      final rig = Rig(query: '');
      await pumpKit(tester, rig.build());
      await open(tester, rig);
      await tester.enterText(field, 'zen');
      await tester.pump();
      expect(rig.query, 'zen');
      expect(shown(tester), ['Zen mode']);
      rig.set(() => rig.items = const [CommandDescriptor(id: 'zen2', label: 'Zen garden'), ...commands]);
      await tester.pump();
      expect(shown(tester), ['Zen garden', 'Zen mode']);
      rig.set(() => rig.open = false);
      await tester.pump();
      await open(tester, rig);
      expect(tester.widget<EditableText>(field).controller.text, 'zen', reason: 'a controlled query is not the palette’s to reset');

      final own = Rig();
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpKit(tester, own.build(defaultQuery: 'the'));
      await open(tester, own);
      expect(own.log, ['query:the'], reason: 'the reset is announced, as the setter always does');
      expect(shown(tester), ['Toggle theme']);
      await tester.enterText(field, 'new');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await open(tester, own);
      expect(tester.widget<EditableText>(field).controller.text, 'the');
      expect(shown(tester), ['Toggle theme']);
    });

    testWidgets('the same commands built again leave the cursor where it is; opening seats it on the first row', (tester) async {
      // With the query the parent's, as Ghost.md has it: nothing of the palette's own is reset by opening but this.
      final rig = Rig(open: true, query: '');
      await pumpKit(tester, rig.build());
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(active(tester), 'Open…');
      rig.set(() => rig.items = [...commands]);
      await tester.pump();
      expect(active(tester), 'Open…');

      rig.set(() => rig.open = false);
      await tester.pump();
      await open(tester, rig);
      expect(active(tester), 'New file');
    });

    testWidgets('⌘K and Ctrl+K summon it from anywhere, unless the chord is the caller’s', (tester) async {
      final rig = Rig();
      await pumpKit(tester, rig.build());
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.pump();
      expect(rig.log, isEmpty, reason: 'a bare K is a letter');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(rig.log.first, 'open:true');
      expect(panel, findsOneWidget);

      // On an open palette the chord is a no-op that goes no further: no K lands in the field.
      rig.log.clear();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(rig.log, ['open:true']);

      final quiet = Rig();
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpKit(tester, quiet.build(shortcut: false));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(quiet.log, isEmpty);
    });

    testWidgets('Android’s back closes it, with no route under it', (tester) async {
      final rig = Rig(open: true);
      await pumpKit(tester, rig.build());
      await tester.pumpAndSettle();
      rig.log.clear();
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      expect(rig.log, ['open:false']);
      expect(panel, findsNothing);
      // Closed, back is not the palette's any more.
      expect(await tester.binding.handlePopRoute(), isFalse);
    });

    testWidgets('Android’s back closes it and leaves the route under it where it was', (tester) async {
      final rig = Rig();
      final navigator = GlobalKey<NavigatorState>();
      await pumpKit(
        tester,
        SizedBox(
          width: 390,
          height: 844,
          child: Navigator(
            key: navigator,
            onGenerateRoute: (settings) => PageRouteBuilder<void>(
              settings: settings,
              pageBuilder: (context, _, _) => settings.name == '/note' ? Align(alignment: Alignment.topLeft, child: rig.build(beside: const Text('A note'))) : const Text('Home'),
            ),
          ),
        ),
      );
      navigator.currentState!.pushNamed('/note');
      await tester.pumpAndSettle();
      await open(tester, rig);
      expect(panel, findsOneWidget);
      rig.log.clear();

      expect(await navigator.currentState!.maybePop(), isTrue, reason: 'the back was taken');
      await tester.pumpAndSettle();
      expect(rig.log, ['open:false']);
      expect(panel, findsNothing);
      expect(find.text('A note'), findsOneWidget, reason: 'the note behind the palette stays open');

      // With the palette closed, back is the note's again.
      expect(await navigator.currentState!.maybePop(), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('A note'), findsNothing);
    });

    testWidgets('focus is held inside while it is open and handed back when it closes', (tester) async {
      final outside = FocusNode(debugLabel: 'outside');
      addTearDown(outside.dispose);
      final rig = Rig();
      await pumpKit(tester, rig.build(beside: Focus(focusNode: outside, child: const SizedBox(width: 40, height: 40))));
      outside.requestFocus();
      await tester.pump();
      expect(outside.hasPrimaryFocus, isTrue);

      await open(tester, rig);
      final input = tester.widget<EditableText>(field).focusNode;
      expect(input.hasPrimaryFocus, isTrue);

      // Tab with nothing else to stop at comes back to the field; with a value there is the clear button, and round.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(input.hasPrimaryFocus, isTrue);
      await tester.enterText(field, 'zen');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(input.hasPrimaryFocus, isFalse);
      expect(outside.hasFocus, isFalse);
      expect(FocusManager.instance.primaryFocus!.context!.findAncestorWidgetOfExactType<GlacierSearchField>(), isNotNull, reason: 'the clear button');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(input.hasPrimaryFocus, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(input.hasPrimaryFocus, isFalse);
      expect(outside.hasFocus, isFalse);

      // Escape answers from wherever the focus is inside.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(outside.hasPrimaryFocus, isTrue);
    });

    testWidgets('it enters as the original does: the scrim fades in as the panel springs down into place', (tester) async {
      final rig = Rig();
      await pumpKit(tester, rig.build());
      rig.set(() => rig.open = true);
      await tester.pump();
      final t = testTokens();

      double scrim() => tester.widget<ColoredBox>(find.byType(ColoredBox).first).color.a / t.color('glacier-overlay').a;
      double lift() => tester.widget<Transform>(find.ancestor(of: panel, matching: find.byType(Transform)).last).transform.getTranslation().y;
      double scale() => tester.widget<Transform>(find.ancestor(of: panel, matching: find.byType(Transform)).first).transform.storage[0];
      double solid() => tester.widget<Opacity>(find.ancestor(of: panel, matching: find.byType(Opacity)).first).opacity;

      // initial={{ opacity: 0, scale: 0.97, y: -8 }}
      expect(scrim(), 0);
      expect(lift(), -8);
      expect(scale(), moreOrLessEquals(0.97));
      expect(solid(), 0);

      await tester.pump(const Duration(milliseconds: 75));
      expect(scrim(), moreOrLessEquals(Curves.easeOut.transform(0.5), epsilon: 0.001));
      expect(lift(), inExclusiveRange(-8, 0));
      expect(scale(), inExclusiveRange(0.97, 1));
      expect(solid(), inExclusiveRange(0, 1));

      await tester.pump(const Duration(milliseconds: 75));
      expect(scrim(), moreOrLessEquals(1));

      await tester.pumpAndSettle();
      expect(lift(), 0);
      expect(scale(), 1);
      expect(solid(), 1);
    });

    testWidgets('reduced motion puts it there at once', (tester) async {
      final rig = Rig();
      await pumpIn(tester, rig.build(), reduceMotion: true);
      rig.set(() => rig.open = true);
      await tester.pump();
      expect(tester.widget<Opacity>(find.ancestor(of: panel, matching: find.byType(Opacity)).first).opacity, 1);
      expect(tester.widget<Transform>(find.ancestor(of: panel, matching: find.byType(Transform)).last).transform.getTranslation().y, 0);
      expect(tester.widget<Transform>(find.ancestor(of: panel, matching: find.byType(Transform)).first).transform.storage[0], 1);
      expect(tester.widget<ColoredBox>(find.byType(ColoredBox).first).color, testTokens().color('glacier-overlay'));
    });

    for (final size in GlacierCommandPaletteSize.values) {
      testWidgets('on a wide window ${size.name} is ${size.maxWidth} across, centred', (tester) async {
        final rig = Rig(open: true);
        await pumpIn(tester, rig.build(size: size), size: const Size(1200, 900));
        await tester.pumpAndSettle();
        final box = tester.getRect(panel);
        expect(box.width, moreOrLessEquals(const {GlacierCommandPaletteSize.sm: 384.0, GlacierCommandPaletteSize.md: 512.0, GlacierCommandPaletteSize.lg: 640.0}[size]!));
        expect(box.center.dx, moreOrLessEquals(600));
        expect(box.top, moreOrLessEquals(108));
      });
    }

    testWidgets('a long list scrolls inside the panel, and the keys keep the cursor’s row in view', (tester) async {
      final many = [for (var i = 0; i < 40; i++) CommandDescriptor(id: 'c$i', label: 'Command $i')];
      final rig = Rig(open: true, items: many);
      await pumpKit(tester, rig.build());
      await tester.pumpAndSettle();
      // max-height: min(28rem, 70vh); the field and the footer stay put and the list takes what is left.
      final box = tester.getRect(panel);
      expect(box.height, moreOrLessEquals(448));
      final view = tester.getRect(list);
      expect(view.bottom, lessThan(box.bottom));
      expect(tester.getRect(find.text('↑↓ to navigate · ↵ to run · esc to close')).bottom, lessThan(box.bottom));

      bool visible(String label) {
        final row = tester.getRect(rowOf(label));
        return row.top >= view.top - 0.01 && row.bottom <= view.bottom + 0.01;
      }

      expect(visible('Command 0'), isTrue);
      for (var i = 0; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.pump();
        expect(visible('Command ${i + 1}'), isTrue, reason: 'row ${i + 1}');
      }
      expect(tester.getRect(find.byType(GlacierSearchField)).top, moreOrLessEquals(box.top + testTokens().len('glacier-hairline') + testTokens().space(2)));
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      await tester.pump();
      expect(active(tester), 'Command 39');
      expect(visible('Command 39'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();
      expect(active(tester), 'Command 0');
      expect(visible('Command 0'), isTrue);

      // A finger scrolls the list without running what it lands on.
      rig.log.clear();
      await tester.drag(list, const Offset(0, -200));
      await tester.pump();
      expect(rig.log, isEmpty);
      expect(visible('Command 0'), isFalse);
    });

    testWidgets('over a soft keyboard it measures what the keyboard leaves', (tester) async {
      final many = [for (var i = 0; i < 40; i++) CommandDescriptor(id: 'c$i', label: 'Command $i')];
      final rig = Rig(open: true, items: many);
      await pumpIn(tester, rig.build(), keyboard: 300);
      await tester.pumpAndSettle();
      final box = tester.getRect(panel);
      // 844 - 300 = 544 of window: 12vh of it above, and no taller than 70vh of it.
      expect(box.top, moreOrLessEquals(544 * 0.12));
      expect(box.height, moreOrLessEquals(544 * 0.7));
      expect(box.bottom, lessThan(544));
    });

    testWidgets('says what it is to a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      final rig = Rig(open: true);
      await pumpKit(tester, rig.build(beside: const Text('Behind')));
      await tester.pumpAndSettle();

      final dialog = tester.getSemantics(panel);
      expect(dialog, isSemantics(scopesRoute: true, namesRoute: true, label: 'Command palette'));
      expect(dialog.getSemanticsData().role, SemanticsRole.dialog);

      final input = tester.getSemantics(field);
      expect(input, isSemantics(isTextField: true, isFocused: true, isEnabled: true, hasEnabledState: true, hasExpandedState: true, isExpanded: true, label: 'Command palette'));
      final listId = input.getSemanticsData().controlsNodes!.single;
      final listNode = tester.getSemantics(find.ancestor(of: list, matching: find.byType(Semantics)).first);
      expect(listNode.identifier, listId);
      expect(listNode.label, 'Command palette');

      expect(tester.getSemantics(rows.at(0)), isSemantics(label: 'New file\n⌘N', isSelected: true, hasSelectedState: true, isEnabled: true, hasEnabledState: true, hasTapAction: true));
      expect(tester.getSemantics(rows.at(1)), isSemantics(label: 'Open…', isSelected: false, hasSelectedState: true, isEnabled: true, hasEnabledState: true, hasTapAction: true));
      expect(tester.getSemantics(rows.at(2)), isSemantics(label: 'Save', isSelected: false, hasSelectedState: true, isEnabled: false, hasEnabledState: true));
      // The headings are for the eye, and what is behind the palette is out of reach.
      expect(find.bySemanticsLabel('FILE'), findsNothing);
      expect(find.bySemanticsLabel('Behind'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(tester.getSemantics(rows.at(1)), isSemantics(label: 'Open…', isSelected: true, hasSelectedState: true, isEnabled: true, hasEnabledState: true, hasTapAction: true));
      handle.dispose();
    });

    testWidgets('speaks the reader’s language, and takes an app’s style for its key caps', (tester) async {
      final rig = Rig(open: true, query: 'xyzzy');
      await pumpKit(
        tester,
        Localizations(
          locale: const Locale('fr'),
          delegates: const [DefaultWidgetsLocalizations.delegate],
          child: rig.build(kbdStyle: const TextStyle(letterSpacing: 0, fontFeatures: [FontFeature('calt'), FontFeature('liga')])),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Aucune commande correspondante'), findsOneWidget);
      expect(find.text('↑↓ pour naviguer · ↵ pour exécuter · échap pour fermer'), findsOneWidget);
      rig.set(() => rig.query = '');
      await tester.pump();
      expect(find.text('Tapez une commande ou recherchez…'), findsOneWidget);

      rig.set(() => rig.query = 'new');
      await tester.pump();
      final cap = tester.widget<RichText>(find.descendant(of: find.byType(GlacierKbd), matching: find.byType(RichText)));
      expect(cap.text.style!.fontFeatures, const [FontFeature('calt'), FontFeature('liga')]);
      expect(cap.text.style!.letterSpacing, 0);
    });
  });
}
