import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/settings_screen.dart';
import 'package:ghost_md/settings/settings_search.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

/// The web app's src/app/settings/SettingsScreen.test.tsx on the Flutter port, case for case: the search, the
/// shell's steps, sub-pages, a screen called something else, and a target. The shell's own rows and panes here are
/// made up, as they are there; the app's sections are settings_sheet_test.dart's.

Widget _row(String label) => SettingRow(label: label);

final List<SettingsSection> _sections = [
  SettingsSection(
    id: 'type',
    label: 'Type',
    icon: const SizedBox.shrink(),
    group: 0,
    summary: 'Larger · Inter',
    content: (context) => PaneBody(children: [_row('Text size')]),
    settings: const [SettingsFindable('Text size')],
  ),
  SettingsSection(
    id: 'animations',
    label: 'Animations',
    icon: const SizedBox.shrink(),
    group: 1,
    content: (context) => PaneBody(children: [_row('Animation speed'), _row('Smoke at the edges')]),
    settings: const [SettingsFindable('Animation speed'), SettingsFindable('Smoke at the edges', 'wisp')],
  ),
];

/// What the screen is given, so a test can give it something else (`rerender`).
class _Props {
  const _Props({this.open = true, this.sections, this.goTo, this.title = 'Settings', this.search = true, this.closeWord, this.split = false});
  final bool open;
  final List<SettingsSection>? sections;
  final SettingsTarget? goTo;
  final String title;
  final bool search;
  final String? closeWord;
  final bool split;
}

late ValueNotifier<_Props> _props;
int _closed = 0;

Future<void> _show(WidgetTester tester, [_Props props = const _Props()]) async {
  _closed = 0;
  _props = ValueNotifier(props);
  await pumpSettings(
    tester,
    ValueListenableBuilder<_Props>(
      valueListenable: _props,
      builder: (context, p, _) => SettingsScreen(
        open: p.open,
        onClose: () => _closed++,
        sections: p.sections ?? _sections,
        goTo: p.goTo,
        title: p.title,
        search: p.search,
        closeWord: p.closeWord,
        split: p.split,
      ),
    ),
  );
}

Future<void> _rerender(WidgetTester tester, _Props props) async {
  _props.value = props;
  await tester.pump();
  await settleSettings(tester);
}

List<String?> _labels(WidgetTester tester) => [for (final text in tester.widgetList<Text>(find.byKey(const ValueKey('settings-row-label')))) text.data];
List<String?> _summaries(WidgetTester tester) => [for (final text in tester.widgetList<Text>(find.byKey(const ValueKey('settings-row-summary')))) text.data];

/// The page's own word, or null over the list.
String? _display(WidgetTester tester) {
  final found = find.byKey(const ValueKey('settings-display'));
  return found.evaluate().isEmpty ? null : tester.widget<Text>(found).data;
}

final Finder _head = find.byKey(const ValueKey('settings-head-word'));

/// The word in the head, without its arrow.
String _headWord(WidgetTester tester) => tester.widget<Text>(find.descendant(of: _head, matching: find.byType(Text))).textSpan!.toPlainText().replaceAll('￼', '').trim();

Finder _rowFor(String label) => find.ancestor(of: find.text(label), matching: find.byType(GlacierPressable)).first;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await settleSettings(tester);
}

Future<void> _type(WidgetTester tester, String words) async {
  await tester.enterText(find.byType(EditableText), words);
  await tester.pump();
  await settleSettings(tester);
}

Future<void> _back(WidgetTester tester) async {
  testBack.goBack();
  await tester.pump();
  await settleSettings(tester);
}

/// A quick sideways drag across the page by [dx] pixels, right for back and left for forward (core/swipe.ts).
Future<void> _swipe(WidgetTester tester, double dx) async {
  final gesture = await tester.startGesture(const Offset(200, 300));
  await gesture.moveBy(Offset(dx, 0));
  await gesture.up();
  await tester.pump();
  await settleSettings(tester);
}

