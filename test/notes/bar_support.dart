import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/tabs.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/main.dart';
import 'package:ghost_md/notes/note_tabs.dart';
import 'package:ghost_md/shell/app_tab_bar.dart';
import 'package:ghost_md/shell/header_pane.dart';
import 'package:ghost_md/shell/root_stamps.dart';
import 'package:ghost_md/shell/top_bar.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

/// The notch the test's phone has (test/support/render.dart): what the web page, measured in a browser with none,
/// has to be moved down by.
const double notch = 36;

/// The invented library the web app was measured over (ghost-md-app-store-pack/tools/seed.mjs), and its workspaces.
final List<Note> library = seedLibrary();
final Workspaces spaces = Workspaces(list: seedWorkspaces().list, of: seedWorkspaces().notes);

Note noteOf(String id) => library.firstWhere((n) => n.id == id);
List<Note> notesOf(List<String> ids) => [for (final id in ids) noteOf(id)];

TokenSheet? _sheet;

/// The app's token sheet, read once.
Future<TokenSheet> appSheet(WidgetTester tester) async => _sheet ??= (await tester.runAsync(() => loadTokenSheet(more: appStyleSheets)))!;

/// What a press on the bar asked for, in order.
class BarLog {
  final List<String> said = [];
  void call(String what) => said.add(what);
}

/// The bar as the shell draws it, over a page of paper: [style] on a window of [size], with [open] as its tabs and
/// [active] the one being read. `split` is whether the window is in two panes, as the shell stamps it.
Future<BarLog> pumpBar(
  WidgetTester tester, {
  TopBarStyle style = TopBarStyle.classic,
  List<String> open = const [],
  String active = '',
  Size size = const Size(390, 844),
  bool split = false,
  String theme = 'light',
  TabGroups groups = TabGroups.none,
  bool quiet = false,
  bool unread = false,
  bool atHome = false,
  bool canGoBack = false,
  bool canGoOn = false,
  bool fine = false,
  bool aside = false,
  List<OrgLike> organizations = const [],
  Widget? tools,
  Widget? tail,
  Widget Function(Widget bar)? wrap,
  void Function(String id, int to, {bool grouped})? onMove,
  ValueChanged<TabGroups>? onGroups,
  void Function(String id, String title)? onRename,
  List<Note>? notes,
}) async {
  final sheet = await appSheet(tester);
  final log = BarLog();
  final tabs = notes ?? notesOf(open);
  final bar = NoteTabs(
    style: style,
    tabs: tabs,
    activeId: active,
    workspaces: spaces,
    groups: groups,
    finePointer: fine,
    onOpen: (id) => log('open $id'),
    onClose: (id) => log('close $id'),
    onDelete: (id) => log('delete $id'),
    onNew: () => log('new'),
    onGroups: onGroups ?? (next) => log('groups ${next.list.map((g) => '${g.name}:${g.hue}${g.collapsed ? ':folded' : ''}').join(',')} ${next.of}'),
    onCloseTabs: (ids) => log('close tabs $ids'),
    onSidebar: () => log('sidebar'),
    onAside: aside ? () => log('aside') : null,
    onHome: () => log('home'),
    atHome: atHome,
    onMove: onMove ?? (id, to, {grouped = false}) => log('move $id $to${grouped ? ' grouped' : ''}'),
    onGoBack: () => log('back'),
    onGoOn: () => log('on'),
    canGoBack: canGoBack,
    canGoOn: canGoOn,
    onOrganizations: quiet ? null : () => log('organizations'),
    organizations: organizations,
    onOrganization: (id) => log('organization $id'),
    onNotifications: quiet ? null : () => log('notifications'),
    onSettings: quiet ? null : () => log('settings'),
    unread: unread,
    onRename: onRename ?? (id, title) => log('rename $id $title'),
    tools: tools,
    tail: tail,
  );
  await pumpApp(
    tester,
    size: size,
    prefs: Preferences(theme: theme),
    home: RootStamps(
      sheet: sheet,
      stamps: {'tabs': barRows(style, tabs.length).stamp, 'topbar': style == TopBarStyle.classic ? null : style.id, 'split': split ? 'on' : null},
      child: Stack(
        fit: StackFit.expand,
        children: [
          const HeaderPane(),
          Builder(builder: (context) => AppTabBar(style: style, child: wrap == null ? bar : wrap(bar))),
        ],
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return log;
}

/// Takes the screen down, with the binding's own switch for shadows put back.
Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// A box on the screen as the web page measured its twin: left and top from the window's corner (the web's top is
/// moved down by the test phone's notch), width and height.
Matcher boxAt(double x, double y, double w, double h, {double within = 0.5}) => _Box(Rect.fromLTWH(x, y + notch, w, h), within);

class _Box extends Matcher {
  const _Box(this.want, this.within);
  final Rect want;
  final double within;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) =>
      item is Rect && (item.left - want.left).abs() <= within && (item.top - want.top).abs() <= within && (item.width - want.width).abs() <= within && (item.height - want.height).abs() <= within;

  @override
  Description describe(Description description) => description.add('a box within $within of ${_say(want)}');

  @override
  Description describeMismatch(Object? item, Description mismatchDescription, Map<dynamic, dynamic> matchState, bool verbose) =>
      mismatchDescription.add(item is Rect ? 'is ${_say(item)}' : 'is not a box');

  static String _say(Rect r) => '[${r.left.toStringAsFixed(2)},${r.top.toStringAsFixed(2)} ${r.width.toStringAsFixed(2)}x${r.height.toStringAsFixed(2)}]';
}

/// The box of the one control named [label] to a screen reader.
Rect named(WidgetTester tester, String label) => tester.getRect(find.bySemanticsLabel(label).first);
