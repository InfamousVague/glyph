/// An organization's dashboard. A port of `src/app/notes/OrganizationScreen.tsx` with OrganizationScreen.module.css
/// (docs/TEAMS.md; Matt: "Design and deploy a dashboard for organizations when clicking an organization in the
/// header don't take me to the settings, instead, take me to this dashboard page and have a organization settings
/// icon on that").
///
/// Built as All notes is (lib/notes/all_notes_screen.dart): the glass bar with the way home, the organization's
/// name with its colour, the clock to its audit log and the cog to its settings; under it the scroller with its
/// smoke. On it, in order: the other organizations as pills, when there is more than one; the hero (the colour,
/// the name, how many and what you are, what its workspace is, New and Invite); the newest notes filed in its
/// workspace, as cards; the members with their roles, your colour here, and for an owner or an admin the invite
/// field and the invite links; and the activity, the organization's own news from the feed, newest first.
///
/// On a page 44rem wide the members stand beside the notes and the activity. Invited and not yet a member, the
/// page is the invitation with Accept and Decline; gone from the list, it says so. Signed out or with Local only
/// on, nothing can arrive, and the page says why with a word to Account.
///
/// The members are read when the page opens, when the organization's news arrives, and when a pull from the top
/// takes the feed again.
///
/// At its bottom end corner, the dock every page has (lib/shell/page_dock.dart, [OrganizationScreen.dock]): Claude,
/// a new note in this organization, Invite for an owner or an admin, and the organization's settings at its foot.
/// Each is the page's own: the hero's New and Invite, the bar's cog.
///
/// What differs from the web page:
/// - The account, the organizations and the feed are the [AccountServices] it is handed; the workspaces are theirs.
/// - **Who is in the app now** comes from the live service on the web (`core/live/presence.ts`), which is not
///   ported: [OrganizationScreen.seen] is handed in, and is nobody until it is. A member's "Jump to cursor" opens
///   the note they are editing; where their caret is waits for live typing too.
/// - **An AI online** (docs/CLAUDE_LIVE.md) is in [OrganizationScreen.seen] too, marked as one: never a member
///   present, even under a member's handle, it is shown on its own AI row as online, with what it is doing there
///   ("editing Roadmap"), Jump and Follow; an AI online that has no row yet is given one.
/// - The rows do not rise as they arrive (`animation: rise`), and the cards do not carry the AI corner mark; the
///   pull's ring and the smoke are All notes' own.
/// - The phone's back gesture is the shell's (lib/shell/app_shell.dart wraps the screen in `OnBack`).
/// - **Folders, and the icon view** (GHST-107, 2026-10-19) are the port's own: the folders inside the organization's
///   workspace stand above its Notes as chips (lib/notes/folder_strip.dart), a tap on one going to All notes with
///   that folder chosen ([OrganizationScreen.onAllNotes] with its id); and the Notes heading offers Cards or Icons
///   (lib/notes/icon_browser.dart), chosen for the organization's workspace and so for its folders wherever they are
///   browsed, until one of them chooses its own; the strip and the icon view offer New folder and New note
///   ([OrganizationScreen.onNewNote]) in the organization's workspace. Nothing of the folders is drawn until
///   the organization's workspace holds one.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../core/page_scroll.dart';
import '../../account/ui_state.dart';
import '../../art/art.dart';
import '../../core/note.dart';
import '../../core/note_facts.dart';
import '../../core/notifications.dart';
import '../../core/preferences.dart';
import '../../core/stored.dart' show stored;
import '../../core/workspaces.dart' show Workspace;
import '../../home/home_organizations.dart' show OrgPresence;
import '../../live/presence.dart' show aiDoingWords;
import '../../home/note_card.dart';
import '../../notes/folder_drag.dart';
import '../../notes/folder_strip.dart';
import '../../notes/icon_browser.dart';
import '../../notes/pull_to_refresh.dart';
import '../../notes/when.dart';
import '../../notes/workspace_swatch.dart';
import '../../settings/invite_actions.dart';
import '../../settings/invite_links.dart';
import '../../settings/kit/settings_kit.dart' show GoWord, SettingsWord;
import '../../sheet/css.dart';
import '../../shell/header_pane.dart';
import '../../shell/page_dock.dart';
import '../orgs.dart';
import 'org_news.dart';
import 'parts.dart';

/// How many of the workspace's notes the page shows before "All of them" (`NOTES_SHOWN`).
const int organizationNotesShown = 6;

/// How many of the organization's news rows the page shows; the audit log has them all (`ACTIVITY_SHOWN`).
const int organizationActivityShown = 8;

/// The organization's dashboard (`src/app/notes/OrganizationScreen.tsx`).
class OrganizationScreen extends StatefulWidget {
  const OrganizationScreen({
    super.key,
    required this.services,
    required this.orgId,
    required this.notes,
    required this.onBack,
    required this.onOpenNote,
    required this.onNew,
    required this.onAllNotes,
    required this.onSettings,
    required this.onOpenOrganization,
    required this.onLog,
    required this.onAccount,
    this.onJumpTo,
    this.onFollow,
    this.onChat,
    this.seen = const [],
    this.wisp = true,
    this.onSendLink,
    this.now,
    this.dock,
    this.onNewFolder,
    this.onNewNote,
  });

  final AccountServices? services;
  final String orgId;

  /// The notes this device holds (not the trash), of which those filed in the organization's workspace are shown.
  final List<Note> notes;

  /// Home.
  final VoidCallback onBack;
  final ValueChanged<String> onOpenNote;

  /// A new note, filed in the organization's workspace, opened ready to type.
  final VoidCallback onNew;

  /// Every note filed in the organization's workspace: the home page with that workspace chosen; or, from a
  /// folder's chip, with that folder chosen, by its id (GHST-107).
  final ValueChanged<String?> onAllNotes;

  /// New folder on the folders' strip (GHST-107): a folder inside the workspace given, by id, through the root's
  /// workspace sheet. Absent, the strip offers none.
  final ValueChanged<String?>? onNewFolder;

  /// New note on the folders' strip and in the icon view: a note filed in the workspace given (the organization's
  /// own here), opened ready to type, the team's as any note filed there. Absent, neither offers one.
  final ValueChanged<String>? onNewNote;

  /// The organization's settings (lib/settings/organization_sheet.dart), from the cog.
  final VoidCallback onSettings;

  /// Another organization's dashboard, from the row of pills.
  final ValueChanged<String> onOpenOrganization;

  /// The organization's audit log (organization_log.dart), from the clock in the bar and the Activity heading.
  final VoidCallback onLog;

  /// Settings at Account, from the signed-out words.
  final VoidCallback onAccount;

