import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/commands/app_commands.dart';
import 'package:ghost_md/commands/command_bar.dart';
import 'package:ghost_md/commands/palette.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/core/sample_library.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

/// What the web app's palette measured (test/commands/fixtures/web_palette.json): Ghost.md's own page in Chromium
/// over the invented library of ghost-md-app-store-pack/tools/seed.mjs, opened from the dock's Search at 390 x 844
/// and by Ctrl+K at 1280 x 800, in dark and in light, with nothing typed and with each of a handful of queries.
/// For each: the panel, the field, the list and the footer by `getBoundingClientRect`, and every heading and row in
/// order with its words and its rectangle (rows below the fold too, where the page laid them out).
final Map<String, dynamic> web = jsonDecode(File('test/commands/fixtures/web_palette.json').readAsStringSync()) as Map<String, dynamic>;

/// What a press asked for, in order.
class Calls {
  final List<String> said = [];
  void call(String what) => said.add(what);
}

/// Every doing the web app hands its palette where it records and has no note open, each one written down.
PaletteDoing everyDoing(Calls calls) => PaletteDoing(
      openNote: (id) => calls('openNote $id'),
      newNote: () => calls('newNote'),
      newNotebook: () => calls('newNotebook'),
      newJournal: () => calls('newJournal'),
      newEntry: (id) => calls('newEntry $id'),
      speak: () => calls('speak'),
      speakInto: (id) => calls('speakInto $id'),
      closeTab: (id) => calls('closeTab $id'),
      showList: () => calls('showList'),
      browseNotes: () => calls('browseNotes'),
      back: () => calls('back'),
      forward: () => calls('forward'),
      settings: () => calls('settings'),
      cheatSheet: () => calls('cheatSheet'),
      guide: () => calls('guide'),
      academy: () => calls('academy'),
      notifications: () => calls('notifications'),
      organizations: () => calls('organizations'),
      chooseWorkspace: (id) => calls('chooseWorkspace $id'),
      fileNote: (id, workspace) => calls('fileNote $id $workspace'),
      setView: (view) => calls('setView $view'),
      setTheme: (theme) => calls('setTheme $theme'),
      pin: (id, pinned) => calls('pin $id $pinned'),
      archive: (id) => calls('archive $id'),
      remove: (id) => calls('remove $id'),
      noteAi: (id, kind) => calls('noteAi $id $kind'),
      groupTab: (id) => calls('groupTab $id'),
      joinTabGroup: (id, group) => calls('joinTabGroup $id $group'),
      leaveTabGroup: (id) => calls('leaveTabGroup $id'),
    );

/// The home page of the library the web app was measured over, as the palette sees it: seed.mjs's notes and its two
/// workspaces, nothing open, on [theme].
PaletteWorld seededWorld(String theme) => PaletteWorld(
      notes: paletteNotes(seedLibrary()),
      journals: paletteJournals(seedLibrary()),
      workspaces: [for (final space in seedWorkspaces().list) (id: space.id, name: space.name)],
      theme: theme,
    );

/// The palette alone under the app's theme, on a window of [size]; [under] is drawn beneath it.
Future<CommandBarState> pumpBar(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  String theme = 'dark',
  required PaletteWorld world,
  required PaletteDoing doing,
  BackStack? stack,
  ValueChanged<VoidCallback>? onReady,
  Widget? under,
}) async {
  await pumpApp(
    tester,
    size: size,
    prefs: Preferences(theme: theme),
    home: BackScope(
      stack: stack ?? BackStack(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ?under,
          CommandBar(world: world, doing: doing, onReady: onReady),
        ],
      ),
    ),
  );
  await tester.pump();
  return tester.state<CommandBarState>(find.byType(CommandBar));
}

/// Past the palette's entrance: the scrim's fade and the panel's spring.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> type(WidgetTester tester, String words) async {
  await tester.enterText(find.byType(EditableText), words);
  await settle(tester);
}

/// pumpApp turned the shadows on for a picture; the binding wants its own switch back as a test ends.
Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// One line of the list as drawn: a group's heading or a row, its words and where it is.
typedef Line = ({String kind, String text, Rect rect, bool selected});

final Finder _list = find.descendant(of: find.byType(GlacierCommandPalette), matching: find.byType(SingleChildScrollView));

/// The panel: the kit puts its whole surface in one tap region, the outermost of the overlay's.
Rect panelRect(WidgetTester tester) => tester.getRect(find.byType(TextFieldTapRegion).first);
Rect fieldRect(WidgetTester tester) => tester.getRect(find.byType(GlacierSearchField));
Rect listRect(WidgetTester tester) => tester.getRect(_list);

/// The footer with its rule and padding, as the page's `.footer` box is.
Rect footerRect(WidgetTester tester) => tester.getRect(find.ancestor(of: find.byType(GlacierCommandPaletteHint), matching: find.byType(DecoratedBox)).first);

bool get hasList => _list.evaluate().isNotEmpty;

/// The headings and rows of the list, top to bottom, those scrolled out of sight among them. A row's words are as
/// the page's `innerText` gives them: the label, then its key hint after a bar.
List<Line> lines(WidgetTester tester) {
  final out = <Line>[];
  if (!hasList) return out;
  String words(Element element) => [
        for (final text in find.descendant(of: find.byElementPredicate((e) => identical(e, element)), matching: find.byType(RichText)).evaluate())
          (text.widget as RichText).text.toPlainText(),
      ].join(' | ');
  for (final element in find.descendant(of: _list, matching: find.byType(GlacierPressable)).evaluate()) {
    final row = element.widget as GlacierPressable;
    out.add((kind: 'row', text: words(element), rect: tester.getRect(find.byElementPredicate((e) => identical(e, element))), selected: row.selected ?? false));
  }
  for (final element in find.descendant(of: _list, matching: find.byType(ExcludeSemantics)).evaluate()) {
    final child = (element.widget as ExcludeSemantics).child;
    if (child is! Padding) continue;
    // A heading's words are set on the page's own line (the kit's ExactLines round the Text), or are the Text itself
    // where its style has no line of its own to be exact about.
    final inner = child.child;
    final words = inner is ExactLines ? inner.child : inner;
    if (words is! Text) continue;
    out.add((kind: 'head', text: words.data!, rect: tester.getRect(find.byElementPredicate((e) => identical(e, element))), selected: false));
  }
  out.sort((a, b) => a.rect.top.compareTo(b.rect.top));
  return out;
}

Rect rectOf(List<dynamic> web) => Rect.fromLTWH((web[0] as num).toDouble(), (web[1] as num).toDouble(), (web[2] as num).toDouble(), (web[3] as num).toDouble());

/// A rectangle within [by] of the page's on every side.
void expectRect(Rect got, List<dynamic> page, String what, {double by = 0.5}) {
  final want = rectOf(page);
  for (final (name, a, b) in [('left', got.left, want.left), ('top', got.top, want.top), ('width', got.width, want.width), ('height', got.height, want.height)]) {
    expect(a, closeTo(b, by), reason: '$what $name: drew $got, the page $want');
  }
}
