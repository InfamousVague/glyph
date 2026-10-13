import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/book.dart';
import '../core/canvas_body.dart';
import '../core/live_titles.dart';
import '../core/note.dart';
import '../core/note_text.dart';
import '../core/tabs.dart';
import '../core/workspaces.dart';
import '../shell/desktop/mac_lights.dart';
import '../shell/pop_menu.dart';
import '../shell/top_bar.dart';
import '../shell/wide_screen.dart';
import 'floating_card.dart';
import 'tabs/bar_icon.dart';
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
    this.unread = false,
    this.atNotifications = false,
    this.onRename,
    this.workspaces = const Workspaces(),
    this.liveTitles,
    this.tools,
    this.tail,
    this.finePointer,
  });

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

  /// Back and forward through where he has been, beside the sidebar's button.
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

  /// Whether the pointer is a mouse (`(hover: hover) and (pointer: fine)`): a longer fade at the row's ends, flyouts
  /// in the menus where they fit. The device's answer unless a test says.
  final bool? finePointer;

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

  /// The organizations' picker, open, and the icon it hangs from.
  bool _pickingOrg = false;
  final GlobalKey _orgsKey = GlobalKey(debugLabel: 'organizations');

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

  // ---- the pieces, each once, placed by the style below ------------------------------------------------------------

  Widget? _homeRing() => widget.onHome == null
      ? null
      : BarRing(glyph: BarGlyph.house, iconSize: 20, label: 'Home', onPressed: widget.onHome, on: widget.atHome, current: widget.atHome);

  Widget? _homeWord() => widget.onHome == null ? null : BarWord(word: 'Home', onPressed: widget.onHome, on: widget.atHome, current: widget.atHome);

  Widget? _sidebarRing() => widget.onSidebar == null
      ? null
      // `data-sidebar-toggle`: a press on it is the icon's own to answer, not a press outside its card.
      : FloatingCardToggle(
          toggle: sidebarToggle,
          child: BarRing(glyph: BarGlyph.panelLeft, iconSize: 20, label: 'All your notes', onPressed: widget.onSidebar, on: widget.sidebarOpen, expanded: widget.sidebarOpen),
        );

  Widget? _sidebarWord() =>
      widget.onSidebar == null
          ? null
          : FloatingCardToggle(
              toggle: sidebarToggle,
              child: BarWord(word: 'Notes', label: 'All your notes', onPressed: widget.onSidebar, on: widget.sidebarOpen, expanded: widget.sidebarOpen),
            );

  /// Where he has been: the same two arrows a browser has, in the same place, beside the sidebar's button.
  List<Widget> _arrows() => widget.onGoBack == null || widget.onGoOn == null
      ? const []
      : [
          BarRing(glyph: BarGlyph.arrowLeft, iconSize: 19, label: 'Back to where you were', onPressed: widget.canGoBack ? widget.onGoBack : null),
          BarRing(glyph: BarGlyph.arrowRight, iconSize: 19, label: 'Forward again', onPressed: widget.canGoOn ? widget.onGoOn : null),
        ];

  /// The Masthead's: Back as a word, and Forward only when there is somewhere forward to go, since it seldom is.
  List<Widget> _arrowWords() => widget.onGoBack == null || widget.onGoOn == null
      ? const []
      : [
          BarWord(word: 'Back', label: 'Back to where you were', leading: BarGlyph.arrowLeft, onPressed: widget.canGoBack ? widget.onGoBack : null),
          if (widget.canGoOn) BarWord(word: 'Forward', label: 'Forward again', trailing: BarGlyph.arrowRight, onPressed: widget.onGoOn),
        ];

  /// Organizations: with a picker, the icon opens it and a second press closes it again; without, it goes to Settings.
  Widget? _orgs({required bool asWord}) {
    final all = widget.onOrganizations;
    if (all == null) return null;
    final pick = widget.onOrganization;
    final picks = widget.organizations.isNotEmpty && pick != null;
    final press = picks ? () => setState(() => _pickingOrg = !_pickingOrg) : all;
    final expanded = picks ? _pickingOrg : null;
    final trigger = asWord
        ? BarWord(word: 'Teams', label: 'Organizations', onPressed: press, expanded: expanded, anchorKey: _orgsKey)
        : BarRing(glyph: BarGlyph.people, iconSize: 19, label: 'Organizations', onPressed: press, expanded: expanded, anchorKey: _orgsKey);
    if (!picks || !_pickingOrg) return trigger;
    // A picker of the organizations you belong to, hung from the icon: a pick goes straight to that one's dashboard;
    // the last row is the whole list in Settings, where one is made or an invitation answered.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        trigger,
        PopMenu(
          anchor: GlacierAnchor.key(_orgsKey),
          placement: Placement.bottomEnd,
          reach: PopReach.down,
          ariaLabel: 'Choose an organization',
          coarse: !_fine,
          onDismiss: () => setState(() => _pickingOrg = false),
          children: [
            const GlacierMenuLabel(child: Text('Organizations')),
            for (final org in widget.organizations) GlacierMenuItem(onSelect: () => pick(org.id), icon: HueDot(org.hue), child: Text(org.name)),
            const GlacierMenuSeparator(),
            GlacierMenuItem(onSelect: all, child: const Text('All organizations…')),
          ],
        ),
      ],
    );
  }

  /// The bell, on while something unread waits: a dot, no number.
  Widget? _bell() => widget.onNotifications == null
      ? null
      // `data-notifications-toggle`
      : FloatingCardToggle(
          toggle: notificationsToggle,
          child: BarRing(
            glyph: BarGlyph.bell,
            iconSize: 19,
            label: widget.unread ? 'Notifications, something new' : 'Notifications',
            onPressed: widget.onNotifications,
            on: widget.unread || widget.atNotifications,
            expanded: widget.atNotifications,
            dot: widget.unread,
          ),
        );

  Widget? _cog() => widget.onSettings == null ? null : BarRing(glyph: BarGlyph.settings, iconSize: 19, label: 'Settings', onPressed: widget.onSettings);

  /// The aside's toggle, last of all: the sidebar's icon reversed.
  Widget? _asideRing() => widget.onAside == null
      ? null
      // `data-aside-toggle`
      : FloatingCardToggle(
          toggle: asideToggle,
          child: BarRing(glyph: BarGlyph.panelLeft, iconSize: 20, label: 'Side panel', onPressed: widget.onAside, on: widget.asideOpen, expanded: widget.asideOpen, mirrored: true),
        );

  /// `.top`: the way to the notes and back at one end, whatever the screen puts in the slot pushed to the other.
  Widget _toolRow(double gap, double endInset, List<Widget?> before, List<Widget?> after) {
    final tools = widget.tools;
    return ToolRow(
      gap: gap,
      endInset: endInset,
      before: before.nonNulls.toList(),
      // `.slot { overflow-x: auto }`: if the screen's own controls ever run out of room, they scroll rather than
      // the last of them being cut off.
      slot: tools == null ? const SizedBox.shrink() : SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: tools),
      after: after.nonNulls.toList(),
    );
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
                    onNewGroup: () => _startGroup(note.id),
                    onGroups: _change,
                    onCloseTab: () => widget.onClose(note.id),
                    onDeleteNote: widget.onDelete == null ? null : () => widget.onDelete!(note.id),
                  ),
          ),
        ),
      );
    }
    // After the last tab, so it moves along with the row: a new note, in a tab of its own.
    if (widget.onNew != null) {
      entries.add(TabRowEntry(kind: RowKind.newTab, center: true, marginStart: t.space(1), child: NewTabButton(onPressed: widget.onNew!)));
    }
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

  @override
  Widget build(BuildContext context) {
    if (widget.onSidebar == null && widget.onGoBack == null && widget.tabs.isEmpty) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: _live,
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

    if (style == TopBarStyle.islands) return _islands(t, constraints, tabRow?.row, split: split);

    final Widget top;
    final double topH;
    if (style == TopBarStyle.ledger) {
      // The tool row under the tabs is the open tab's own ground: paper, with a line under it, the bar's whole width.
      topH = ring + 4 + hairline;
      top = Container(
        padding: EdgeInsets.fromLTRB(start, 2, end, 2),
        decoration: BoxDecoration(
          color: t.color('glacier-bg'),
          border: Border(bottom: BorderSide(color: t.color('glacier-border-subtle'), width: hairline)),
        ),
        child: _toolRow(gap, 0, [_sidebarRing(), ..._arrows()], [_orgs(asWord: false), _bell(), _cog(), widget.tail, _asideRing()]),
      );
    } else {
      // The Mac's three window buttons sit at this row's start: the first control begins after their room.
      final lights = trafficLightsRoom(t);
      topH = ring;
      final controls = style == TopBarStyle.masthead
          ? _toolRow(gap, end, [_homeWord(), _sidebarWord(), ..._arrowWords()], [_orgs(asWord: true), _bell(), _cog(), widget.tail, _asideRing()])
          : _toolRow(gap, end, [_homeRing(), _sidebarRing(), ..._arrows()], [_orgs(asWord: false), _bell(), _cog(), widget.tail, _asideRing()]);
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
  Widget _islands(Tokens t, BoxConstraints constraints, Widget? tabRow, {required bool split}) {
    final ring = t.len('app-bar-ring');
    final hairline = t.len('glacier-hairline');
    final start = t.len('app-bar-start'), end = t.len('app-bar-end');
    final gap = t.space(2);
    final capH = ring + 6 + 2 * hairline;
    // A capsule's height with its padding and hairline round it, so a folded group's chip does not move.
    final rowH = t.len('app-tab-h') - 4 + 6 + 2 * hairline;

    final Widget capsule = BarCapsule(children: [?_homeRing(), ?_sidebarRing(), ..._arrows()]);
    final way = titlebarOverlay(t) ? MacLightsRow(child: capsule) : capsule;
    final own = <Widget>[?_orgs(asWord: false), ?_bell(), ?_cog(), ?widget.tail, ?_asideRing()];
    final tools = widget.tools;
    // The slot is a place in the capsule's row whether or not the screen has put anything in it.
    final ownCapsule = own.isEmpty && tools == null ? null : BarCapsule(children: [tools ?? const SizedBox.shrink(), ...own]);
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
          if (ownCapsule != null) ...[SizedBox(width: gap), ownCapsule],
        ],
      );
    } else {
      total = capH + (tabs == null ? 0 : gap + rowH);
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [way, const Spacer(), ?ownCapsule]),
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
