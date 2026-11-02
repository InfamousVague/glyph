import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/lucide.g.dart';

import '../core/book.dart';
import '../core/canvas_body.dart';
import '../core/live_titles.dart';
import '../core/note.dart';
import '../core/note_text.dart';
import '../core/tabs.dart';
import '../core/workspaces.dart';
import '../note/note_tools.dart' show NoteToolsModel;
import '../shell/desktop/mac_lights.dart';
import '../shell/header/grouped_command_row.dart' show groupedCommandRow;
import '../shell/header_toolbar.dart';
import '../shell/top_bar_tools.dart' show BarButton;
import '../shell/top_bar.dart';
import '../shell/wide_screen.dart';
import 'floating_card.dart';
import 'tabs/bar_parts.dart';
import 'tabs/tab_parts.dart';
import 'tabs/tab_row.dart';

/// The app's top bar: the notes that are open, and the way to the rest of them. Ports the web app's
/// notes/NoteTabs.tsx with NoteTabs.module.css, and with it notes/GroupChip.tsx, notes/TabMenus.tsx,
/// notes/useTabDrag.ts and notes/useTabOutline.ts (under notes/tabs/).
///
/// Two rows. The first is the controls - home, the sidebar's icon, back and forward, the slot the screen's own
/// buttons are drawn into ([tools]), the organizations' people icon with its picker, the bell (on when something
/// unread arrived, with a dot and no number), the Settings cog, the screen's More ([tail]) and the aside's icon at
/// the far end. The second is the tabs, which scroll sideways when there are more than fit, and is not drawn at all
/// with nothing open. A tap changes note without leaving the screen; the cross closes a tab, and the note behind it
/// carries on existing.
///
/// Four ways to lay it out ([style]; docs/DESIGN.md §178, §180), the same pieces in a different order and shape, so a
/// tab behaves the same whichever way it is drawn:
///
/// - **Classic**, the two rows above.
/// - **Ledger**: the tabs first, as a browser has them, with Home pinned in the row as a house tab; the open tab
///   opens down into the tool row, which is its own. The row is always there, so Home always is.
/// - **Masthead**: the controls as the app's own words - Home, Notes, Back - and the tabs as an index line under a
///   rule, the open one underlined.
/// - **Islands**: no bar; three glass capsules float over the page - the way around, the tabs, the screen's own.
///   On a window in two panes the three share one line.
///
/// In every way but Classic the cross is drawn on the open tab alone: the rest close from their menu, or once opened.
///
/// **The line of controls is Grouped command's** (lib/shell/header_toolbar.dart, header/grouped_command_row.dart) in
/// whichever of the four ways the bar is laid out: the way around in two pills, the note's name in a pill that opens
/// the command palette, the note's own in a pill with •••, and the round button for you. It is handed the controls as
/// words ([HeaderParts]) and the note's tools as their model ([toolsModel]), and answers the line ([HeaderRow]); the
/// tabs are the style's as ever. Until 2026-11-01 it was one of six versions, picked under Settings › Developer, and
/// today's bar, every control its own ring, was drawn here; the contact sheet ended with Grouped command (Matt: "we
/// currently have too many appearance settings for different title bar layouts and stuff").
///
/// The bar is the app's, not any screen's: shell/app_shell.dart draws it once, in shell/app_tab_bar.dart's box, which
/// is the web's `.app-tabBar`. It fills the box it is given, across the whole window: the bar's own gutters
/// (`--app-bar-start`, `--app-bar-end`) are kept in here, because the row of tabs runs past them to the window's
/// edges.
///
/// Differs from the web:
/// - What the page read from stores of its own comes in by the constructor: the workspaces ([workspaces], for the
///   pill on a tab), and each open note's title as its editor has it ([liveTitles]).
/// - The screen's own controls were drawn into the bar's DOM through a portal (core/topBarTools.ts); here they are
///   handed in as [tools] and [tail], which shell/top_bar_tools.dart carries from the screen to the shell.
/// - The row of tabs is not a `tablist` to a screen reader, whose tab bar may hold nothing but tabs where the page's
///   also held the chips, the crosses and the +: it is a group named "Notes you have open", and each tab in it is a
///   tab, selected or not.
/// - `title` (the tooltip on a ring) and `aria-haspopup` have no counterpart; `aria-current="page"` is said as
///   selected.
/// - The Islands on a window in two panes keep to one line whatever is open, the tabs' capsule taking the room
///   between the other two. The page's stylesheet meant that and did not get it: with more tabs than fit, its
///   third capsule wrapped under the first and the line ran off the top of the window, and with no tabs at all the
///   third capsule stood beside the first.
/// - The Islands' third capsule is not drawn when it would hold nothing, which the page never came to (a note's
///   screen always has tools).
/// - The smoke at the row's fading ends is not drawn (notes/tabs/tab_row.dart says what else differs in the row).
class NoteTabs extends StatefulWidget {
  const NoteTabs({
    super.key,
    this.style = TopBarStyle.classic,
    required this.tabs,
    required this.activeId,
    required this.onOpen,
    required this.onClose,
    this.onDelete,
    this.onNew,
    this.groups = TabGroups.none,
    this.onGroups,
    this.onCloseTabs,
    this.onSidebar,
    this.sidebarOpen = false,
    this.onAside,
    this.asideOpen = false,
    this.onHome,
    this.atHome = false,
    this.onMove,
    this.onGoBack,
    this.onGoOn,
    this.canGoBack = false,
    this.canGoOn = false,
    this.onOrganizations,
    this.organizations = const [],
    this.onOrganization,
    this.onNotifications,
    this.onSettings,
    this.onAcademy,
    this.unread = false,
    this.atNotifications = false,
    this.onRename,
    this.workspaces = const Workspaces(),
    this.liveTitles,
    this.tools,
    this.tail,
    this.presence,
    this.activity,
    this.finePointer,
    this.grouping = true,
    this.toolsModel,
    this.onSearch,
    this.onAllNotes,
    this.filters,
    this.onFolders,
    this.atFolders = false,
  });