bool _lit(WidgetTester tester, String label) => SettingsFindableMark.isLit(tester.widget(find.descendant(of: find.widgetWithText(SettingRow, label), matching: find.byKey(SettingsFindableMark.lightKey))));

/// The lights that are on, anywhere on the page.
List<BoxDecoration> _lights(WidgetTester tester) => [
      for (final box in tester.widgetList<DecoratedBox>(find.byKey(SettingsFindableMark.lightKey)))
        if (SettingsFindableMark.isLit(box)) box.decoration as BoxDecoration,
    ];

void main() {
  setUpAll(loadAppFonts);

  group('Settings search', () {
    testWidgets('sits over the sections on a phone and swaps them for what it finds', (tester) async {
      await _show(tester);
      expect(find.bySemanticsLabel('Search settings'), findsWidgets);
      expect(_labels(tester), ['Type', 'Animations']);
      await _type(tester, 'wisp');
      expect(_labels(tester), ['Smoke at the edges']);
      expect(_summaries(tester), ['Animations']);
      await _type(tester, 'nothing like it');
      expect(find.text('Nothing in Settings matches “nothing like it”.'), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('opens a setting on its page and lights its row', (tester) async {
      await _show(tester);
      await _type(tester, 'smoke');
      await tester.tap(_rowFor('Smoke at the edges'));
      await tester.pump();
      expect(_display(tester), 'Animations');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_lit(tester, 'Smoke at the edges'), isTrue);
      expect(_lit(tester, 'Animation speed'), isFalse);
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pump();
      expect(_lit(tester, 'Smoke at the edges'), isFalse);
      await endSettings(tester);
    });

    testWidgets('opens the first result on Enter, and empties the field on Escape before anything closes', (tester) async {
      await _show(tester, const _Props(split: true));
      await tester.tap(find.byType(EditableText));
      await _type(tester, 'anim');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleSettings(tester);
      expect(_display(tester), 'Animations');
      // The split view keeps what was found in its left column while the page on the right changes.
      expect(_labels(tester), ['Animations']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleSettings(tester);
      expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, '');
      expect(_labels(tester), ['Type', 'Animations']);
      expect(_closed, 0);
      await endSettings(tester);
    });

    testWidgets('steps from the field into the results with the arrows, and back to it', (tester) async {
      await _show(tester);
      await tester.tap(find.byType(EditableText));
      await _type(tester, 's');
      expect(_labels(tester), ['Text size', 'Animation speed', 'Smoke at the edges']);
      final field = tester.widget<EditableText>(find.byType(EditableText)).focusNode;
      expect(field.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(field.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      // Up from the second result is the first, and up from the first is the field again.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(field.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(field.hasFocus, isTrue);
      // Down past the last stays on the last, and Enter there opens it: the setting, on its section's page.
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleSettings(tester);
      expect(_display(tester), 'Animations');
      await endSettings(tester);
    });

    testWidgets('takes ⌘F while it is open', (tester) async {
      await _show(tester);
      final field = tester.widget<EditableText>(find.byType(EditableText)).focusNode;
      expect(field.hasFocus, isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(field.hasFocus, isTrue);
      await endSettings(tester);
    });
  });

  group('the Settings shell', () {
    testWidgets('draws nothing while it is closed, and arrives when it opens', (tester) async {
      await _show(tester, const _Props(open: false));
      expect(find.byKey(const ValueKey('settings-head-word')), findsNothing);
      expect(testBack.depth, 0);
      _props.value = const _Props();
      await tester.pump();
      // `settingsEnter`: it comes up from 12px under where it rests, as it fades in.
      final first = tester.getTopLeft(_head).dy;
      await settleSettings(tester);
      expect(tester.getTopLeft(_head).dy, lessThan(first));
      expect(first - tester.getTopLeft(_head).dy, closeTo(12, 1.5));
      // One handler on the back stack while it is up, as each open screen puts one.
      expect(testBack.depth, 1);
      await _rerender(tester, const _Props(open: false));
      expect(testBack.depth, 0);
      await endSettings(tester);
    });

    testWidgets('steps out of a page and then closes, by the back word or the phone’s back', (tester) async {
      await _show(tester);
      await _tap(tester, _rowFor('Animations'));
      expect(_display(tester), 'Animations');
      await _back(tester);
      expect(_display(tester), isNull);
      expect(_closed, 0);
      await _tap(tester, _rowFor('Type'));
      await _tap(tester, _head);
      expect(_display(tester), isNull);
      await _tap(tester, _head);
      expect(_closed, 1);
      await endSettings(tester);
    });

    testWidgets('answers the system’s own back through the app’s back scope', (tester) async {
      await _show(tester);
      await _tap(tester, _rowFor('Animations'));
      // What Android sends for the back gesture.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await settleSettings(tester);
      expect(_display(tester), isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(_closed, 1);
      await endSettings(tester);
    });

    testWidgets('lands on the page it is asked to from inside another, each time it is asked', (tester) async {
      await _show(tester, const _Props(goTo: SettingsTarget('animations', nonce: 1)));
      expect(_display(tester), 'Animations');
      await _tap(tester, _head);
      expect(_display(tester), isNull);
      await _rerender(tester, const _Props(goTo: SettingsTarget('animations', nonce: 2)));
      expect(_display(tester), 'Animations');
      await endSettings(tester);
    });

    testWidgets('lands on the list on a fresh open, not on the page the last request opened', (tester) async {
      const goTo = SettingsTarget('animations', nonce: 1);
      await _show(tester, const _Props(goTo: goTo));
      expect(_display(tester), 'Animations');
      // Closed with the request still held, as the sheet holds it, and opened again.
      await _rerender(tester, const _Props(open: false, goTo: goTo));
      await _rerender(tester, const _Props(goTo: goTo));
      expect(_display(tester), isNull);
      // A request made while it was closed is still answered when it opens.
      await _rerender(tester, const _Props(open: false, goTo: SettingsTarget('animations', nonce: 2)));
      await _rerender(tester, const _Props(goTo: SettingsTarget('animations', nonce: 2)));
      expect(_display(tester), 'Animations');
      await endSettings(tester);
    });

    testWidgets('drops back to the list when the page on screen leaves the sections', (tester) async {
      await _show(tester);
      await _tap(tester, _rowFor('Animations'));
      // Developer mode switched off from inside its own page takes the page away.
      await _rerender(tester, _Props(sections: _sections.sublist(0, 1)));
      expect(_display(tester), isNull);
      expect(_labels(tester), ['Type']);
      // Truly on the list, not on a page that is only missing for now: it does not come back with its section,
      await _rerender(tester, const _Props());
      expect(_display(tester), isNull);
      // and back leaves Settings rather than stepping out of it.
      await _back(tester);
      expect(_closed, 1);
      await endSettings(tester);
    });

    testWidgets('steps out of a page on a swipe to the right, and back into it on one to the left', (tester) async {
      await _show(tester);
      await _tap(tester, _rowFor('Animations'));
      await _swipe(tester, 120);
      expect(_display(tester), isNull);
      await _swipe(tester, -120);
      expect(_display(tester), 'Animations');
      // A page opened from the list has nothing ahead of it: a swipe to the left there stays put.
      await _swipe(tester, 120);
      await _tap(tester, _rowFor('Type'));
      await _swipe(tester, -120);
      expect(_display(tester), 'Type');
      // A drag that is mostly up or down, or a short one, is not a swipe.
      final scroll = await tester.startGesture(const Offset(200, 300));
      await scroll.moveBy(const Offset(80, 60));
      await scroll.up();
      await tester.pump();
      expect(_display(tester), 'Type');
      await _swipe(tester, 40);
      expect(_display(tester), 'Type');
      await endSettings(tester);
    });

    testWidgets('leaves a drag that begins on the field, or on something marked as moving sideways, alone', (tester) async {
      await _show(
        tester,
        _Props(
          sections: [
            SettingsSection(
              id: 'type',
              label: 'Type',
              icon: const SizedBox.shrink(),
              group: 0,
              content: (context) => const PaneBody(children: [SettingsNoSwipe(child: SizedBox(height: 300, child: ColoredBox(color: Color(0x01000000))))]),
            ),
          ],
        ),
      );
      // On the list, a drag across the search field moves its caret, not the page.
      final onField = await tester.startGesture(tester.getCenter(find.byType(EditableText)));
      await onField.moveBy(const Offset(120, 0));
      await onField.up();
      await tester.pump();
      expect(_closed, 0);
      await _tap(tester, _rowFor('Type'));
      await _swipe(tester, 120);
      expect(_display(tester), 'Type');
      await endSettings(tester);
    });

    testWidgets('shows the first page beside the list on a wide window, and back leaves at once', (tester) async {
      await _show(tester, const _Props(split: true));
      expect(_display(tester), 'Type');
      expect(tester.getSemantics(_rowFor('Type')), isSemantics(isSelected: true, isButton: true));
      await _tap(tester, _rowFor('Animations'));
      expect(_display(tester), 'Animations');
      await _back(tester);
      expect(_closed, 1);
      await endSettings(tester);
    });

    testWidgets('is a split view exactly where the sidebar would be up, asked of the window', (tester) async {
      Future<bool> at(Size size) async {
        late bool split;
        await pumpApp(tester, size: size, home: Builder(builder: (context) {
          split = settingsSplitFits(context);
          return const SizedBox.shrink();
        }));
        return split;
      }

      expect(await at(const Size(390, 844)), isFalse);
      expect(await at(const Size(659, 844)), isFalse);
      expect(await at(const Size(660, 844)), isTrue);
      // A phone held sideways is wide and a strip: not two panes.
      expect(await at(const Size(844, 390)), isFalse);
      expect(await at(const Size(1280, 800)), isTrue);
      await endSettings(tester);
    });

    testWidgets('colours a section by its own hue, else by its id, else grey, and has no hue for a page that went', (tester) async {
      SettingsSection section(String id, String label, int group, {String? hue}) =>
          SettingsSection(id: id, label: label, icon: const SizedBox.shrink(), group: group, hue: hue, content: (context) => const SizedBox.shrink());
      final sections = [
        section('account', 'Account', 0),
        section('theme', 'Appearance', 1),
        section('recording', 'Recording', 1),
        section('market', 'Market', 1),
        section('about', 'About', 2),
        section('plugin:someday', 'Someday', 3, hue: 'coral'),
        section('plugin:unknown', 'Unknown', 3),
        // Formatting's orange went with its page: a section by that id now takes one picked by its id, as any without
        // one does; never grey (Matt, 2026-10-24: "make sure all settings sections icons have a color").
        section('formatting', 'Formatting', 3),
      ];
      expect([for (final s in sections) settingsHueOf(s)], ['blue', 'purple', 'red', 'green', 'yellow', 'coral', 'mint', 'blue']);
      await _show(tester, _Props(sections: sections));
      // And each chip is that hue as the page draws it on the light page: the colour at 16% under the glyph in it.
      final chips = tester.widgetList<Container>(find.byKey(const ValueKey('settings-row-icon'))).toList();
      final light = ['#0a6fe0', '#9a45c9', '#dd3a30', '#2a9d4b', '#b58400', '#c8643f', '#1f9e8f', '#0a6fe0'];
      for (var i = 0; i < light.length; i++) {
        final ground = (chips[i].decoration! as BoxDecoration).color!;
        expect(ground, sameColor(cssColor(tester, light[i]).withValues(alpha: 0.16)), reason: sections[i].label);
      }
      await endSettings(tester);
    });

    testWidgets('draws each hue a shade brighter on the dark page', (tester) async {
      await _show(tester);
      await endSettings(tester);
      _props = ValueNotifier(const _Props());
      await pumpSettings(
        tester,
        SettingsScreen(open: true, onClose: () {}, sections: [SettingsSection(id: 'account', label: 'Account', icon: const Icon(IconData(0x41)), group: 0, content: (context) => const SizedBox.shrink())]),
        prefs: const Preferences(theme: 'dark'),
      );
      final chip = tester.widget<Container>(find.byKey(const ValueKey('settings-row-icon')));
      // Measured on the page: rgb(78, 161, 255) at 16% under the glyph in the same colour.
      expect((chip.decoration! as BoxDecoration).color, sameColor(const Color.fromARGB(255, 78, 161, 255).withValues(alpha: 0.16)));
      expect(IconTheme.of(tester.element(find.descendant(of: find.byKey(const ValueKey('settings-row-icon')), matching: find.byType(Icon)))).color, sameColor(const Color.fromARGB(255, 78, 161, 255)));
      await endSettings(tester);
    });
  });

  /// Sub-pages (docs/DESIGN.md §138): a section off the list, opened from a row on its parent's page or by the
  /// search, with its parent's name in the head and back stepping there first.
  group('a sub-page', () {
    final withSub = [
      ..._sections,
      SettingsSection(id: 'plugins', label: 'Plugins', icon: const SizedBox.shrink(), group: 1, content: (context) => PaneBody(children: [_row('Notion')])),
      SettingsSection(
        id: 'plugin:notion',
        label: 'Notion',
        icon: const SizedBox.shrink(),
        group: 1,
        listed: false,
        parent: 'plugins',
        hue: 'graphite',
        content: (context) => PaneBody(children: [PaneSection(title: 'Boards', children: [_row('Kitchen')])]),
        settings: const [SettingsFindable('Boards', 'databases')],
      ),
    ];
    const toNotion = SettingsTarget('plugin:notion', nonce: 1);

    testWidgets('is not a row on the list, but the search finds it and what is on it', (tester) async {
      await _show(tester, _Props(sections: withSub));
      expect(_labels(tester), ['Type', 'Animations', 'Plugins']);
      await _type(tester, 'notion');
      expect(_labels(tester), ['Notion']);
      await _type(tester, 'databases');
      expect(_labels(tester), ['Boards']);
      expect(_summaries(tester), ['Notion']);
      await endSettings(tester);
    });

    testWidgets('opens from its parent’s page, names the parent in the head, and steps back to it, then to the list', (tester) async {
      await _show(tester, _Props(sections: withSub, goTo: toNotion));
      expect(_display(tester), 'Notion');
      expect(_headWord(tester), 'Plugins');
      await _back(tester);
      expect(_display(tester), 'Plugins');
      expect(_headWord(tester), 'Settings');
      await _tap(tester, _head);
      expect(_display(tester), isNull);
      await _back(tester);
      expect(_closed, 1);
      await endSettings(tester);
    });

    testWidgets('steps to its parent on a swipe to the right, and back into it on one to the left, from the parent only', (tester) async {
      await _show(tester, _Props(sections: withSub, goTo: toNotion));
      await _swipe(tester, 120);
      expect(_display(tester), 'Plugins');
      await _swipe(tester, -120);
      expect(_display(tester), 'Notion');
      // Back twice, to the list: from there the swipe forward goes into Plugins, the page just left, not to Notion.
      await _swipe(tester, 120);
      await _swipe(tester, 120);
      expect(_display(tester), isNull);
      await _swipe(tester, -120);
      expect(_display(tester), 'Plugins');
      await endSettings(tester);
    });

    testWidgets('opened from a search hit, still steps back to its parent', (tester) async {
      await _show(tester, _Props(sections: withSub));
      await _type(tester, 'boards');
      await _tap(tester, _rowFor('Boards'));
      expect(_display(tester), 'Notion');
      await _back(tester);
      expect(_display(tester), 'Plugins');
      await endSettings(tester);
    });

    testWidgets('shows on the right of a wide window with its parent’s row current, and back steps to the parent before it leaves', (tester) async {
      await _show(tester, _Props(sections: withSub, goTo: toNotion, split: true));
      expect(_display(tester), 'Notion');
      expect(_labels(tester), ['Type', 'Animations', 'Plugins']);
      expect(tester.getSemantics(_rowFor('Plugins')), isSemantics(isSelected: true, isButton: true));
      // The page wears its own colour: a row's chip on it would be graphite.
      expect(tokensAt(tester, find.widgetWithText(SettingRow, 'Kitchen')).colorOf('var(--hue)'), sameColor(cssColor(tester, '#5f6368')));
      await _back(tester);
      expect(_display(tester), 'Plugins');
      expect(_closed, 0);
      await _back(tester);
      expect(_closed, 1);
      await endSettings(tester);
    });

    testWidgets('says its parent in the head of a wide window, where the head steps back as back does, and leaves from a pane', (tester) async {
      await _show(tester, _Props(sections: withSub, goTo: toNotion, split: true));
      expect(_headWord(tester), 'Plugins');
      expect(find.bySemanticsLabel('Back to your notes'), findsNothing);
      await _tap(tester, _head);
      expect(_display(tester), 'Plugins');
      expect(_closed, 0);
      expect(_headWord(tester), 'Settings');
      expect(find.bySemanticsLabel('Back to your notes'), findsOneWidget);
      await _tap(tester, _head);
      expect(_closed, 1);
      await endSettings(tester);
    });
  });

  /// The same screen as an organization's (docs/TEAMS.md, D6): its name in place of "Settings" everywhere the word
  /// stood, no search over its few sections, and a head that can say where closing goes.
  group('a screen called something else', () {
    testWidgets('wears its title over the list, in the head’s way out, in its label and in what the search says', (tester) async {
      await _show(tester, const _Props(title: 'Ghost'));
      expect(find.bySemanticsLabel('Ghost'), findsWidgets);
      expect(_headWord(tester), 'Ghost');
      expect(find.bySemanticsLabel('Back to your notes'), findsOneWidget);
      expect(find.bySemanticsLabel('Search Ghost'), findsWidgets);
      await _type(tester, 'nothing like it');
      expect(find.text('Nothing in Ghost matches “nothing like it”.'), findsOneWidget);
      await _type(tester, '');
      await _tap(tester, _rowFor('Animations'));
      expect(_headWord(tester), 'Ghost');
      await _tap(tester, _head);
      await _tap(tester, _head);
      expect(_closed, 1);
      await endSettings(tester);
    });

    testWidgets('draws no search when told not to, on a phone and on a wide window, and ⌘F then goes nowhere', (tester) async {
      await _show(tester, const _Props(title: 'Ghost', search: false));
      expect(find.byType(EditableText), findsNothing);
      expect(_labels(tester), ['Type', 'Animations']);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      await _rerender(tester, const _Props(title: 'Ghost', search: false, split: true));
      expect(find.byType(EditableText), findsNothing);
      expect(_display(tester), 'Type');
      expect(_headWord(tester), 'Ghost');
      await endSettings(tester);
    });

    testWidgets('says where closing goes when told, in place of its name, on a phone and on a wide window', (tester) async {
      await _show(tester, const _Props(title: 'Ghost', closeWord: 'Organizations'));
      expect(_headWord(tester), 'Organizations');
      expect(find.bySemanticsLabel('Back to your notes'), findsNothing);
      // Over a pane the head still steps back to the list, and names the screen.
      await _tap(tester, _rowFor('Type'));
      expect(_headWord(tester), 'Ghost');
      await _tap(tester, _head);
      await _tap(tester, _head);
      expect(_closed, 1);
      await _rerender(tester, const _Props(title: 'Ghost', closeWord: 'Organizations', split: true));
      expect(_headWord(tester), 'Organizations');
      await endSettings(tester);
    });
  });

  group('a target', () {
    const lit = SettingsTarget('animations', setting: 'Smoke at the edges', nonce: 1);

    testWidgets('opens a page at a setting named with it, scrolled to and lit as a search hit is', (tester) async {
      await _show(tester, const _Props(goTo: lit), );
      expect(_display(tester), 'Animations');
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pump();
      expect(_lit(tester, 'Smoke at the edges'), isFalse);
      // Asked again from the page it is already on (a word on Account for Account's own card): lit again.
      _props.value = const _Props(goTo: SettingsTarget('animations', setting: 'Smoke at the edges', nonce: 2));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_lit(tester, 'Smoke at the edges'), isTrue);
      await tester.pump(const Duration(milliseconds: 1700));
      await endSettings(tester);
    });

    testWidgets('lights the setting as the page arrives, and lets it go after a moment', (tester) async {
      _closed = 0;
      _props = ValueNotifier(const _Props(goTo: lit));
      await pumpSettings(
        tester,
        ValueListenableBuilder<_Props>(valueListenable: _props, builder: (context, p, _) => SettingsScreen(open: true, onClose: () {}, sections: _sections, goTo: p.goTo, split: p.split)),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(_lit(tester, 'Smoke at the edges'), isTrue);
      // Lit in the section's colour, 18% of it for the first third: no hue is kept for this id, so its id picks blue.
      expect(_lights(tester).single.color, sameColor(cssColor(tester, '#0a6fe0').withValues(alpha: 0.18)));
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pump();
      expect(_lit(tester, 'Smoke at the edges'), isFalse);
      await endSettings(tester);
    });

    testWidgets('lights a setting once for each request: coming back to the page from the list is only opening it', (tester) async {
      await _show(tester, const _Props(goTo: lit));
      await tester.pump(const Duration(milliseconds: 1700));
      await _tap(tester, _head);
      await tester.tap(_rowFor('Animations'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_display(tester), 'Animations');
      expect(_lit(tester, 'Smoke at the edges'), isFalse);
      await endSettings(tester);
    });

    testWidgets('lights the setting on the right of a wide window too', (tester) async {
      _props = ValueNotifier(const _Props());
      await pumpSettings(tester, SettingsScreen(open: true, onClose: () {}, sections: _sections, goTo: lit, split: true), settle: false);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_lit(tester, 'Smoke at the edges'), isTrue);
      await tester.pump(const Duration(milliseconds: 1700));
      await endSettings(tester);
    });

    testWidgets('opens the page alone when it names no setting, or one the page does not draw', (tester) async {
      await _show(tester, const _Props(goTo: SettingsTarget('animations', nonce: 1)));
      expect(_lights(tester), isEmpty);
      await _rerender(tester, const _Props(goTo: SettingsTarget('animations', setting: 'Not on this page', nonce: 2)));
      expect(_display(tester), 'Animations');
      expect(_lights(tester), isEmpty);
      await endSettings(tester);
    });

    testWidgets('holds a lit setting still under reduced motion, at 12% of the colour', (tester) async {
      _props = ValueNotifier(const _Props());
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpSettings(tester, SettingsScreen(open: true, onClose: () {}, sections: _sections, goTo: lit), settle: false);
      await tester.pump(const Duration(milliseconds: 16));
      // Nothing arrives: the page and its row are where they rest from the first frame.
      expect(_display(tester), 'Animations');
      expect(_lights(tester).single.color, sameColor(cssColor(tester, '#0a6fe0').withValues(alpha: 0.12)));
      await tester.pump(const Duration(milliseconds: 800));
      expect(_lights(tester).single.color, sameColor(cssColor(tester, '#0a6fe0').withValues(alpha: 0.12)));
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump();
      expect(_lights(tester), isEmpty);
      await endSettings(tester);
    });
  });
}
