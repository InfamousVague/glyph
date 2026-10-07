import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/notifications.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/floating_card.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

/// The invented library the sidebar's pictures and measurements are taken over, here and on the web page: the same
/// file seeds the page's `localStorage` (the probes that measured the web app read it too), so a rectangle asserted
/// here was measured there over the same notes. Nobody in it is real.
class SidebarLibrary {
  SidebarLibrary._(this.now, this.all, this.kept, this.trash, this.notifications);

  factory SidebarLibrary.load() {
    final raw = jsonDecode(File('test/sidebar/fixtures/sidebar_library.json').readAsStringSync()) as Map<String, dynamic>;
    final notes = [
      for (final n in (raw['notes'] as List).cast<Map<String, dynamic>>())
        Note(id: n['id'] as String, body: n['body'] as String, createdAt: n['createdAt'] as int, updatedAt: n['updatedAt'] as int, starred: n['starred'] == true, archivedAt: n['archivedAt'] as int?),
    ];
    final spaces = raw['workspaces'] as Map<String, dynamic>;
    return SidebarLibrary._(
      raw['now'] as int,
      notes,
      WorkspaceSheet(
        list: [for (final w in (spaces['list'] as List).cast<Map<String, dynamic>>()) Workspace.kept(id: w['id'] as String, name: w['name'] as String, hue: w['hue'])],
        notes: (spaces['notes'] as Map).cast<String, String>(),
      ),
      (raw['trash'] as Map).cast<String, int>(),
      [for (final n in (raw['notifications'] as List)) FeedNotification.fromJson(n)!],
    );
  }

  /// The moment the pictures are taken at.
  final int now;
  final List<Note> all;
  final WorkspaceSheet kept;
  final Map<String, int> trash;
  final List<FeedNotification> notifications;

  /// The notes a screen may show: those not in the trash.
  List<Note> get notes => [for (final n in all) if (!trash.containsKey(n.id)) n];

  /// The notes in the trash, the most recently thrown away first.
  List<Note> get trashed => [for (final n in all) if (trash.containsKey(n.id)) n]..sort((a, b) => trash[b.id]!.compareTo(trash[a.id]!));

  /// A fresh store over the library's workspaces.
  WorkspaceStore store() => WorkspaceStore(storage: MemoryWorkspaceStorage(kept));
}

/// A page to float a card over: lines of words on the page's paper, and at its top corners the icons that open the
/// cards, each named as the web's are (`[data-sidebar-toggle]`, `[data-notifications-toggle]`).
class PageUnder extends StatelessWidget {
  const PageUnder({super.key, this.onSidebar, this.onBell, this.children = const []});
  final VoidCallback? onSidebar;
  final VoidCallback? onBell;

  /// What floats over the page: the drawers, a sheet.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return BackScope(
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.fromLTRB(t.space(5), t.len('app-safe-top') + t.space(5), t.space(5), 0),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: t.space(3),
                children: [
                  Text('Weekend trip', style: t.textAt(t.fontSize('2xl'), weight: 'bold')),
                  for (var i = 0; i < 14; i++)
                    Text(
                      const ['Pack the tent and the two sleeping bags.', 'Ask Sam about the stove.', 'The ferry leaves at nine; be there by half past eight.', 'Bring the map of the coast path.'][i % 4],
                      style: t.textAt(t.fontSize('lg'), mono: true),
                    ),
                ],
              ),
              ),
            ),
          ),
          Positioned(
            left: t.space(3),
            top: t.len('app-inset-top') + t.space(1),
            child: FloatingCardToggle(
              toggle: sidebarToggle,
              child: GestureDetector(
                key: const ValueKey('sidebar-icon'),
                behavior: HitTestBehavior.opaque,
                onTap: onSidebar,
                child: SizedBox.square(dimension: 33, child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: t.color('app-ink'), width: 1.5), borderRadius: BorderRadius.circular(10)))),
              ),
            ),
          ),
          Positioned(
            right: t.space(3),
            top: t.len('app-inset-top') + t.space(1),
            child: FloatingCardToggle(
              toggle: notificationsToggle,
              child: GestureDetector(
                key: const ValueKey('bell-icon'),
                behavior: HitTestBehavior.opaque,
                onTap: onBell,
                child: SizedBox.square(dimension: 33, child: DecoratedBox(decoration: BoxDecoration(border: Border.all(color: t.color('app-ink'), width: 1.5), borderRadius: BorderRadius.circular(10)))),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// The app with [home] under its theme, as [pumpApp] makes it. [bare] takes the window's safe areas away, as the
/// browser the web page was measured in has none; left false, the window has a phone's status bar and gesture bar.
Future<void> pumpPage(WidgetTester tester, Widget home, {Size size = const Size(390, 844), String theme = 'light', bool bare = true}) async {
  await pumpApp(tester, size: size, prefs: AppPreferences(theme: theme), home: home);
  if (bare) {
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await tester.pump();
  }
}

/// Past an entrance: the card's 180 ms, a sheet's 320.
Future<void> settle(WidgetTester tester, [int ms = 400]) async {
  for (var left = ms; left > 0; left -= 50) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Takes the screen down, and gives the test binding back its own switch for shadows, which [pumpApp] turned on.
Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// Asserts a rectangle measured on the web page: left, top, width, height, to [by] pixels.
void near(Rect got, List<double> want, {double by = 0.5, String? what}) {
  final said = '${what ?? ''} $got against $want';
  expect(got.left, closeTo(want[0], by), reason: '$said: left');
  expect(got.top, closeTo(want[1], by), reason: '$said: top');
  expect(got.width, closeTo(want[2], by), reason: '$said: width');
  expect(got.height, closeTo(want[3], by), reason: '$said: height');
}