  /// Every note by folder, All notes in its icon view (Matt, 2026-10-29: "add a folder icon to the top near home and
  /// sidebar to show all notes in the folder / icon view"): a row of the line's •••, and whether that page is the one
  /// showing.
  final VoidCallback? onFolders;
  final bool atFolders;

  /// The home page's Filters, a circle of the bar's after the title pill ([HeaderParts.filters]).
  final BarButton? filters;

  /// What the screen's [tools] are, as the actions they draw.
  final ValueListenable<NoteToolsModel>? toolsModel;

  /// The command palette, which the title pill opens, and every note.
  final VoidCallback? onSearch;
  final VoidCallback? onAllNotes;

  /// How the bar is laid out; Classic unless Settings says otherwise.
  final TopBarStyle style;

  /// The open notes, in the order drawn: each group's tabs together.
  final List<Note> tabs;

  /// The tab being read, or empty.
  final String activeId;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onClose;

  /// Deletes a tab's note, to the Trash with an Undo: the tab's menu's Delete note.
  final ValueChanged<String>? onDelete;

  /// A new note in a new tab: the + at the end of the row.
  final VoidCallback? onNew;

  /// Chrome-style groups over the tabs.
  final TabGroups groups;
  final ValueChanged<TabGroups>? onGroups;

  /// Close several tabs at once: a whole group.
  final ValueChanged<List<String>>? onCloseTabs;

  /// The floating list of every note, or the docked sidebar's column.
  final VoidCallback? onSidebar;
  final bool sidebarOpen;

  /// The right-hand aside; absent when there is nothing for it to show, and so is the icon.
  final VoidCallback? onAside;
  final bool asideOpen;

  /// The home page, and whether it is the page showing.
  final VoidCallback? onHome;
  final bool atHome;