  /// A note opened where a member is editing it, from their profile; the row's own press when null.
  final ValueChanged<String>? onJumpTo;

  /// Follow an AI online here (lib/live/follow.dart), from its row; absent, and there is no Follow.
  final ValueChanged<OrgPresence>? onFollow;

  /// An AI's Chat: the chat with Claude opened for it (lib/claude/claude_chat.dart; Matt: "Make the ask Claude and
  /// other agents open a chat when we go to talk to them").
  final ValueChanged<OrgAi>? onChat;

  /// Who is in the organization's notes now, by device.
  final List<OrgPresence> seen;

  /// Whether the smoke is drawn under the bar (the `wispEdge` preference).
  final bool wisp;
  final void Function(String title, String url)? onSendLink;
  final int Function()? now;

  /// Claude and the halo for the page's dock (docs/DOCK.md); no dock where it is left out.
  final PageDockSeam? dock;

  @override
  State<OrganizationScreen> createState() => _OrganizationScreenState();
}

class _OrganizationScreenState extends State<OrganizationScreen> {
  final ScrollController _scroller = ScrollController();
  final FocusNode _inviteFocus = FocusNode(debugLabel: 'Invite by handle');
  final GlobalKey _inviteKey = GlobalKey(debugLabel: 'invite field');
  Org? _org;
  String? _problem;
  Object? _readFor;
  bool? _wasHeld;

  AccountServices? get _services => widget.services;
  PreferencesStore get _prefs => _services?.prefs ?? preferences;

  /// Cards or icons for the notes (lib/notes/icon_browser.dart): the organization's workspace is a level, and what is
  /// chosen here is what its folders open in, on home and All notes too, until one of them chooses its own.
  BrowseView get _view => browseViewAt(_services?.workspaces?.value.list ?? const <Workspace>[], orgWorkspaceId(widget.orgId), _services?.kept ?? stored);

  void _setView(BrowseView view) {
    chooseBrowseView(_services?.workspaces?.value.list ?? const <Workspace>[], orgWorkspaceId(widget.orgId), view, _services?.kept ?? stored);
    setState(() {});
  }

  bool get _signedIn => _services?.signedIn ?? false;
  bool get _held => !_signedIn || _prefs.value.localOnly;
  OrgRow? get _row => _signedIn ? _services?.orgs?.orgRow(widget.orgId) : null;
  List<FeedNotification> get _news => _services?.newsOf(widget.orgId) ?? const [];
  int _now() => (widget.now ?? _services?.now ?? () => DateTime.now().millisecondsSinceEpoch)();

  @override
  void initState() {
    super.initState();
    _services?.changes.addListener(_changed);
    _prefs.addListener(_changed);
    _services?.workspaces?.addListener(_changed);
    _look();
  }

  @override
  void didUpdateWidget(OrganizationScreen old) {
    super.didUpdateWidget(old);
    if (old.orgId != widget.orgId) {
      _org = null;
      _problem = null;
      _readFor = null;
      _wasHeld = null;
      _look();
    }
  }

  @override
  void dispose() {
    _services?.changes.removeListener(_changed);
    _prefs.removeListener(_changed);
    _services?.workspaces?.removeListener(_changed);
    _scroller.dispose();
    _inviteFocus.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _look();
  }

  /// What the page's two effects do: a whole pass as it opens (and when it stops being held), and the members read
  /// again whenever something about them may have changed - a new row of news, the count, the colour.
  void _look() {
    final held = _held;
    if (!held && _wasHeld != false) unawaited(_services!.syncNow());
    _wasHeld = held;
    final row = _row;
    if (held || row?.state != 'member') return;
    final news = _news;
    final key = (widget.orgId, news.isEmpty ? 0 : news.first.rev, row!.members, row.colour);
    if (key == _readFor) return;
    _readFor = key;
    unawaited(_read());
  }

  Future<void> _read() async {
    final orgs = _services?.orgs;
    if (orgs == null) return;
    final id = widget.orgId;
    try {
      final org = await orgs.fetchOrg(id);
      if (mounted && id == widget.orgId) {
        setState(() {
          _org = org;
          _problem = null;
        });
      }
    } catch (failure) {
      if (mounted && id == widget.orgId) setState(() => _problem = accountFailureText(failure));
    }
  }

  Future<void> _refresh() async {
    await _services?.syncNow();
    if (_row?.state == 'member') await _read();
  }

