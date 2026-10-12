import 'dart:async';

import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../account/ui_state.dart';
import '../art/art.dart';
import '../core/preferences.dart';
import '../core/workspaces.dart';
import '../notes/workspace_swatch.dart';
import '../orgs/orgs.dart';
import '../orgs/ui/parts.dart';
import 'account_forms.dart';
import 'invite_actions.dart';
import 'invite_links.dart';
import 'kit/settings_kit.dart';
import 'panes/pane_parts.dart';
import 'settings_screen.dart';

/// How long a leave, a delete or a hand-over stays armed after its first tap, as a reset does (`ARMED_MS`).
const Duration organizationArmedFor = armedFor;

/// Where a report goes: the address on the privacy page and on both stores' listings (`REPORT_TO`).
const String reportTo = 'infamousvaguerat@gmail.com';

/// The email a report opens (`reportMail`), addressed and titled so it can be acted on: the organization's name and
/// its id, and who is reporting. The body is left to the person, with one line asking for what the service cannot
/// see for itself.
String reportMail({required String orgId, required String name, String? handle}) {
  final subject = 'Ghost.md report: $name ($orgId)';
  final body =
      'Reported by: ${handle ?? 'not signed in'}\nOrganization: $name ($orgId)\n\nWho or what is this about, and what happened? Paste the words or attach a screenshot: team notes are sealed, so we cannot read them ourselves.\n\n';
  return 'mailto:$reportTo?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}';
}

/// Where the organization's screen was opened from (`from`).
enum OrganizationFrom { settings, dashboard }

/// Port of `OrganizationSheet` (src/app/settings/OrganizationSheet.tsx; docs/TEAMS.md, D6): an organization's own
/// screen, which is the Settings surface itself ([SettingsScreen]) with the organization's name where "Settings"
/// stood, no search over its six sections, and opened landed on Members, so the first thing seen is the team.
///
/// The sections: General (the name and the colour, which owners and admins change; the workspace follows), Members
/// (the hero, the list with each one's role, your colour here, invite by handle or by link, remove, and for the
/// owner a role to set or the organization to hand over), Workspace (the organization's workspace on this device,
/// and the way to the notes filed in it), Notifications (mute this organization's team news), Report (an email to
/// the app's maker) and, last and on its own, Leave or Delete, each tapped twice. The service's refusals are shown
/// in its own words under the row that asked.
///
/// Opened from Settings › Organizations ([OrganizationFrom.settings]) its head reads "← Organizations"; from the
/// dashboard's cog ([OrganizationFrom.dashboard]) it reads the organization's name.
///
/// What differs from the web original:
/// - The account, the organizations and the workspaces are the [AccountServices] it is handed.
/// - The report's email is opened by [onOpenLink] (`openLink`); without it the row cannot be pressed.
/// - **The key is not turned from here on the web either**: an organization's key is made, filled for new members
///   and turned by the sync pass (lib/orgs/org_keys.dart), which an invitation sent from this screen asks for with
///   a pass of the notifications. There is no row for it.
/// - Report's section asks for a hue named `amber`, which neither stylesheet defines: its glyph is the ink on both.
class OrganizationSheet extends StatefulWidget {
  const OrganizationSheet({
    super.key,
    required this.services,
    required this.orgId,
    this.from,
    required this.onClose,
    required this.onNotes,
    this.landOnMembers = true,
    this.onOpenLink,
    this.onSendLink,
    this.split,
    this.now,
  });

  final AccountServices services;
  final String orgId;
  final OrganizationFrom? from;
  final VoidCallback onClose;

  /// The notes filed in the organization's workspace: the home page with that workspace chosen.
  final VoidCallback onNotes;

  /// Land on Members as it opens (the default), or on the list of sections: from the dashboard, whose page already
  /// shows the team, the cog opens the settings themselves.
  final bool landOnMembers;
  final void Function(String url)? onOpenLink;

  /// Hands an invite link to the platform's share sheet ([InviteLinks.onSend]).
  final void Function(String title, String url)? onSendLink;