  /// A tab moved to sit somewhere else in the row. `grouped` says the drag has already settled which group the tab
  /// is in; without it - a move by the keys - the row works that out from where it lands.
  final void Function(String id, int to, {bool grouped})? onMove;

  /// Back and forward through where he has been, beside the sidebar's button. Each arrow is drawn for its own
  /// callback: simple mode (GHST-103) has Back and no Forward.
  final VoidCallback? onGoBack;
  final VoidCallback? onGoOn;
  final bool canGoBack;
  final bool canGoOn;

  /// Your organizations in Settings, from the people icon before the bell; absent, and there is none.
  final VoidCallback? onOrganizations;

  /// The organizations you belong to, for the people icon's picker. With any, the icon opens the picker and a pick
  /// opens that organization's dashboard ([onOrganization]); with none, it goes to Settings ([onOrganizations]).
  final List<OrgLike> organizations;
  final ValueChanged<String>? onOrganization;

  /// Opens or closes the notifications drawer, from the bell; absent, and there is no bell.
  final VoidCallback? onNotifications;

  /// Opens Settings, from the cog after the bell; absent, and there is no cog.
  final VoidCallback? onSettings;

  /// Opens Ghost Academy, from the mortarboard just before the button for you; absent, and there is none.
  final VoidCallback? onAcademy;

  /// Whether something unread and wanted has arrived: the bell wears its ring and a dot.
  final bool unread;

  /// Whether the notifications drawer is open: the bell is lit and says it is expanded.
  final bool atNotifications;

  /// A canvas or a book renamed from its tab. Absent, and no tab offers it.
  final void Function(String id, String title)? onRename;

  /// The workspaces, for the pill a filed note's tab wears.
  final Workspaces workspaces;

  /// Each open note's title as its editor has it now; the app's own store unless a test brings one.
  final LiveTitles? liveTitles;

  /// The screen's own controls, in the bar's slot (`.slot`).
  final Widget? tools;

  /// The screen's last control, its More, after the bell and the cog (`.tail`).
  final Widget? tail;

  /// Who else is here before the people icon: the Claude chip while an AI is online (lib/shell/ai_chip.dart;
  /// docs/CLAUDE_LIVE.md). The app's own; the web's bar has none yet.
  final Widget? presence;

  /// The ring of the app's running work, beside the app's own (lib/activity/activity_ring.dart; docs/ACTIVITY.md):
  /// the app hands it always, grey while nothing runs.
  final Widget? activity;

  /// Whether the pointer is a mouse (`(hover: hover) and (pointer: fine)`): a longer fade at the row's ends, flyouts
  /// in the menus where they fit. The device's answer unless a test says.
  final bool? finePointer;

  /// Whether tabs can be put in groups from here: a tab's menu's group rows and a chip's Colour. Off in simple mode
  /// (GHST-103; Matt: "fancy features hidden behind more"), which keeps the tabs, a new tab, Close tab and Delete
  /// note; a group made in advanced still draws its chip, with Rename, Ungroup and Close group to take it apart.
  final bool grouping;

  /// How tall the row of tabs draws for [tabs], before the bar has shrunk it: a tab's height, or a pixel more where
  /// a tab wears a workspace's pill under its border.
  static double rowHeight(Tokens t, TabShape shape, {required bool pills}) {
    final tabH = t.len('app-tab-h');
    if (shape == TabShape.capsule) return tabH - 4;
    final small = t.fontSize('sm');
    final line = normalLine(t.fontSize('md'), dpr: t.css.lineDpr);
    // A border is as wide as a phone draws it: whole device pixels, the kit's hairline.
    final hair = t.len('glacier-hairline');
    final pill = small + 2 * 0.52 * small + 2 * hair;
    final inside = 2 * t.space(1) * 1.3 + (pills ? math.max(pill, line) : line);
    return math.max(tabH, inside + (shape == TabShape.tab ? hair : 0));
  }

  @override
  State<NoteTabs> createState() => _NoteTabsState();
}