  void _toInvite() {
    final at = _inviteKey.currentContext;
    if (at != null) unawaited(Scrollable.ensureVisible(at, alignment: 0.5, duration: context.tokens.reducedMotion ? Duration.zero : const Duration(milliseconds: 300), curve: Curves.easeOut));
    _inviteFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final services = _services;
    final row = _row;
    final held = _held;
    final member = row?.state == 'member';
    final me = services?.session?.handle ?? '';
    final org = _org;
    final news = _news;
    final now = _now();

    // The notes filed in its workspace, or in any folder under it (GHST-107), newest change first.
    final workspaceId = orgWorkspaceId(widget.orgId);
    final spaces = services?.workspaces?.value;
    final filed = spaces?.of ?? const <String, String>{};
    final here = workspaceFamily(spaces?.list ?? const [], workspaceId).toSet();
    final filedHere = [for (final note in widget.notes) if (here.contains(filed[note.id]) && note.archivedAt == null) note]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final others = [for (final each in (_signedIn ? services!.orgState.list : const <OrgRow>[])) if (each.id != widget.orgId) each];
    final canInvite = member && (row!.role == 'owner' || row.role == 'admin');
    final joined = [for (final m in org?.members ?? const <Member>[]) if (m.state == 'member') m];
    final invited = [for (final m in org?.members ?? const <Member>[]) if (m.state == 'invited') m];
    final count = org != null ? joined.length : (row?.members ?? 0);

    // The bar: `padding-block: calc(var(--app-safe-top) + var(--glacier-space-2)) var(--glacier-space-2)` round the
    // tallest thing in it - a cog when there is one, else the arrow.
    final safeTop = t.len('app-safe-top');
    final cog = t.lenOf('calc(var(--glacier-space-10) * 0.88)');
    final hasCog = row != null && !held;
    final lg = t.fontSize('lg');
    final titleLine = normalLine(t, lg, weight: 'semibold');
    final bar = safeTop + t.space(2) * 2 + [t.space(8), if (hasCog) cog, titleLine].reduce(math.max);
    final under = bar.roundToDouble();
    final top = math.max(under, safeTop) + t.space(4);
    // The dock's rings, each one the page already has: New and Invite in the hero, the cog in the bar.
    final dockSeam = widget.dock;
    final dockRings = <DockAction>[
      if (member) DockAction(id: 'org-new', label: 'New note in this organization', icon: Lucide.plus, motion: DockMotion.turn, onPressed: widget.onNew),
      if (canInvite) DockAction(id: 'org-invite', label: 'Invite', tip: 'Invite someone', icon: Lucide.userPlus, onPressed: _toInvite),
    ];
    final dockFoot = hasCog ? DockAction(id: 'org-settings', label: 'Organization settings', icon: Lucide.settings, onPressed: widget.onSettings) : null;
    final rings = (dockSeam?.claude != null ? 1 : 0) + dockRings.length + (dockFoot != null ? 1 : 0);
    // And at least the room the dock stands in, so the activity's last rows scroll clear of it.
    final foot = t.len('app-safe-bottom') + (dockSeam == null ? t.space(10) : math.max(t.space(10), pageDockRoom(t, rings)));
    final sm = t.fontSize('sm');
    final md = t.fontSize('md');

    Widget heading(LucideIcon mark, String words, {int? count, Widget? more}) => Row(
          key: ValueKey('org-heading-${words.toLowerCase()}'),
          children: [
            ExcludeSemantics(child: AppIcon(mark, size: 15, color: t.color('app-ink-3'))),
            SizedBox(width: t.space(2)),
            Semantics(header: true, child: Text(words, style: pageText(t, sm, weight: 'semibold', color: t.color('app-ink-2')))),
            if (count != null) ...[
              SizedBox(width: t.space(2)),
              Text('$count', style: pageText(t, sm, color: t.color('app-ink-3')).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ],
            // What stands at the end takes the rest of the line, and gives way (Cards · Icons and "In its workspace"
            // together are a phone's width, GHST-107).
            if (more != null) Expanded(child: Padding(padding: EdgeInsetsDirectional.only(start: t.space(3)), child: Align(alignment: AlignmentDirectional.centerEnd, child: more))) else const Spacer(),
          ],
        );

    Widget more(String words, VoidCallback onPressed, {Key? key}) => DefaultTextStyle(
          style: pageText(t, sm),
          child: SettingsWord(key: key, onPressed: onPressed, color: t.color('app-ink-2'), child: Text(words, softWrap: false, overflow: TextOverflow.ellipsis)),
        );

    Widget none(String words) => Text(words, style: pageText(t, sm, height: t.len('glacier-leading-sm'), color: t.color('app-ink-3')));

    Widget section(List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(height: t.space(3)),
              children[i],
            ],
          ],
        );