  /// Whether to draw the split view; null asks the window.
  final bool? split;
  final int Function()? now;

  @override
  State<OrganizationSheet> createState() => _OrganizationSheetState();
}

class _OrganizationSheetState extends State<OrganizationSheet> {
  Org? _org;
  String? _problem;
  SettingsTarget? _goTo;
  String? _readFor;

  AccountServices get _services => widget.services;
  Orgs get _orgs => _services.orgs!;
  int _now() => (widget.now ?? _services.now)();

  @override
  void initState() {
    super.initState();
    _land();
    _services.changes.addListener(_changed);
    _maybeRead();
  }

  @override
  void didUpdateWidget(OrganizationSheet old) {
    super.didUpdateWidget(old);
    if (old.orgId != widget.orgId || old.landOnMembers != widget.landOnMembers) {
      // Another organization: landed on its Members again.
      _org = null;
      _problem = null;
      _readFor = null;
      _land();
      _maybeRead();
    }
  }

  @override
  void dispose() {
    _services.changes.removeListener(_changed);
    super.dispose();
  }

  void _land() => _goTo = widget.landOnMembers ? SettingsTarget('members', nonce: DateTime.now().microsecondsSinceEpoch) : null;

  OrgRow? get _row => _services.orgs?.orgRow(widget.orgId);

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _maybeRead();
  }

  /// Read once for each (session, membership) the page has seen (`useEffect(…, [account.session, read, row?.state])`).
  void _maybeRead() {
    final session = _services.session;
    final row = _row;
    if (session == null || row?.state != 'member' || _services.orgs == null) return;
    final key = '${session.accountId}:${widget.orgId}:${row!.state}';
    if (_readFor == key) return;
    _readFor = key;
    unawaited(_read());
  }

  /// The organization in full, read again after every change here: the members, and the kept row with them.
  Future<void> _read() async {
    final id = widget.orgId;
    try {
      final org = await _orgs.fetchOrg(id);
      if (mounted && id == widget.orgId) {
        setState(() {
          _org = org;
          _problem = null;
        });
      }
    } catch (failure) {
      // An invitee, or an organization gone meanwhile: the kept row draws what it can, and the words say the rest.
      if (mounted && id == widget.orgId) setState(() => _problem = accountFailureText(failure));
    }
  }

  Future<void> _onDo(String what, String handle) async {
    if (what == 'remove') {
      await _orgs.removeMember(widget.orgId, handle);
    } else {
      await _orgs.setRole(widget.orgId, handle, what);
    }
    await _read();
  }

  Future<void> _onRemoveAi(OrgAi ai) async {
    await _orgs.removeOrgAi(widget.orgId, ai.id);
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    final orgId = widget.orgId;
    final row = _row;
    final org = _org;
    final me = services.session?.handle ?? '';
    final name = row?.name ?? org?.name ?? 'Organization';
    final role = row?.role ?? 'member';
    final canEdit = row?.state == 'member' && (role == 'owner' || role == 'admin');
    final store = services.prefs;
    final close = widget.onClose;
    Workspace? workspace;
    for (final each in services.workspaces?.value.list ?? const <Workspace>[]) {
      if (each.id == orgWorkspaceId(orgId)) workspace = each;
    }
    final open = widget.onOpenLink;
    final owner = role == 'owner';

    final sections = <SettingsSection>[
      SettingsSection(
        id: 'general',
        label: 'General',
        icon: const AppIcon(Lucide.slidersHorizontal, size: 16),
        hue: 'graphite',
        group: 0,
        content: (context) => org != null && row != null
            ? _General(
                org: org,
                canEdit: canEdit,
                onChange: ({String? name, String? Function()? hue}) async {
                  await _orgs.updateOrg(orgId, name: name, hue: hue);
                  await _read();
                },
              )
            : PaneBody(children: [PaneSection(children: [SettingRow(label: 'Name', value: Text(name))])]),
      ),
      SettingsSection(
        id: 'members',
        label: 'Members',
        icon: const AppIcon(Lucide.users, size: 16),
        hue: 'blue',
        group: 0,
        summary: row != null ? memberWords(row.members) : null,
        content: (context) => row != null
            ? _Members(
                services: services,
                row: row,
                org: org,
                me: me,
                problem: _problem,
                now: _now(),
                onSendLink: widget.onSendLink,
                onInvite: (handle) async {
                  await _orgs.inviteByHandle(orgId, handle);
                  // The key wrapped for them now (docs/SHARED.md, S2), so the team's notes are theirs the moment they accept.
                  unawaited(services.syncNotificationsNow());
                  await _read();
                },
                onDo: _onDo,
                onRemoveAi: _onRemoveAi,
              )
            : const PaneBody(children: [SettingsCallout(child: Text('This organization is not in your list any more.'))]),
      ),
      SettingsSection(
        id: 'workspace',
        label: 'Workspace',
        icon: const AppIcon(Lucide.folderOpen, size: 16),
        hue: 'green',
        group: 1,
        summary: workspace != null ? workspace.name : 'Not on this device yet',
        content: (context) => PaneBody(
          children: [
            PaneSection(
              title: 'Its workspace',
              footer: const Text(teamsNotes),
              children: [
                SettingRow(
                  icon: HueMark(hue: row?.hue),
                  label: workspace?.name ?? name,
                  hint: Text(workspace != null ? 'Made on every member’s device, named and coloured after the organization.' : 'Made here once you have joined and the next sync lands.'),
                ),
                if (workspace != null)
                  SettingRow(icon: const AppIcon(Lucide.folderOpen, size: 20), label: 'Notes filed here', hint: const Text('The home page, with this workspace chosen.'), onPress: widget.onNotes)
                else
                  const SettingRow(icon: AppIcon(Lucide.folderOpen, size: 20), label: 'Notes filed here', hint: Text('The home page, with this workspace chosen.'), disabledReason: 'Nothing is filed here yet.'),
              ],
            ),
          ],
        ),
      ),
      SettingsSection(
        id: 'notifications',
        label: 'Notifications',
        icon: const AppIcon(Lucide.bell, size: 16),
        hue: 'coral',
        group: 1,
        summary: store.value.notifications.mutedOrgs.contains(orgId) ? 'Muted' : 'On',
        content: (context) => ValueListenableBuilder<Preferences>(
          valueListenable: store,
          builder: (context, prefs, _) {
            final notifications = prefs.notifications;
            final others = [for (final id in notifications.mutedOrgs) if (id != orgId) id];
            return PaneBody(
              children: [
                PaneSection(
                  title: 'This organization',
                  footer: const Text('Muted, its team news is not drawn or counted. Its invitations still are. The choice follows you to your other devices.'),
                  children: [
                    SettingRow(
                      label: 'Mute this organization',
                      hint: const Text('Who joined, left or was removed, a rename, a deletion.'),
                      control: GlacierSwitch(
                        ariaLabel: 'Mute this organization',
                        checked: notifications.mutedOrgs.contains(orgId),
                        onCheckedChange: (on) => store.update((now) => now.copyWith(notifications: notifications.copyWith(mutedOrgs: on ? [...others, orgId] : others))),
                      ),
                    ),
                    const SettingsFootnote(child: Text('The four switches over what reaches you at all are under Settings › Notifications.')),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      SettingsSection(
        id: 'report',
        label: 'Report',
        icon: const AppIcon(Lucide.flag, size: 16),
        hue: 'amber',
        group: 2,
        content: (context) => PaneBody(
          children: [
            PaneSection(
              title: 'Report a problem',
              footer: const Text(
                'Team notes are sealed, so we cannot read what is reported unless the email carries it. Reports are read within a few days. To stop seeing an organization’s notes at once, leave it; an owner or an admin can remove a member on Members.',
              ),
              children: [
                SettingRow(
                  icon: const AppIcon(Lucide.flag, size: 20),
                  label: 'Report a member or a note',
                  hint: const Text('Opens an email to Ghost.md’s maker, with this organization named.'),
                  onPress: () => open?.call(reportMail(orgId: orgId, name: name, handle: services.session?.handle)),
                  disabled: open == null,
                ),
              ],
            ),
          ],
        ),
      ),
      SettingsSection(
        id: 'leave',
        label: owner ? 'Delete' : 'Leave',
        icon: AppIcon(owner ? Lucide.trash2 : Lucide.doorOpen, size: 16),
        hue: 'red',
        group: 2,
        content: (context) => PaneBody(
          children: [
            if (owner)
              PaneSection(
                title: 'Delete organization',
                footer: const Text('Every member is told, and their workspace for it goes; the notes filed there stay with each of them, unfiled. Invitations waiting are withdrawn.'),
                children: [
                  TwiceRow(
                    icon: const AppIcon(Lucide.trash2, size: 20),
                    label: 'Delete organization',
                    hint: 'For good. Tap twice.',
                    word: 'Delete',
                    busyWord: 'Deleting',
                    onDo: () async {
                      await _orgs.deleteOrg(orgId);
                      close();
                    },
                  ),
                ],
              )
            else
              PaneSection(
                title: 'Leave organization',
                footer: const Text('Your workspace for it goes from your devices; the notes filed there stay yours, unfiled. The others are told.'),
                children: [
                  TwiceRow(
                    icon: const AppIcon(Lucide.doorOpen, size: 20),
                    label: 'Leave organization',
                    hint: 'Tap twice.',
                    word: 'Leave',
                    busyWord: 'Leaving',
                    onDo: () async {
                      await _orgs.removeMember(orgId, me);
                      close();
                    },
                  ),
                ],
              ),
          ],
        ),
      ),
    ];

    return SettingsScreen(
      open: true,
      onClose: widget.onClose,
      sections: row == null ? [for (final section in sections) if (section.id == 'members') section] : sections,
      goTo: _goTo,
      title: name,
      search: false,
      closeWord: widget.from == OrganizationFrom.settings ? 'Organizations' : (widget.from == OrganizationFrom.dashboard ? name : null),
      split: widget.split,
    );
  }
}

// --- General ---------------------------------------------------------------------------------------------------------

class _General extends StatefulWidget {
  const _General({required this.org, required this.canEdit, required this.onChange});
  final Org org;
  final bool canEdit;
  final Future<void> Function({String? name, String? Function()? hue}) onChange;

  @override
  State<_General> createState() => _GeneralState();
}

class _GeneralState extends State<_General> {
  late String _name = widget.org.name;
  bool _busy = false;
  String? _problem;

  @override
  void didUpdateWidget(_General old) {
    super.didUpdateWidget(old);
    if (old.org.name != widget.org.name) _name = widget.org.name;
  }

  Future<void> _change({String? name, String? Function()? hue}) async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await widget.onChange(name: name, hue: hue);
    } catch (failure) {
      if (mounted) setState(() => _problem = accountFailureText(failure));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final org = widget.org;
    final clean = _name.trim();
    final ready = !_busy && clean.isNotEmpty && clean != org.name;
    final problem = _problem;
    void rename() {
      if (clean.isNotEmpty && clean != org.name) unawaited(_change(name: clean));
    }

    return PaneBody(
      children: [
        PaneSection(
          title: 'Name',
          footer: Text(widget.canEdit ? 'Every member sees the new name, and their workspace for it is renamed with it.' : 'Only the owner or an admin can rename it.'),
          children: [
            if (widget.canEdit)
              SettingsForm(
                children: [
                  GlacierInput(
                    ariaLabel: 'Organization name',
                    placeholder: 'Name',
                    autoCapitalize: TextCapitalization.words,
                    maxLength: 60,
                    value: _name,
                    onChange: (text) => setState(() => _name = text),
                    onSubmitted: (_) => rename(),
                  ),
                  if (problem != null) FormProblem(problem),
                  FormSubmit(wordKey: const ValueKey('organization-rename'), _busy ? 'One moment…' : 'Rename', onPressed: ready ? rename : null),
                ],
              )
            else
              SettingRow(label: 'Name', value: Text(org.name)),
          ],
        ),
        PaneSection(
          title: 'Colour',
          footer: const Text("Worn by the organization's workspace on every member's device: its pill, its folder and its tag on a note."),
          children: [
            if (widget.canEdit)
              CardSwatch(child: WorkspaceSwatch(hue: org.hue ?? 'ink', onHue: (hue) => unawaited(_change(hue: () => hue == 'ink' ? null : hue))))
            else
              SettingRow(label: 'Colour', value: Align(alignment: AlignmentDirectional.centerEnd, widthFactor: 1, child: HueMark(hue: org.hue))),
          ],
        ),
      ],
    );
  }
}

// --- Members ---------------------------------------------------------------------------------------------------------

class _Members extends StatelessWidget {
  const _Members({required this.services, required this.row, required this.org, required this.me, required this.problem, required this.now, required this.onInvite, required this.onDo, required this.onRemoveAi, this.onSendLink});

  final AccountServices services;
  final OrgRow row;
  final Org? org;
  final String me;
  final String? problem;
  final int now;
  final Future<void> Function(String handle) onInvite;
  final Future<void> Function(String what, String handle) onDo;
  final Future<void> Function(OrgAi ai) onRemoveAi;
  final void Function(String title, String url)? onSendLink;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final org = this.org;
    final joined = org != null ? org.members.where((m) => m.state == 'member').length : row.members;
    final ais = org?.ais ?? const <OrgAi>[];
    final canInvite = row.state == 'member' && (row.role == 'owner' || row.role == 'admin');
    final problem = this.problem;
    return PaneBody(
      children: [
        if (problem != null) SettingsCallout(child: Text(problem)),
        PaneSection(
          footer: const Text(teamsNotes),
          children: [
            PaneHero(
              // `.heroHue`: the organization's colour, a round the size of the kit's glyph tile.
              glyph: OverflowBox(maxWidth: t.lenOf('2.75rem'), maxHeight: t.lenOf('2.75rem'), child: HueRound(hue: row.hue, size: t.lenOf('2.75rem'))),
              title: row.name,
              meta: Text('${memberWords(joined)} · ${row.state == 'invited' ? 'You are invited' : 'You are ${roleWords(row.role).toLowerCase()}'}'),
            ),
          ],
        ),
        if (row.state == 'invited')
          PaneSection(
            title: 'Invitation',
            children: [
              SettingRow(
                label: row.invitedBy != null && row.invitedBy!.isNotEmpty ? '${row.invitedBy} invited you' : 'You are invited',
                hint: const Text('Accept to join, and its workspace is made on each of your devices.'),
                layout: SettingRowLayout.stacked,
                control: Align(alignment: AlignmentDirectional.centerStart, child: InviteActions(services: services, orgId: row.id)),
              ),
            ],
          )
        else
          PaneSection(
            title: 'Members',
            footer: ais.isNotEmpty ? const Text(aiNotes) : null,
            children: [
              if (org != null)
                for (final member in org.members) MemberRow(key: ValueKey('member:${member.handle}'), member: member, me: me, role: row.role, now: now, onDo: onDo)
              else
                const SettingRow(label: 'Reading the members…'),
              // The AIs after the people: beside the members, never counted among them.
              for (final ai in ais) AiRow(key: ValueKey('ai:${ai.id}'), ai: ai, me: me, role: row.role, now: now, onRemove: onRemoveAi),
            ],
          ),
        if (row.state == 'member') YourColourCard(services: services, row: row),
        if (canInvite) InviteCard(onInvite: onInvite),
        if (canInvite)
          InviteLinks(
            services: services,
            orgId: row.id,
            inset: true,
            onSend: onSendLink,
            around: (panel) => PaneSection(
              title: 'Invite by link',
              description: const Text('Anyone signed in who has the link can join as a member, until it stops or you turn it off. Send it however you like.'),
              children: [panel],
            ),
          ),
      ],
    );
  }
}

/// What the signed-in person may do to a member row, by the roles (docs/TEAMS.md, D10; `MemberRow`). The owner sets
/// roles and hands over; an admin removes members and invitees, never the owner or another admin; nobody removes
/// themself here - that is Leave, last on the list, tapped twice. Handing the organization over is tapped twice
/// too.
class MemberRow extends StatefulWidget implements PaneRow {
  const MemberRow({super.key, required this.member, required this.me, required this.role, required this.onDo, this.now});
  final Member member;
  final String me;

  /// The signed-in person's own role here.
  final String role;

  /// `remove`, `admin`, `member` or `owner`, and whose.
  final Future<void> Function(String what, String handle) onDo;
  final int? now;

  @override
  State<MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends State<MemberRow> {
  bool _busy = false;
  bool _handing = false;
  String? _problem;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _act(String what) async {
    if (what == 'owner' && !_handing) {
      setState(() => _handing = true);
      HapticsProvider.of(context)(HapticKind.warning);
      _timer?.cancel();
      _timer = Timer(organizationArmedFor, () {
        if (mounted) setState(() => _handing = false);
      });
      return;
    }
    _timer?.cancel();
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await widget.onDo(what, widget.member.handle);
    } catch (failure) {
      if (mounted) setState(() => _problem = accountFailureText(failure));
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _handing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final member = widget.member;
    final role = widget.role;
    final self = member.handle.toLowerCase() == widget.me.toLowerCase();
    final joined = member.state == 'member';
    final canRole = role == 'owner' && !self && joined;
    final canRemove = !self && member.role != 'owner' && (role == 'owner' || (role == 'admin' && member.role != 'admin'));
    final words = <(String, String)>[
      if (canRole) member.role == 'admin' ? ('member', 'Make member') : ('admin', 'Make admin'),
      if (canRole) ('owner', _handing ? 'Tap again to hand over' : 'Hand over'),
      if (canRemove) ('remove', joined ? 'Remove' : 'Withdraw'),
    ];
    return SettingRow(
      label: member.handle,
      // `.role { margin-inline-start: var(--glacier-space-2); vertical-align: 0.1em }`
      labelAfter: Padding(padding: EdgeInsetsDirectional.only(start: t.space(2)), child: RoleChip(member: member)),
      hint: Text(_problem ?? memberLine(member, self: self, now: widget.now)),
      layout: words.isNotEmpty ? SettingRowLayout.stacked : SettingRowLayout.trailing,
      control: words.isEmpty
          ? null
          // `.memberWords`: in a line that wraps, a `--glacier-space-3` apart.
          : Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: t.space(3),
                children: [
                  for (final (what, word) in words) RowAction(key: ValueKey('member-$what'), onPress: () => unawaited(_act(what)), disabled: _busy, child: Text(word)),
                ],
              ),
            ),
    );
  }
}

/// An AI seen in the organization through a member's connector (lib/orgs/types.dart `OrgAi`; Matt: "when an AI has
/// accessed an ORG add it as a member labeled as (AI)"; `AiRow`): a row as a member's is, its name with an AI chip,
/// whose connector it came through and when it was last seen under it, and Remove for the owner, an admin, or that
/// member.
class AiRow extends StatefulWidget implements PaneRow {
  const AiRow({super.key, required this.ai, required this.me, required this.role, required this.onRemove, this.now});
  final OrgAi ai;
  final String me;

  /// The signed-in person's own role here.
  final String role;
  final Future<void> Function(OrgAi ai) onRemove;
  final int? now;

  @override
  State<AiRow> createState() => _AiRowState();
}

class _AiRowState extends State<AiRow> {
  bool _busy = false;
  String? _problem;

  Future<void> _remove() async {
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await widget.onRemove(widget.ai);
    } catch (failure) {
      if (mounted) setState(() => _problem = accountFailureText(failure));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ai = widget.ai;
    final role = widget.role;
    final canRemove = aiIsMine(ai, widget.me) || role == 'owner' || role == 'admin';
    return SettingRow(
      label: ai.name,
      labelAfter: Padding(padding: EdgeInsetsDirectional.only(start: t.space(2)), child: const RoleChip.ai()),
      hint: Text(_problem ?? aiLine(ai, me: widget.me, now: widget.now)),
      layout: canRemove ? SettingRowLayout.stacked : SettingRowLayout.trailing,
      control: canRemove ? Align(alignment: AlignmentDirectional.centerStart, child: RowAction(key: const ValueKey('ai-remove'), onPress: () => unawaited(_remove()), disabled: _busy, child: const Text('Remove'))) : null,
    );
  }
}

/// Invite by handle (`Invite`): they get an invitation in their notifications, and join once they accept.
class InviteCard extends StatefulWidget {
  const InviteCard({super.key, required this.onInvite});
  final Future<void> Function(String handle) onInvite;

  @override
  State<InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<InviteCard> {
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
    final words = _problem ?? _said;
    return PaneSection(
      title: 'Invite',
      description: const Text('By handle. They get an invitation in their notifications, with Accept and Decline, and join once they accept.'),
      children: [
        SettingsForm(
          children: [
            GlacierInput(
              ariaLabel: 'Handle',
              placeholder: 'Handle',
              autoCapitalize: TextCapitalization.none,
              autoCorrect: false,
              spellCheck: false,
              value: _handle,
              onChange: (text) => setState(() => _handle = text),
              onSubmitted: (_) => unawaited(_submit()),
            ),
            if (words != null) FormProblem(words),
            FormSubmit(wordKey: const ValueKey('organization-invite'), _busy ? 'One moment…' : 'Invite', onPressed: _busy || _handle.trim().isEmpty ? null : () => unawaited(_submit())),
          ],
        ),
      ],
    );
  }
}

/// The person's colour in this organization (docs/SHARED.md, S7; `YourColour`): the account's own
/// (colour_card.dart) unless one is chosen here, which is worn here alone. `row.colour` is the one in force; the
/// account's is the list's.
class YourColourCard extends StatefulWidget {
  const YourColourCard({super.key, required this.services, required this.row});
  final AccountServices services;
  final OrgRow row;

  @override
  State<YourColourCard> createState() => _YourColourCardState();
}

class _YourColourCardState extends State<YourColourCard> {
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
    final row = widget.row;
    final overridden = row.colour != widget.services.orgState.colour;
    final problem = _problem;
    return PaneSection(
      title: 'Your colour here',
      footer: Text(
        overridden
            ? 'Worn in this organization alone: your cursor, your selections, your comments and your row in the members.'
            : 'Your account’s colour, from Settings › Account. Pick another to wear it in this organization alone.',
      ),
      children: [
        CardSwatch(child: WorkspaceSwatch(hue: row.colour ?? 'ink', onHue: (hue) => unawaited(_choose(hue == 'ink' ? null : hue)))),
        if (overridden) Align(alignment: AlignmentDirectional.centerStart, child: RowAction(onPress: () => unawaited(_choose(null)), child: const Text('Use your account’s colour'))),
        if (problem != null) SettingsFootnote(child: Text(problem)),
      ],
    );
  }
}

// --- Leave or Delete -------------------------------------------------------------------------------------------------

/// A row tapped twice, armed for a few seconds in between, as a reset is (`TwiceRow`; DeveloperPane.tsx
/// `ResetRow`). What went wrong is said where the hint was.
class TwiceRow extends StatefulWidget implements PaneRow {
  const TwiceRow({super.key, required this.icon, required this.label, required this.hint, required this.word, required this.busyWord, required this.onDo});
  final Widget icon;
  final String label;
  final String hint;
  final String word;
  final String busyWord;
  final Future<void> Function() onDo;

  @override
  State<TwiceRow> createState() => _TwiceRowState();
}

class _TwiceRowState extends State<TwiceRow> {
  String? _problem;

  @override
  Widget build(BuildContext context) => SettingRow(
        icon: widget.icon,
        label: widget.label,
        hint: Text(_problem ?? widget.hint),
        control: ArmedAction(
          word: widget.word,
          busyWord: widget.busyWord,
          onDo: () {
            setState(() => _problem = null);
            return widget.onDo();
          },
          onFailed: (words) {
            if (mounted) setState(() => _problem = words);
          },
        ),
      );
}