class _NoteTabsState extends State<NoteTabs> {
  /// The menu a group's chip or a tab has open.
  ({bool group, String id})? _menu;

  /// The chip being renamed, and the tab whose name is open as a field.
  String? _renaming;
  String? _naming;

  final Map<String, GlobalKey> _tabAnchors = {};
  final Map<String, GlobalKey> _closeKeys = {};
  final Map<String, GlobalKey> _chipAnchors = {};

  GlobalKey _key(Map<String, GlobalKey> keys, String id) => keys.putIfAbsent(id, () => GlobalKey(debugLabel: id));

  LiveTitles get _live => widget.liveTitles ?? liveTitles;
  bool get _fine => widget.finePointer ?? mousePointer;

  void _change(TabGroups next) => widget.onGroups?.call(next);

  void _startGroup(String noteId) {
    final made = newGroup(widget.groups, noteId);
    _change(made.groups);
    // Named "Group" to begin with, and straight into its name to be called something better.
    setState(() => _renaming = made.id);
  }

  String _titleOf(Note note) {
    final title = _live.titleNow(note.id, note.updatedAt, noteTitle(note.body));
    return title.isEmpty ? 'Untitled' : title;
  }

  /// The end of a rename, however it ends. A name is only sent on if it is a name and is not the one the tab has.
  void _keepName(String id, String was, String words, bool keep) {
    final kept = words.trim();
    setState(() => _naming = null);
    if (keep && kept.isNotEmpty && kept != was) widget.onRename?.call(id, kept);
  }