    Widget body(bool wide) {
      if (held) {
        // `.held`: one sentence in the quiet ink, with its word in ink that goes to Account.
        return Padding(
          padding: EdgeInsets.only(top: t.space(4)),
          child: DefaultTextStyle(
            style: pageText(t, md, height: t.len('glacier-leading-md'), color: t.color('app-ink-2')),
            child: Text.rich(
              TextSpan(
                children: _signedIn
                    ? [
                        WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: GoWord('Local only', onPress: widget.onAccount)),
                        const TextSpan(text: ' is on, so nothing about the organization arrives until it is off.'),
                      ]
                    : [
                        const TextSpan(text: 'Organizations come with an account. Sign in under '),
                        WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: GoWord('Account', onPress: widget.onAccount)),
                        const TextSpan(text: '.'),
                      ],
              ),
            ),
          ),
        );
      }
      if (row == null) {
        final xl = t.fontSize('xl');
        return Padding(
          padding: EdgeInsets.symmetric(vertical: t.space(6)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Ghost(scene: GhostScene.emptyWorkspace, size: GhostSize.small, color: t.color('app-ink-3')),
              SizedBox(height: t.space(4)),
              Text('This organization is not in your list any more.', style: pageText(t, xl, weight: 'semibold', tracking: t.len('app-tracking-title', em: xl), color: t.color('glacier-text-subtle'))),
              SizedBox(height: t.space(2)),
              Text('You left it, it was deleted, or the invitation was withdrawn.', style: pageText(t, md, color: t.color('glacier-text-muted'))),
            ],
          ),
        );
      }
      if (!member) {
        return _Hero(
          row: row,
          wide: wide,
          meta: '${row.invitedBy != null && row.invitedBy!.isNotEmpty ? '${row.invitedBy} invited you' : 'You are invited'} · ${memberWords(row.members)}',
          note: 'Accept to join: its workspace is made on each of your devices, and the team’s news reaches you.',
          actions: [InviteActions(services: services!, orgId: row.id)],
        );
      }

      // The folders inside the organization's workspace (GHST-107), each with its count: chips above the cards, or
      // the first tiles of the icon view.
      final spaces = services?.workspaces?.value.list ?? const <Workspace>[];
      final folders = folderTiles(spaces, filed, widget.notes, workspaceId);
      // The workspaces, to carry the notes and the folders onto the folders (lib/notes/folder_drag.dart): within
      // the organization only, by the rules there.
      final store = services?.workspaces;
      NoteCarry? carry(Note note) {
        if (store == null) return null;
        final title = NoteFacts.of(note).title.trim();
        return (store: store, carry: FolderCarry.note(note.id, title.isEmpty ? 'Untitled' : title));
      }

      final all = filedHere.length > organizationNotesShown
          ? more('All ${filedHere.length}', () => widget.onAllNotes(null), key: const ValueKey('org-all-notes'))
          : (filedHere.isNotEmpty ? more('In its workspace', () => widget.onAllNotes(null), key: const ValueKey('org-all-notes')) : null);
      // Cards or icons while there is anything to view, then the way to all of them: a step apart, so "In its
      // workspace" keeps its place on a phone (test/account_ui/reference_test.dart holds it to the page's). With
      // nothing filed and no folder the heading is as it was, its words alone, level with Members on a wide page.
      final viewed = filedHere.isNotEmpty || folders.isNotEmpty;
      // With nothing to view there is no toggle, so the page is the cards and their New folder, whatever was chosen.
      final icons = viewed && _view == BrowseView.icons;
      final notes = section([
        heading(
          Lucide.filePlus,
          'Notes',
          count: filedHere.isEmpty ? null : filedHere.length,
          more: viewed
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: t.space(2),
                  children: [
                    BrowseViewToggle(key: const ValueKey('org-notes-view'), view: _view, onView: _setView),
                    if (all != null) Flexible(child: all),
                  ],
                )
              : null,
        ),
        if (!icons && (folders.isNotEmpty || widget.onNewFolder != null || widget.onNewNote != null))
          FolderStrip(key: const ValueKey('org-folders'), list: spaces, of: filed, notes: widget.notes, chosen: workspaceId, onChoose: widget.onAllNotes, onNewFolder: widget.onNewFolder, onNewNote: widget.onNewNote, store: store),
        if (icons && (filedHere.isNotEmpty || folders.isNotEmpty || widget.onNewFolder != null || widget.onNewNote != null))
          IconBrowser(
            key: const ValueKey('org-notes-icons'),
            folders: folders,
            onNewFolder: widget.onNewFolder == null ? null : () => widget.onNewFolder!(workspaceId),
            onNewNote: widget.onNewNote == null ? null : () => widget.onNewNote!(workspaceId),
            // The organization's own level, beside its folders' tiles (folder_strip.dart `notesAt`).
            notes: notesAt(filed, filedHere, workspaceId).take(organizationNotesShown).toList(growable: false),
            onFolder: widget.onAllNotes,
            onOpen: widget.onOpenNote,
            now: now,
            store: store,
          )
        else if (filedHere.isNotEmpty)
          Semantics(
            container: true,
            label: 'Notes in this organization',
            child: NoteCards(
              count: math.min(filedHere.length, organizationNotesShown),
              itemBuilder: (context, i, fill) => NoteCard(key: ValueKey('card-${filedHere[i].id}'), note: filedHere[i], index: i, onOpen: widget.onOpenNote, dense: true, fill: fill, now: now, carry: carry(filedHere[i]), folder: folderUnder(spaces, filed, filedHere[i].id, workspaceId)?.name),
            ),
          )
        else if (folders.isEmpty)
          none('Nothing is filed here yet. Start one with New, or file a note here from its More, under Workspace.'),
      ]);

      final members = section([
        heading(Lucide.users, 'Members', count: count),
        Semantics(
          container: true,
          label: 'Members',
          explicitChildNodes: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (org != null)
                for (final m in [...joined, ...invited]) _MemberLine(key: ValueKey('member:${m.handle}'), member: m, me: me, seen: widget.seen, now: now, onJump: widget.onJumpTo ?? widget.onOpenNote)
              else
                Text('Reading the members…', style: pageText(t, sm, color: t.color('app-ink-3'))),
              // The AIs seen here through a member's connector, after the people and never counted with them; each
              // online with what it is doing, and one online with no row yet given one.
              for (final (ai, here) in aiLines(org?.ais ?? const <OrgAi>[], widget.seen, now: now))
                _AiLine(key: ValueKey('ai:${ai.id}'), ai: ai, me: me, now: now, here: here, onJump: widget.onJumpTo ?? widget.onOpenNote, onFollow: widget.onFollow, onChat: widget.onChat),
            ],
          ),
        ),
        // Your colour in this organization (docs/SHARED.md, S7), under the members, where it is worn.
        _YourColour(services: services!, row: row),
        if (canInvite)
          _Invite(
            fieldKey: _inviteKey,
            focusNode: _inviteFocus,
            onInvite: (handle) async {
              await services.orgs!.inviteByHandle(widget.orgId, handle);
              // The key wrapped for them now (docs/SHARED.md, S2), so the team's notes are theirs the moment they accept.
              unawaited(services.syncNotificationsNow());
              await _read();
            },
          ),
        if (canInvite)
          InviteLinks(
            services: services,
            orgId: widget.orgId,
            onSend: widget.onSendLink,
            now: widget.now,
            around: (panel) => Padding(
              // `.byLink { margin-block-start: var(--glacier-space-4) }`, over the section's own gap.
              padding: EdgeInsets.only(top: t.space(4)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Invite by link', style: pageText(t, sm, weight: 'semibold', color: t.color('app-ink-2'))),
                  SizedBox(height: t.space(1)),
                  panel,
                ],
              ),
            ),
          ),
      ]);

      final activity = section([
        heading(Lucide.activity, 'Activity', more: more('Audit log', widget.onLog, key: const ValueKey('org-audit-log'))),
        if (news.isNotEmpty)
          Semantics(
            container: true,
            label: 'Activity',
            explicitChildNodes: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [for (final n in news.take(organizationActivityShown)) _NewsLine(key: ValueKey('news:${n.id}'), n: n, now: now)],
            ),
          )
        else
          none('Nothing has happened here yet. Who joins, leaves or changes role shows here.'),
      ]);

      final problem = _problem;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Hero(
            row: row,
            wide: wide,
            meta: '${memberWords(count)} · You are ${roleWords(row.role).toLowerCase()}',
            note: teamsNotes,
            actions: [
              // The +, as on the home page: a note, a canvas or a notebook, made filed in this organization's workspace.
              OrgAction(key: const ValueKey('org-new'), label: 'New', semanticLabel: 'New in this organization', icon: const AppIcon(Lucide.plus, size: 16, strokeWidth: 2.4), onPressed: widget.onNew),
              if (canInvite) OrgAction(key: const ValueKey('org-invite'), label: 'Invite', icon: const AppIcon(Lucide.userPlus, size: 16, strokeWidth: 2.1), onPressed: _toInvite),
            ],
          ),
          if (problem != null)
            Padding(
              padding: EdgeInsets.only(top: t.space(3)),
              child: Semantics(liveRegion: true, child: Text(problem, style: pageText(t, sm, color: t.color('app-ink-2')))),
            ),
          SizedBox(height: t.space(8)),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [notes, SizedBox(height: t.space(8)), activity])),
                SizedBox(width: t.space(10)),
                Expanded(child: members),
              ],
            )
          else ...[
            notes,
            SizedBox(height: t.space(8)),
            members,
            SizedBox(height: t.space(8)),
            activity,
          ],
        ],
      );
    }

    Widget page(PullDown? pull) {
      final column = LayoutBuilder(
        builder: (context, box) {
          // `@container org-page (min-width: 44rem)`
          final wide = box.maxWidth >= t.lenOf('44rem');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (others.isNotEmpty) _Switcher(current: row, others: others, onOpen: widget.onOpenOrganization),
              body(wide),
            ],
          );
        },
      );
      final Widget scroller = ScrollConfiguration(
        behavior: const _Still(),
        child: SingleChildScrollView(
          key: const ValueKey('organization-scroll'),
          controller: _scroller,
          physics: pull?.physics,
          padding: EdgeInsetsDirectional.fromSTEB(t.len('app-gutter-start'), top, t.len('app-gutter-end'), foot),
          child: pull == null ? column : PullLowered(pull: pull, child: column),
        ),
      );
      return widget.wisp ? WispEdge(under: under, child: scroller) : scroller;
    }

    Widget ring(LucideIcon mark, String label, VoidCallback onPressed, Key key) => GlacierPressable(
          key: key,
          onPressed: onPressed,
          semanticLabel: label,
          builder: (context, state) => GlacierFocusRing(
            visible: state.focused,
            radius: t.radius('full'),
            child: Container(
              width: cog,
              height: cog,
              decoration: ShapeDecoration(
                color: t.colorOf('color-mix(in oklch, var(--app-ink) ${state.hovered ? 8 : 4}%, transparent)'),
                shape: CircleBorder(side: BorderSide(color: t.color('glacier-border-subtle'), width: snapBorder(context, t.len('glacier-hairline')))),
              ),
              alignment: Alignment.center,
              child: AnimatedScale(scale: state.pressed ? 0.92 : 1, duration: const Duration(milliseconds: 80), child: AppIcon(mark, size: 19, strokeWidth: 2.1, color: t.color('app-ink'))),
            ),
          ),
        );

    return GlacierScope(
      attrs: {'hue': row?.hue ?? 'ink'},
      child: ColoredBox(
        color: t.color('glacier-bg'),
        child: ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: () {
                  final Widget body = held ? page(null) : PullToRefresh(controller: _scroller, onRefresh: _refresh, top: top, builder: (context, pull) => page(pull));
                  return dockSeam == null ? body : PageDockFrame(seam: dockSeam, actions: dockRings, foot: dockFoot, child: body);
                }(),
              ),
              HeaderPane(
                child: Padding(
                  key: const ValueKey('organization-bar'),
                  padding: EdgeInsetsDirectional.fromSTEB(t.len('app-gutter-start') - t.space(2), t.space(2), t.len('app-gutter-end'), t.space(2)),
                  child: Row(
                    spacing: t.space(2),
                    children: [
                      GlacierPressable(
                        key: const ValueKey('organization-back'),
                        onPressed: widget.onBack,
                        semanticLabel: 'Back to home',
                        builder: (context, state) => GlacierFocusRing(
                          visible: state.focused,
                          child: SizedBox.square(dimension: t.space(8), child: Center(child: AppIcon(Lucide.arrowLeft, size: 20, color: t.color('app-ink')))),
                        ),
                      ),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Row(
                            children: [
                              ExcludeSemantics(child: HueRound(hue: row?.hue, size: 0.6 * lg)),
                              SizedBox(width: t.space(2)),
                              Flexible(
                                child: Text(
                                  row?.name ?? 'Organization',
                                  key: const ValueKey('organization-title'),
                                  style: pageText(t, lg, weight: 'semibold', tracking: t.len('app-tracking-title', em: lg), color: t.color('app-ink')),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // The audit log, behind a clock before the cog: every change to the notes filed here, and the team's news.
                      if (row != null && !held && member) ring(Lucide.history, 'Audit log', widget.onLog, const ValueKey('organization-log')),
                      // The organization's settings, behind a cog at the bar's end.
                      if (hasCog) ring(Lucide.settings, 'Organization settings', widget.onSettings, const ValueKey('organization-cog')),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The platform's overscroll glow and stretch left off, and no scrollbar of its own.
class _Still extends GhostScrollBehavior {
  const _Still();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

/// The other organizations, as pills to move between them, each in its colour; an invitation waiting says so
/// (`Switcher`).
class _Switcher extends StatelessWidget {
  const _Switcher({required this.current, required this.others, required this.onOpen});
  final OrgRow? current;
  final List<OrgRow> others;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final current = this.current;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(4)),
      child: Semantics(
        container: true,
        label: 'Your organizations',
        explicitChildNodes: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: t.space(2),
            children: [
              if (current != null) OrgPill(key: const ValueKey('org-pill-current'), label: current.name, hue: current.hue, pressed: true),
              for (final org in others)
                OrgPill(key: ValueKey('org-pill:${org.id}'), label: org.name, hue: org.hue, note: org.state == 'invited' ? 'invited' : null, onPressed: () => onOpen(org.id)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pill (`.pill`): the switcher's organizations, and the audit log's kinds. [pressed] is the one on screen or the
/// kind chosen; [dashed] the log's "only this note".
class OrgPill extends StatelessWidget {
  const OrgPill({super.key, required this.label, this.hue, this.showHue = true, this.note, this.pressed = false, this.dashed = false, this.onPressed, this.leading, this.trailing, this.semanticLabel});

  final String label;
  final String? hue;
  final bool showHue;
  final String? note;
  final bool pressed;
  final bool dashed;
  final VoidCallback? onPressed;
  final Widget? leading;
  final Widget? trailing;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final line = snapBorder(context, t.len('glacier-hairline'));
    final ink = pressed || dashed ? t.color('app-ink') : t.color('app-ink-2');
    final rule = pressed ? t.color('app-ink-2') : t.color('glacier-border-subtle');
    final Widget pill = CustomPaint(
      painter: _PillOutline(color: rule, width: line, dashed: dashed, fill: pressed ? t.colorOf('color-mix(in oklch, var(--app-ink) 6%, transparent)') : null),
      child: Padding(
        // `padding: 0.35em 0.85em`, inside the hairline.
        padding: EdgeInsets.symmetric(vertical: 0.35 * sm + line, horizontal: 0.85 * sm + line),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 0.45 * sm,
          children: [
            if (leading != null) IconTheme.merge(data: IconThemeData(color: ink), child: leading!),
            if (showHue) HueRound(hue: hue, size: 0.55 * sm),
            Text(label, style: pageText(t, sm, color: ink), softWrap: false),
            if (note != null) Text(note!, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3')), softWrap: false),
            if (trailing != null) IconTheme.merge(data: IconThemeData(color: ink), child: trailing!),
          ],
        ),
      ),
    );
    if (onPressed == null) return Semantics(label: semanticLabel ?? label, selected: pressed, child: ExcludeSemantics(child: pill));
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: semanticLabel ?? label,
      toggled: showHue ? null : pressed,
      builder: (context, state) => GlacierFocusRing(visible: state.focused, radius: t.radius('full'), child: ExcludeSemantics(child: pill)),
    );
  }
}

class _PillOutline extends CustomPainter {
  const _PillOutline({required this.color, required this.width, required this.dashed, this.fill});
  final Color color;
  final double width;
  final bool dashed;
  final Color? fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
    final fill = this.fill;
    if (fill != null) canvas.drawRRect(shape, Paint()..color = fill);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    if (!dashed) return canvas.drawRRect(shape, paint);
    final dash = width * 3;
    for (final metric in (Path()..addRRect(shape)).computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += dash * 2) {
        canvas.drawPath(metric.extractPath(at, math.min(at + dash, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_PillOutline old) => old.color != color || old.width != width || old.dashed != dashed || old.fill != fill;
}

/// The organization at the top of its page (`Hero`, and `Invitation`, which is the same card with other words): its
/// colour, its name, a line of what it is to you, a sentence, and what there is to do - under the words on a phone,
/// at the card's end on a wide page.
class _Hero extends StatelessWidget {
  const _Hero({required this.row, required this.wide, required this.meta, required this.note, required this.actions});
  final OrgRow row;
  final bool wide;
  final String meta;
  final String note;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final xxl = t.fontSize('2xl');
    final line = snapBorder(context, t.len('glacier-hairline'));
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(row.name, key: const ValueKey('org-hero-name'), style: pageText(t, xxl, weight: 'semibold', height: 1.15, tracking: t.len('app-tracking-title', em: xxl), color: t.color('app-ink'))),
        SizedBox(height: t.space(1)),
        Text(meta, key: const ValueKey('org-hero-meta'), style: pageText(t, sm, color: t.color('app-ink-2'))),
        SizedBox(height: t.space(2)),
        Text(note, style: pageText(t, sm, height: t.len('glacier-leading-sm'), color: t.color('app-ink-3'))),
      ],
    );
    final round = HueRound(key: const ValueKey('org-hero-hue'), hue: row.hue, size: t.lenOf('3.25rem'));
    final things = Wrap(spacing: t.space(2), runSpacing: t.space(2), alignment: wide ? WrapAlignment.end : WrapAlignment.start, children: actions);
    return Semantics(
      container: true,
      label: row.name,
      child: Container(
        key: const ValueKey('org-hero'),
        padding: EdgeInsets.all(t.space(5)),
        decoration: BoxDecoration(
          color: t.colorOf('color-mix(in oklch, var(--app-ink) 3%, transparent)'),
          borderRadius: BorderRadius.circular(t.radius('lg')),
          border: Border.all(color: t.color('glacier-border-subtle'), width: line),
        ),
        child: wide
            ? Row(children: [round, SizedBox(width: t.space(4)), Expanded(child: words), SizedBox(width: t.space(4)), things])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [round, SizedBox(width: t.space(4)), Expanded(child: words)]),
                  SizedBox(height: t.space(3)),
                  things,
                ],
              ),
      ),
    );
  }
}

/// One member (`MemberLine`): an initial in a round, the handle, the role, and since when; invited ones dashed. A
/// member in the app now has a dot on their initial and the line says "here now" or "editing Roadmap", and the row
/// opens their profile: since when, where they are, and the way to the note they are editing.
class _MemberLine extends StatefulWidget {
  const _MemberLine({super.key, required this.member, required this.me, required this.seen, required this.onJump, this.now});
  final Member member;
  final String me;
  final List<OrgPresence> seen;
  final ValueChanged<String> onJump;
  final int? now;

  @override
  State<_MemberLine> createState() => _MemberLineState();
}

class _MemberLineState extends State<_MemberLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final member = widget.member;
    final sm = t.fontSize('sm');
    final md = t.fontSize('md');
    final self = member.handle.toLowerCase() == widget.me.toLowerCase();
    final joined = member.state == 'member';
    // An AI is never a member present, even one whose name is a member's handle.
    final devices = [for (final s in widget.seen) if (!s.ai && s.handle.toLowerCase() == member.handle.toLowerCase()) s];
    OrgPresence? at;
    for (final device in devices) {
      if (device.editingNote != null) {
        at = device;
        break;
      }
    }
    // You are in the app: this device is reading the page. The others are here when the room says so.
    final present = self || devices.isNotEmpty;
    final line = memberLine(member, self: self, now: widget.now);
    final title = at == null ? null : (at.editingTitle != null && at.editingTitle!.isNotEmpty ? at.editingTitle! : (at.editingCanvas ? 'an untitled canvas' : 'an untitled note'));
    final where = at != null ? 'editing $title' : (present && !self ? 'here now' : null);
    final hair = snapBorder(context, t.len('glacier-hairline'));
    final side = t.lenOf('2.25rem');

    return GlacierScope(
      attrs: {if (member.colour != null) 'hue': member.colour!},
      child: Builder(
        builder: (context) {
          final here = context.tokens;
          final hued = member.colour != null;
          final space = here.colorOf('var(--app-space, var(--app-ink))');
          final avatarInk = !joined ? here.color('app-ink-3') : (hued ? space : here.color('app-ink'));
          final avatar = Stack(
            clipBehavior: Clip.none,
            children: [
              CustomPaint(
                painter: joined ? null : _PillOutline(color: here.color('app-ink-3'), width: hair, dashed: true),
                child: Container(
                  key: const ValueKey('member-avatar'),
                  width: side,
                  height: side,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: !joined ? null : (hued ? here.colorOf('color-mix(in oklch, var(--app-space) 22%, transparent)') : here.colorOf('color-mix(in oklch, var(--app-ink) 8%, transparent)')),
                  ),
                  child: Text(member.handle.isEmpty ? '' : member.handle.substring(0, 1).toUpperCase(), style: pageText(here, sm, weight: 'semibold', color: avatarInk)),
                ),
              ),
              if (present)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    key: const ValueKey('member-here'),
                    width: here.lenOf('0.62rem'),
                    height: here.lenOf('0.62rem'),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: space, boxShadow: [BoxShadow(color: here.color('app-paper'), spreadRadius: 2)]),
                  ),
                ),
            ],
          );
          final since = Text(
            where ?? line,
            key: const ValueKey('member-since'),
            style: pageText(here, sm, weight: at != null ? 'medium' : 'regular', color: at != null ? space : (where != null ? here.color('app-ink-2') : here.color('app-ink-3'))),
          );
          final row = GlacierPressable(
            onPressed: () => setState(() => _open = !_open),
            toggled: _open,
            haptic: HapticKind.selection,
            builder: (context, state) => GlacierFocusRing(
              visible: state.focused,
              radius: here.radius('sm'),
              offset: 3,
              color: here.color('app-ink'),
              child: Row(
                children: [
                  ExcludeSemantics(child: avatar),
                  SizedBox(width: here.space(3)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // `.handle`: the handle and, in its line, the chip (`inline-block; vertical-align: 0.1em`). The
                        // chip is taller than the words, so the line is the chip and what it stands off the line's top:
                        // 1.75px, as the page measured it at both of the interface's sizes.
                        SizedBox(
                          height: 1.6 * here.fontSize('xs') + 2 * hair + 1.75,
                          child: Row(
                            children: [
                              Flexible(child: Text(member.handle, style: pageText(here, md, weight: 'medium', color: here.color('app-ink')), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              SizedBox(width: here.space(2)),
                              Align(alignment: Alignment.topCenter, child: Padding(padding: const EdgeInsets.only(top: 1.75), child: RoleChip(member: member))),
                            ],
                          ),
                        ),
                        // `gap: 0.15em` of the page's own text, which is 16px whatever the interface's size.
                        const SizedBox(height: 0.15 * 16),
                        since,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
          return Container(
            padding: EdgeInsets.symmetric(vertical: here.space(3)),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: here.color('app-rule'), width: hair))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                row,
                if (_open)
                  Semantics(
                    container: true,
                    label: '${member.handle}’s profile',
                    child: Padding(
                      key: const ValueKey('member-profile'),
                      padding: EdgeInsetsDirectional.fromSTEB(side + here.space(3), here.space(2), 0, here.space(1)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(line, style: pageText(here, sm, color: here.color('app-ink-2'))),
                          SizedBox(height: here.space(2)),
                          Text(
                            at != null ? 'Editing $title now' : (self ? 'In the app now, on this device' : (present ? 'In the app now' : 'Not in the app now')),
                            style: pageText(here, sm, color: here.color('app-ink-2')),
                          ),
                          if (at != null) ...[
                            SizedBox(height: here.space(2) + here.space(1)),
                            GlacierPressable(
                              key: const ValueKey('member-jump'),
                              onPressed: () => widget.onJump(at!.editingNote!),
                              builder: (context, state) => GlacierFocusRing(
                                visible: state.focused,
                                radius: here.radius('full'),
                                offset: 3,
                                color: here.color('app-ink'),
                                child: Container(
                                  padding: EdgeInsets.symmetric(vertical: 0.35 * sm, horizontal: 0.9 * sm),
                                  decoration: ShapeDecoration(
                                    color: state.hovered ? here.colorOf('color-mix(in oklch, var(--app-space, var(--app-ink)) 10%, transparent)') : null,
                                    shape: StadiumBorder(side: BorderSide(color: space, width: hair)),
                                  ),
                                  // `at.cursor ?? at.pointer ? 'Jump to cursor' : at.kind === 'canvas' ? 'Open the canvas' : 'Open the note'`
                                  child: Text(at!.editingPlace ? 'Jump to cursor' : (at.editingCanvas ? 'Open the canvas' : 'Open the note'), style: pageText(here, sm, weight: 'medium', color: space)),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// An AI seen in the organization through a member's connector (lib/orgs/types.dart `OrgAi`; `AiLine`): a line as a
/// member's is - an initial, the name with an AI chip, and whose connector it came through and when it was last
/// seen. Removing one is in the organization's settings.
///
/// Online ([here], docs/CLAUDE_LIVE.md), a dot on its initial and the line says what it is doing ("editing
/// Roadmap", "reading Roadmap", "online"), with Jump to the note it is on, at its caret, and Follow.
///
/// `.aiRow` is `.memberRow`'s measures without the button. The initial stands in an outline, not a fill
/// (`.member[data-state='ai'] .avatar`): listed with the people, and not one of them.
class _AiLine extends StatelessWidget {
  const _AiLine({super.key, required this.ai, required this.me, this.now, this.here, this.onJump, this.onFollow, this.onChat});
  final OrgAi ai;
  final String me;
  final int? now;

  /// Its entry online, or null while it is not.
  final OrgPresence? here;
  final ValueChanged<String>? onJump;
  final ValueChanged<OrgPresence>? onFollow;
  final ValueChanged<OrgAi>? onChat;

  @override
  Widget build(BuildContext context) {
    final here = this.here;
    return GlacierScope(
      attrs: {if (here?.hue != null) 'hue': here!.hue!},
      child: Builder(builder: (context) => _build(context, here)),
    );
  }

  Widget _build(BuildContext context, OrgPresence? here) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final md = t.fontSize('md');
    final hair = snapBorder(context, t.len('glacier-hairline'));
    final side = t.lenOf('2.25rem');
    final space = t.colorOf('var(--app-space, var(--app-ink))');
    final online = here != null;
    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        CustomPaint(
          painter: _PillOutline(color: online ? space : t.color('app-ink-3'), width: hair, dashed: false),
          child: Container(
            key: const ValueKey('ai-avatar'),
            width: side,
            height: side,
            alignment: Alignment.center,
            child: Text(ai.name.isEmpty ? '' : ai.name.substring(0, 1).toUpperCase(), style: pageText(t, sm, weight: 'semibold', color: online ? space : t.color('app-ink-2'))),
          ),
        ),
        if (online)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              key: const ValueKey('ai-here'),
              width: t.lenOf('0.62rem'),
              height: t.lenOf('0.62rem'),
              decoration: BoxDecoration(shape: BoxShape.circle, color: space, boxShadow: [BoxShadow(color: t.color('app-paper'), spreadRadius: 2)]),
            ),
          ),
      ],
    );
    final note = here?.editingNote;
    final doing = here == null ? null : aiDoingWords(note == null ? null : (here.doing ?? 'editing'), here.editingTitle);
    Widget pill(String key, String words, VoidCallback onPressed) => GlacierPressable(
          key: ValueKey(key),
          onPressed: onPressed,
          builder: (context, state) => GlacierFocusRing(
            visible: state.focused,
            radius: t.radius('full'),
            offset: 3,
            color: t.color('app-ink'),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 0.35 * sm, horizontal: 0.9 * sm),
              decoration: ShapeDecoration(
                color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-space, var(--app-ink)) 10%, transparent)') : null,
                shape: StadiumBorder(side: BorderSide(color: space, width: hair)),
              ),
              child: Text(words, style: pageText(t, sm, weight: 'medium', color: space)),
            ),
          ),
        );
    final follow = onFollow;
    final jump = onJump;
    final chat = onChat;
    return Container(
      padding: EdgeInsets.symmetric(vertical: t.space(3)),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.color('app-rule'), width: hair))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // One thing to a reader, as a member's row is one button: the name, that it is an AI, and its line.
          MergeSemantics(
            child: Row(
              children: [
                ExcludeSemantics(child: avatar),
                SizedBox(width: t.space(3)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // `.handle` with its chip, measured as a member's is (see `_MemberLine`).
                      SizedBox(
                        height: 1.6 * t.fontSize('xs') + 2 * hair + 1.75,
                        child: Row(
                          children: [
                            Flexible(child: Text(ai.name, style: pageText(t, md, weight: 'medium', color: t.color('app-ink')), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            SizedBox(width: t.space(2)),
                            const Align(alignment: Alignment.topCenter, child: Padding(padding: EdgeInsets.only(top: 1.75), child: RoleChip.ai())),
                          ],
                        ),
                      ),
                      const SizedBox(height: 0.15 * 16),
                      Text(
                        doing ?? aiLine(ai, me: me, now: now),
                        key: const ValueKey('ai-since'),
                        style: pageText(t, sm, weight: note != null ? 'medium' : 'regular', color: note != null ? space : (online ? t.color('app-ink-2') : t.color('app-ink-3'))),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if ((here != null && ((note != null && jump != null) || follow != null)) || chat != null) ...[
            SizedBox(height: t.space(2)),
            Padding(
              padding: EdgeInsetsDirectional.only(start: side + t.space(3)),
              child: Wrap(
                spacing: t.space(2),
                runSpacing: t.space(2),
                children: [
                  // `at.cursor ? 'Jump to cursor' : 'Open the note'`, as a member's profile says it.
                  if (chat != null) pill('ai-chat', 'Chat', () => chat(ai)),
                  if (here != null && note != null && jump != null) pill('ai-jump', here.editingPlace ? 'Jump to cursor' : (here.editingCanvas ? 'Open the canvas' : 'Open the note'), () => jump(note)),
                  if (here != null && follow != null) pill('ai-follow', 'Follow', () => follow(here)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One piece of the organization's news, as the notifications drawer words it (`NewsLine`): the kind's mark in its
/// colour, the sentence, and when; the unread ones in ink and the rest in the quiet ink.
class _NewsLine extends StatelessWidget {
  const _NewsLine({super.key, required this.n, this.now});
  final FeedNotification n;
  final int? now;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final ink = n.readAt == null ? t.color('app-ink') : t.color('app-ink-2');
    return Container(
      padding: EdgeInsets.symmetric(vertical: t.space(3)),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.color('app-rule'), width: snapBorder(context, t.len('glacier-hairline'))))),
      child: Row(
        children: [
          ExcludeSemantics(child: OrgNewsMark(kind: n.kind, fallback: t.color('app-ink-3'))),
          SizedBox(width: t.space(3)),
          Expanded(child: Text(sentenceOf(n), style: pageText(t, sm, color: ink))),
          SizedBox(width: t.space(3)),
          Text(when(n.at, now), style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3')), softWrap: false),
        ],
      ),
    );
  }
}

/// Your colour here (docs/SHARED.md, S7; the dashboard's `YourColour`): the account's own unless one is picked
/// here, worn in this organization alone.
class _YourColour extends StatefulWidget {
  const _YourColour({required this.services, required this.row});
  final AccountServices services;
  final OrgRow row;

  @override
  State<_YourColour> createState() => _YourColourState();
}

class _YourColourState extends State<_YourColour> {
  String? _problem;

  Future<void> _choose(String? hue) async {
    final orgs = widget.services.orgs;
    if (orgs == null) return;
    setState(() => _problem = null);
    try {
      await orgs.setOrgColour(widget.row.id, hue);
    } catch (failure) {
      if (mounted) setState(() => _problem = accountFailureText(failure));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final row = widget.row;
    final overridden = row.colour != widget.services.orgState.colour;
    final problem = _problem;
    // The swatch as wide as its seven dots, their gaps and its own padding, or the page where that is narrower.
    final swatch = 7 * t.lenOf('2rem') + 6 * t.space(2) + 2 * t.space(4);
    return Padding(
      // `.yourColour { margin-block-start: var(--glacier-space-4) }`, over the section's own gap.
      padding: EdgeInsets.only(top: t.space(4)),
      child: LayoutBuilder(
        builder: (context, box) => Wrap(
          key: const ValueKey('org-your-colour'),
          spacing: t.space(4),
          runSpacing: t.space(2),
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Your colour', style: pageText(t, sm, weight: 'semibold', color: t.color('app-ink-2'))),
                SizedBox(height: t.space(1) + 0.1 * 16),
                Text(overridden ? 'In this organization alone.' : 'Your account’s, from Settings.', style: pageText(t, sm, color: t.color('app-ink-3'))),
              ],
            ),
            SizedBox(width: math.min(swatch, box.maxWidth), child: WorkspaceSwatch(hue: row.colour ?? 'ink', onHue: (hue) => unawaited(_choose(hue == 'ink' ? null : hue)))),
            if (overridden)
              DefaultTextStyle(
                style: pageText(t, sm),
                child: SettingsWord(onPressed: () => unawaited(_choose(null)), color: t.color('app-ink-2'), child: const Text('Use your account’s colour', softWrap: false)),
              ),
            if (problem != null) Semantics(liveRegion: true, child: Text(problem, style: pageText(t, sm, color: t.color('app-ink-2')))),
          ],
        ),
      ),
    );
  }
}

/// The invite field, for an owner or an admin (the dashboard's `Invite`): a handle in, the service's answer under
/// it in its own words.
class _Invite extends StatefulWidget {
  const _Invite({required this.fieldKey, required this.focusNode, required this.onInvite});
  final Key fieldKey;
  final FocusNode focusNode;
  final Future<void> Function(String handle) onInvite;

  @override
  State<_Invite> createState() => _InviteState();
}

class _InviteState extends State<_Invite> {
  String _handle = '';
  bool _busy = false;
  String? _problem;
  String? _said;

  Future<void> _submit() async {
    final clean = _handle.trim();
    if (clean.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _problem = null;
      _said = null;
    });
    try {
      await widget.onInvite(clean);
      if (mounted) {
        setState(() {
          _said = '$clean is invited. They see it in their notifications.';
          _handle = '';
        });
      }
    } catch (failure) {
      if (mounted) setState(() => _problem = accountFailureText(failure));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final words = _problem ?? _said;
    return Padding(
      // `.invite { margin-block-start: var(--glacier-space-1) }`
      padding: EdgeInsets.only(top: t.space(1)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: GlacierInput(
                  key: widget.fieldKey,
                  focusNode: widget.focusNode,
                  ariaLabel: 'Invite by handle',
                  placeholder: 'Invite by handle',
                  autoCapitalize: TextCapitalization.none,
                  autoCorrect: false,
                  spellCheck: false,
                  value: _handle,
                  onChange: (text) => setState(() => _handle = text),
                  onSubmitted: (_) => unawaited(_submit()),
                ),
              ),
              SizedBox(width: t.space(2)),
              OrgAction(key: const ValueKey('org-invite-submit'), label: _busy ? 'One moment…' : 'Invite', onPressed: _busy || _handle.trim().isEmpty ? null : () => unawaited(_submit())),
            ],
          ),
          if (words != null) ...[
            SizedBox(height: t.space(2)),
            Semantics(liveRegion: true, child: Text(words, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2')))),
          ],
        ],
      ),
    );
  }
}