  /// The tabs, and no line at all when nothing is open; the Ledger keeps the row whatever is open, since Home is
  /// pinned in it.
  ({Widget row, bool pills})? _tabRow(Tokens t, TabShape shape) {
    final tabs = widget.tabs;
    final pinnedHome = widget.style == TopBarStyle.ledger;
    if (tabs.isEmpty && !pinnedHome) return null;
    final groups = widget.groups;
    final spaces = widget.workspaces;
    final ids = [for (final note in tabs) note.id];
    final entries = <TabRowEntry>[];
    var pills = false;
    if (pinnedHome && widget.onHome != null) {
      entries.add(TabRowEntry(kind: RowKind.homeTab, child: HomeTab(onPressed: widget.onHome!, atHome: widget.atHome)));
    }
    for (var at = 0; at < tabs.length; at++) {
      final note = tabs[at];
      final title = _titleOf(note);
      final active = note.id == widget.activeId;
      final group = groups.groupOf(note.id);
      final firstOfGroup = group != null && (at == 0 || groups.of[tabs[at - 1].id] != group.id);
      if (group != null && firstOfGroup) {
        final count = tabs.where((each) => groups.of[each.id] == group.id).length;
        final open = _menu != null && _menu!.group && _menu!.id == group.id;
        entries.add(
          TabRowEntry(
            kind: RowKind.chip,
            id: group.id,
            count: count,
            collapsed: group.collapsed,
            center: true,
            marginStart: 2,
            marginEnd: 2,
            child: GroupChip(
              group: group,
              count: count,
              renaming: _renaming == group.id,
              anchorKey: _key(_chipAnchors, group.id),
              onToggle: () => _change(toggleGroup(groups, group.id)),
              onMenu: () => setState(() => _menu = (group: true, id: group.id)),
              onRename: (name) {
                _change(renameGroup(groups, group.id, name));
                setState(() => _renaming = null);
              },
              menu: !open
                  ? null
                  : GroupMenu(
                      anchor: _key(_chipAnchors, group.id),
                      group: group,
                      groups: groups,
                      tabIds: ids,
                      coarse: !_fine,
                      onDismiss: () => setState(() => _menu = null),
                      onRename: () => setState(() => _renaming = group.id),
                      onGroups: _change,
                      onCloseTabs: widget.onCloseTabs,
                      colours: widget.grouping,
                    ),
            ),
          ),
        );
      }
      // A folded group draws only its chip.
      if (group != null && group.collapsed) continue;
      // The workspace the note is filed in, worn as its own coloured pill in front of the name.
      final spaceId = spaces.of[note.id];
      final space = spaceId == null ? null : spaces.list.where((w) => w.id == spaceId).firstOrNull;
      if (space != null) pills = true;
      final open = _menu != null && !_menu!.group && _menu!.id == note.id;
      // A canvas or a book is named by its front matter and has no first line to write, so the row offers it.
      final renames = widget.onRename != null && (isCanvasBody(note.body) || isBookBody(note.body));
      entries.add(
        TabRowEntry(
          kind: RowKind.tab,
          id: note.id,
          groupId: group?.id,
          child: NoteTab(
            shape: shape,
            title: title,
            note: note,
            active: active,
            space: space,
            group: group,
            // In every way but Classic the cross is the open tab's alone; the others close from their menu.
            showClose: widget.style == TopBarStyle.classic || active,
            onOpen: () => widget.onOpen(note.id),
            onClose: () => widget.onClose(note.id),
            onNudge: widget.onMove == null ? null : (by) => widget.onMove!(note.id, at + by),
            naming: _naming == note.id,
            onNamed: (words, keep) => _keepName(note.id, title, words, keep),
            anchorKey: _key(_tabAnchors, note.id),
            closeKey: _key(_closeKeys, note.id),
            menu: !open
                ? null
                : TabMenu(
                    anchor: _key(_tabAnchors, note.id),
                    noteId: note.id,
                    title: title,
                    groups: groups,
                    coarse: !_fine,
                    onDismiss: () => setState(() => _menu = null),
                    onRename: renames ? () => setState(() => _naming = note.id) : null,
                    onNewGroup: widget.grouping ? () => _startGroup(note.id) : null,
                    onGroups: widget.grouping ? _change : null,
                    onCloseTab: () => widget.onClose(note.id),
                    onDeleteNote: widget.onDelete == null ? null : () => widget.onDelete!(note.id),
                  ),
          ),
        ),
      );
    }
    // No + after the last tab: a new note is under the bar's ••• (Matt, 2026-10-29: "Put the all files folder icon
    // under the more menu as well as the + button in the header"), ⌘N, the palette and the home page's dock.
    final capsule = shape == TabShape.capsule;
    final row = TabRow(
      shape: shape,
      entries: entries,
      activeId: widget.activeId,
      groups: groups,
      onMove: widget.onMove,
      onGroups: widget.onGroups,
      // A finger held on a tab and let go where it was, or a mouse's right-click: that tab's menu.
      onHeld: (id) => setState(() => _menu = (group: false, id: id)),
      gap: switch (shape) { TabShape.tab => 2, TabShape.indexLine => t.space(4), TabShape.capsule => t.space(1) },
      // The Ledger's tabs are the bar's top row, so on the Mac they are the row that clears the window's buttons.
      paddingStart: capsule ? t.space(2) : t.len('app-bar-start') + (widget.style == TopBarStyle.ledger ? trafficLightsRoom(t) : 0),
      paddingEnd: capsule ? t.space(2) : t.len('app-bar-end'),
      minHeight: capsule ? t.len('app-tab-h') - 4 : t.len('app-tab-h'),
      lineColor: switch (shape) {
        // `--tab-line`: the ink mixed into the page's own paper, opaque, so the line laid over itself is one colour.
        TabShape.tab => t.colorOf('color-mix(in oklch, var(--app-ink) 22%, var(--app-paper))'),
        TabShape.indexLine => t.color('app-rule'),
        TabShape.capsule => null,
      },
      // On a desktop the ends wear no smoke, so the fade is the whole of it, and runs longer.
      fade: _fine ? 32 : 12,
      clipRadius: capsule ? t.radius('full') : null,
      // The Islands: the row is a capsule of glass of its own, a capsule's height with this padding and hairline
      // round it.
      frame: !capsule
          ? null
          : (row) => BarGlass(
                head: true,
                radius: t.radius('full'),
                border: BorderSide(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')),
                shadows: t.cssShadows('app-float-shadow'),
                child: Padding(padding: EdgeInsets.symmetric(vertical: 3 + t.len('glacier-hairline'), horizontal: t.len('glacier-hairline')), child: row),
              ),
      closeKeys: _closeKeys,
    );
    return (row: row, pills: pills);
  }

  // ---- the line of controls --------------------------------------------------------------------------------------------

  /// The controls as words, for the line to draw: each with the old bar's label, so a screen reader hears the same bar.
  HeaderParts _parts(double room) {
    final w = widget;
    final model = w.toolsModel?.value;
    final note = model == null ? null : noteActsOf(model);
    final active = w.tabs.where((each) => each.id == w.activeId).firstOrNull;
    final picks = w.organizations.isNotEmpty && w.onOrganization != null;
    return HeaderParts(
      home: w.onHome == null ? null : HeaderAct(id: 'home', label: 'Home', word: 'Home', hue: 'blue', house: true, onPress: w.onHome, on: w.atHome, current: w.atHome),
      sidebar: w.onSidebar == null
          ? null
          : HeaderAct(id: 'sidebar', label: 'All your notes', word: 'Notes', hue: 'indigo', icon: Lucide.panelLeft, onPress: w.onSidebar, on: w.sidebarOpen, expanded: w.sidebarOpen, toggle: sidebarToggle),
      // Every note by folder and a new note are rows of the bar's ••• (HeaderParts.kept): their words are their whole names.
      folders: w.onFolders == null
          ? null
          : HeaderAct(id: 'folders', label: 'All notes, by folder', word: 'All notes, by folder', hue: 'amber', icon: Lucide.folder, onPress: w.onFolders, on: w.atFolders, current: w.atFolders),
      back: w.onGoBack == null ? null : HeaderAct(id: 'back', label: 'Back to where you were', word: 'Back', hue: 'cyan', icon: Lucide.arrowLeft, onPress: w.canGoBack ? w.onGoBack : null),
      forward: w.onGoOn == null ? null : HeaderAct(id: 'forward', label: 'Forward again', word: 'Forward', hue: 'cyan', icon: Lucide.arrowRight, onPress: w.canGoOn ? w.onGoOn : null),
      view: note?.view,
      actions: note?.actions ?? const [],
      more: note?.more,
      menu: model?.menu,
      search: w.onSearch == null ? null : HeaderAct(id: 'search', label: 'Search or run a command', word: 'Search', hue: 'blue', icon: Lucide.search, onPress: w.onSearch),
      newNote: w.onNew == null ? null : HeaderAct(id: 'new', label: 'New note', word: 'New note', hue: 'green', icon: Lucide.plus, onPress: w.onNew),
      allNotes: w.onAllNotes == null ? null : HeaderAct(id: 'all', label: 'Every note', word: 'Browse', hue: 'indigo', icon: Lucide.layoutGrid, onPress: w.onAllNotes),
      organizations: w.onOrganizations == null
          ? null
          : HeaderAct(id: 'organizations', label: 'Organizations', word: picks ? 'All organizations…' : 'Organizations', hue: 'magenta', icon: Lucide.userGroup, onPress: w.onOrganizations),
      orgs: w.organizations,
      onOrganization: w.onOrganization,
      bell: w.onNotifications == null
          ? null
          : HeaderAct(
              id: 'bell',
              label: w.unread ? 'Notifications, something new' : 'Notifications',
              word: 'Notifications',
              hue: 'amber',
              icon: Lucide.bell,
              onPress: w.onNotifications,
              on: w.unread || w.atNotifications,
              expanded: w.atNotifications,
              dot: w.unread,
              toggle: notificationsToggle,
            ),
      settings: w.onSettings == null ? null : HeaderAct(id: 'settings', label: 'Settings', word: 'Settings', hue: 'lime', icon: Lucide.settings, onPress: w.onSettings),
      academy: w.onAcademy == null ? null : HeaderAct(id: 'academy', label: 'Academy', word: 'Academy', hue: 'purple', icon: Lucide.graduationCap, onPress: w.onAcademy),
      aside: w.onAside == null
          ? null
          : HeaderAct(id: 'aside', label: 'Side panel', word: 'Side panel', hue: 'mint', icon: Lucide.panelLeft, mirrored: true, onPress: w.onAside, on: w.asideOpen, expanded: w.asideOpen, toggle: asideToggle),
      presence: w.presence,
      activity: w.activity,
      filters: w.filters,
      // A screen with no model is drawn from its widgets; a note's are redrawn from its model.
      tools: model == null ? w.tools : null,
      tail: model == null ? w.tail : null,
      title: active == null || w.atHome ? null : _titleOf(active),
      atHome: w.atHome,
      unread: w.unread,
      fine: _fine,
      room: room,
    );
  }

  /// The line, laid out on one line: the start, the middle taking what is left, the end.
  Widget _versionLine(HeaderRow row, double gap) => Row(
        spacing: gap,
        children: [
          ...row.lead,
          Expanded(child: row.centre ?? const SizedBox.shrink()),
          ...row.trail,
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (widget.onSidebar == null && widget.onGoBack == null && widget.tabs.isEmpty) return const SizedBox.shrink();
    final model = widget.toolsModel;
    return ListenableBuilder(
      listenable: model == null ? _live : Listenable.merge([_live, model]),
      builder: (context, _) => LayoutBuilder(builder: (context, constraints) => _bar(context, constraints)),
    );
  }

  Widget _bar(BuildContext context, BoxConstraints constraints) {
    final t = context.tokens;
    final style = widget.style;
    // Which shape a tab takes: a tab on a line, a word on an index line, or a capsule.
    final shape = switch (style) { TopBarStyle.masthead => TabShape.indexLine, TopBarStyle.islands => TabShape.capsule, _ => TabShape.tab };
    final split = t.attrs.containsKey('split');
    final ring = t.len('app-bar-ring');
    final start = t.len('app-bar-start'), end = t.len('app-bar-end');
    // `.bar { gap: var(--glacier-space-1) }` between its two rows.
    final between = t.space(1);
    // A narrow phone carries seven rings on this line: the rings keep their size, the air between them gives.
    final gap = MediaQuery.sizeOf(context).width <= 440 ? t.space(1) : t.space(2);
    final hairline = t.len('glacier-hairline');
    final tabRow = _tabRow(t, shape);
    // Grouped command draws the line of controls (lib/shell/header/grouped_command_row.dart).
    final room = constraints.maxWidth - start - end - trafficLightsRoom(t);
    final version = groupedCommandRow(context, _parts(room));

    if (style == TopBarStyle.islands) return _islands(t, constraints, tabRow?.row, split: split, version: version);

    final Widget top;
    final double topH;
    if (style == TopBarStyle.ledger) {
      // The tool row under the tabs is the open tab's own ground, with a line under it, the bar's whole width: the
      // header's glass, as the open tab is, where it was paper - a solid strip across the glass (Matt, 2026-11-01:
      // "the header is a mix of glass and not glass elements").
      topH = ring + 4 + hairline;
      top = Container(
        padding: EdgeInsets.fromLTRB(start, 2, end, 2),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.color('glacier-border-subtle'), width: hairline)),
        ),
        child: _versionLine(version, gap),
      );
    } else {
      // The Mac's three window buttons sit at this row's start: the first control begins after their room.
      final lights = trafficLightsRoom(t);
      topH = ring;
      final controls = Padding(padding: EdgeInsets.only(right: end), child: _versionLine(version, gap));
      top = Padding(padding: EdgeInsets.only(left: start + lights), child: lights > 0 ? MacLightsRow(child: controls) : controls);
    }

    // The column: `justify-content: center`, with the tabs pushed to the bar's foot wherever they are the second row
    // (`.tabs { margin-block-start: auto }`). A row that will not fit gives way down to a tab's height and no
    // further, and what is still over hangs evenly past both edges.
    final least = t.len('app-tab-h');
    final natural = tabRow == null ? 0.0 : NoteTabs.rowHeight(t, shape, pills: tabRow.pills);
    final ledger = style == TopBarStyle.ledger;
    final total = topH + (tabRow == null ? 0 : between + natural);
    final height = constraints.hasBoundedHeight ? constraints.maxHeight : total;
    var rowH = natural;
    double topY, rowY = 0;
    if (tabRow == null) {
      topY = (height - topH) / 2;
    } else {
      final free = height - total;
      if (free < 0) rowH = math.max(least, natural + free);
      final lead = (height - (topH + between + rowH)) / 2;
      if (ledger) {
        rowY = lead;
        topY = lead + rowH + between;
      } else if (free >= 0) {
        topY = 0;
        rowY = height - rowH;
      } else {
        topY = lead;
        rowY = lead + topH + between;
      }
    }
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, right: 0, top: topY, height: topH, child: top),
          if (tabRow != null) Positioned(left: 0, right: 0, top: rowY, height: rowH, child: ledger && titlebarOverlay(t) ? MacLightsRow(child: tabRow.row) : tabRow.row),
        ],
      ),
    );
  }

  /// The Islands: three capsules of glass over the page - the way around at the start, the screen's own at the end,
  /// and the tabs between them on a window in two panes, on a line of their own on a phone.
  Widget _islands(Tokens t, BoxConstraints constraints, Widget? tabRow, {required bool split, required HeaderRow version}) {
    final ring = t.len('app-bar-ring');
    final hairline = t.len('glacier-hairline');
    final start = t.len('app-bar-start'), end = t.len('app-bar-end');
    final gap = t.space(2);
    final capH = ring + 6 + 2 * hairline;
    // A capsule's height with its padding and hairline round it, so a folded group's chip does not move.
    final rowH = t.len('app-tab-h') - 4 + 6 + 2 * hairline;

    // The line in the Islands: its start in the first capsule, its end in the last, its middle between them.
    final Widget capsule = BarCapsule(children: version.lead);
    final way = titlebarOverlay(t) ? MacLightsRow(child: capsule) : capsule;
    final ownCapsule = version.trail.isEmpty ? null : BarCapsule(children: version.trail);
    final middle = version.centre;
    final tabs = tabRow == null ? null : SizedBox(height: rowH, child: tabRow);

    final Widget body;
    final double total;
    if (split) {
      total = tabs == null ? capH : math.max(capH, rowH);
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          way,
          SizedBox(width: gap),
          // `flex: 1 1 auto; max-inline-size: 44rem; margin-inline: auto`
          Expanded(
            child: tabs == null
                ? const SizedBox.shrink()
                : Center(heightFactor: 1, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: t.lenOf('44rem')), child: SizedBox(width: double.infinity, child: tabs))),
          ),
          if (middle != null) ...[SizedBox(width: gap), ConstrainedBox(constraints: const BoxConstraints(maxWidth: 260), child: middle)],
          if (ownCapsule != null) ...[SizedBox(width: gap), ownCapsule],
        ],
      );
    } else {
      total = capH + (tabs == null ? 0 : gap + rowH);
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              way,
              if (middle != null) ...[SizedBox(width: gap), Expanded(child: SizedBox(height: capH, child: middle)), SizedBox(width: gap)] else const Spacer(),
              ?ownCapsule,
            ],
          ),
          if (tabs != null) ...[SizedBox(height: gap), tabs],
        ],
      );
    }
    final height = constraints.hasBoundedHeight ? constraints.maxHeight : total;
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The Mac's window buttons are at the start of the capsules' row, which begins after their room.
          Positioned(left: start + trafficLightsRoom(t), right: end, top: (height - total) / 2, height: total, child: body),
        ],
      ),
    );
  }
}
