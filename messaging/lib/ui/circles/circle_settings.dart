/// A circle's settings over the whole window, with a sidebar of its own (Matt, 2026-11-17: "there are no server settings
/// we should be able to manage roles users etc and other basic circle settings with a full screen sidebar and main page
/// settings"): Overview (its name, picture, colour and icon), Spaces (each to rename, retype, move under a heading or
/// delete, and new ones), Members (who is in it, inviting more, and what the owner can do with each), Roles (owner,
/// admins and members: who each is and what each may do), Invite link (the link and its QR code), and Leave (deleting
/// it, for its owner). Beside one another on a wide window; on a phone the sidebar is the first page and a section
/// opens over it. Whoever may not change the circle reads what it is.
library;

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../circles/circle.dart';
import '../../circles/circles.dart';
import '../../desktop/ui/qr.dart';
import '../../kit/semantic_colors.dart';
import '../../kit/settings_kit.dart';
import '../../kit/settings_type.dart';
import '../../voice/channels.dart';
import '../common.dart';
import '../dialup/bevel.dart';
import '../shell.dart';
import 'arrange_spaces.dart';
import 'circle_face.dart';
import 'circle_invite.dart';
import 'circle_picture.dart';
import 'new_circle.dart';

/// The sections of a circle's settings, in the sidebar's order.
enum CircleSettingsSection {
  overview('Overview', Lucide.layoutGrid, 'blue'),
  spaces('Spaces', Lucide.listTree, 'amber'),
  members('Members', Lucide.users, 'green'),
  roles('Roles', Lucide.shieldCheck, 'indigo'),
  invite('Invite link', Lucide.link, 'purple'),
  leave('Leave', Lucide.logOut, 'red');

  const CircleSettingsSection(this.label, this.icon, this.hue);
  final String label;
  final LucideIcon icon;
  final String hue;
}

/// How wide a window must be for the sidebar and a section side by side.
const double circleSettingsWideAt = 720;

/// Opens [c]'s settings over the whole window (above the list and the pane, as a page of its own), on [section].
void openCircleSettingsFull(BuildContext context, String seed, {CircleSettingsSection section = CircleSettingsSection.overview, bool qr = false}) {
  Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    settings: const RouteSettings(name: 'circle-settings'),
    transitionDuration: const Duration(milliseconds: 240),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, _, _) => CircleSettingsPage(seed: seed, section: section, qr: qr),
    transitionsBuilder: (context, a, _, child) => FadeTransition(
      opacity: a,
      child: SlideTransition(position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child),
    ),
  ));
}

class CircleSettingsPage extends StatefulWidget {
  const CircleSettingsPage({super.key, required this.seed, this.section = CircleSettingsSection.overview, this.qr = false});
  final String seed;
  final CircleSettingsSection section;
  final bool qr;

  @override
  State<CircleSettingsPage> createState() => _CircleSettingsPageState();
}

class _CircleSettingsPageState extends State<CircleSettingsPage> {
  late CircleSettingsSection _section = widget.section;
  late bool _qr = widget.qr;

  @override
  Widget build(BuildContext context) {
    final circles = Circles.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([circles, Voice.instance]),
      builder: (context, _) {
        final c = circles.bySeed(widget.seed);
        if (c == null) return GhostPage(title: 'Circle', body: const Center(child: Text('You left this circle.')));
        return LayoutBuilder(builder: (context, box) {
          if (box.maxWidth < circleSettingsWideAt) {
            // A phone: the sidebar is the page; a section opens over it with its way back.
            return GhostPage(
              title: 'Circle settings',
              body: _Sidebar(circle: c, chosen: null, onChoose: (s) => push<void>(context, (_) => _SectionPage(seed: c.seed, section: s))),
            );
          }
          final t = context.tokens;
          return ColoredBox(
            color: t.color('glacier-bg'),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                key: const ValueKey('circle-settings-sidebar'),
                width: 260,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: t.color('app-paper'), border: Border(right: BorderSide(color: t.color('app-rule')))),
                  child: GhostPage(
                    title: 'Circle settings',
                    body: _Sidebar(circle: c, chosen: _section, onChoose: (s) => setState(() => _section = s)),
                  ),
                ),
              ),
              Expanded(
                child: GhostPage(
                  key: ValueKey('circle-settings-${_section.name}'),
                  title: _section.label,
                  back: false,
                  actions: [IconTap(key: const ValueKey('circle-settings-close'), icon: Lucide.x, label: 'Close settings', onPressed: () => Navigator.of(context).maybePop())],
                  body: _SectionBody(circle: c, section: _section, qr: _qr, onQr: () => setState(() => _qr = !_qr)),
                ),
              ),
            ]),
          );
        });
      },
    );
  }
}

/// The sidebar: the circle at its head (its face, name and how many spaces and people), then each section.
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.circle, required this.chosen, required this.onChoose});
  final Circle circle;
  final CircleSettingsSection? chosen;
  final ValueChanged<CircleSettingsSection> onChoose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = circle;
    final people = circlePeople(c);
    final owner = _isOwner(c);
    return ListView(
      padding: EdgeInsets.fromLTRB(t.space(3), t.space(1), t.space(3), t.space(8)),
      children: [
        Row(children: [
          CircleFace.of(c, size: 44, selected: c.picture == null),
          SizedBox(width: t.space(3)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'bold')),
              Text('${c.spaces.length} ${c.spaces.length == 1 ? 'space' : 'spaces'} · ${people.length} ${people.length == 1 ? 'person' : 'people'}', style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
            ]),
          ),
        ]),
        SizedBox(height: t.space(4)),
        for (final s in CircleSettingsSection.values)
          GlacierScope(
            attrs: {'hue': s.hue},
            child: _SidebarRow(
              key: ValueKey('circle-settings-tab-${s.name}'),
              section: s,
              label: s == CircleSettingsSection.leave && owner ? 'Leave or delete' : s.label,
              chosen: chosen == s,
              onPressed: () => onChoose(s),
            ),
          ),
      ],
    );
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({super.key, required this.section, required this.label, required this.chosen, required this.onPressed});
  final CircleSettingsSection section;
  final String label;
  final bool chosen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bevel = isBevelChrome(t);
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2) + 2),
        decoration: BoxDecoration(
          color: chosen ? t.color('app-paper-3') : (state.hovered || state.pressed ? t.color('app-paper-2') : const Color(0x00000000)),
          borderRadius: BorderRadius.circular(bevel ? 0 : t.radius('md')),
        ),
        child: Row(children: [
          AppIcon(section.icon, size: 18, color: section == CircleSettingsSection.leave ? t.danger : t.color('app-ink-2')),
          SizedBox(width: t.space(3)),
          Expanded(child: Text(label, style: pageText(t, t.fontSize('sm'), weight: chosen ? 'semibold' : 'medium', color: section == CircleSettingsSection.leave ? t.danger : t.color('app-ink')))),
        ]),
      ),
    );
  }
}

/// A section as a page of its own: a phone's, over the sidebar.
class _SectionPage extends StatefulWidget {
  const _SectionPage({required this.seed, required this.section});
  final String seed;
  final CircleSettingsSection section;

  @override
  State<_SectionPage> createState() => _SectionPageState();
}

class _SectionPageState extends State<_SectionPage> {
  bool _qr = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Circles.instance, Voice.instance]),
      builder: (context, _) {
        final c = Circles.instance.bySeed(widget.seed);
        if (c == null) return GhostPage(title: widget.section.label, body: const Center(child: Text('You left this circle.')));
        return GhostPage(title: widget.section.label, body: _SectionBody(circle: c, section: widget.section, qr: _qr, onQr: () => setState(() => _qr = !_qr)));
      },
    );
  }
}

bool _isOwner(Circle c) => c.manifest.ownerId.isNotEmpty && Circles.instance.signer?.id == c.manifest.ownerId;

/// One section's settings.
class _SectionBody extends StatelessWidget {
  const _SectionBody({required this.circle, required this.section, required this.qr, required this.onQr});
  final Circle circle;
  final CircleSettingsSection section;
  final bool qr;
  final VoidCallback onQr;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = circle;
    final circles = Circles.instance;
    // As the circle's roles say (lib/circles: CirclePerm): its look, its spaces.
    final edit = section == CircleSettingsSection.spaces ? circles.can(c, CirclePerm.spaces) : circles.can(c, CirclePerm.circle);
    final owner = _isOwner(c);
    final gap = SizedBox(height: t.space(6));
    final readOnly = SettingsCallout(child: const Text('Only the circle\'s owner and the admins they made can change it.'));
    final children = switch (section) {
      CircleSettingsSection.overview => [
          Center(child: CircleFace.of(c, size: 76, selected: c.picture == null)),
          SizedBox(height: t.space(2)),
          Text(c.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xl'), weight: 'bold')),
          SizedBox(height: t.space(5)),
          if (!edit) ...[readOnly, gap],
          if (edit) ...[
            PaneSection(title: 'Circle', children: [
              SettingRow(key: const ValueKey('circle-rename'), icon: AppIcon(Lucide.pencil, size: 18), label: 'Name', value: Text(c.name), onPress: () => askCircleWords(context, title: 'Rename circle', initial: c.name, then: (n) => circles.edit(c, name: n))),
              SettingRow(
                key: const ValueKey('circle-picture'),
                icon: AppIcon(Lucide.imagePlus, size: 18),
                label: c.picture == null ? 'Choose a picture' : 'Change the picture',
                hint: const Text('Shown in the icon\'s place'),
                onPress: () async {
                  final p = await pickCirclePicture(context);
                  if (p != null) circles.edit(c, picture: p);
                },
              ),
              if (c.picture != null) SettingRow(icon: AppIcon(Lucide.trash2, size: 18), label: 'Use the icon instead', onPress: () => circles.edit(c, clearPicture: true)),
            ]),
            gap,
            PaneSection(title: 'Colour', children: [SettingRowBox(child: CircleHuePicker(value: c.hue, onChanged: (h) => circles.edit(c, hue: h)))]),
            gap,
            PaneSection(title: 'Icon', children: [SettingRowBox(child: CircleIconPicker(hue: c.hue, value: c.icon, onChanged: (i) => circles.edit(c, icon: i)))]),
          ],
        ],
      CircleSettingsSection.spaces => [
          if (!edit) ...[readOnly, gap],
          PaneSection(
            title: '${c.spaces.length} ${c.spaces.length == 1 ? 'space' : 'spaces'}',
            description: Text(edit ? 'Press a space to rename it, change what kind it is, put it under a heading or delete it.' : 'The spaces in ${c.name}.'),
            children: [
              for (final s in c.spaces)
                SettingRow(
                  key: ValueKey('circle-settings-space-${s.seed}'),
                  icon: AppIcon(spaceKindIcon(s.kind), size: 18),
                  label: s.name,
                  hint: Text([spaceKindTitle(s.kind), if (s.section != null) s.section!].join(' · ')),
                  onPress: edit ? () => showArrangeSpaceMenu(context, c, s) : null,
                ),
              if (edit) ...[
                SettingRow(key: const ValueKey('circle-settings-new-space'), icon: AppIcon(Lucide.plus, size: 18), label: 'New space', hint: const Text('A chat, a voice chat, or a files space'), onPress: () => push<void>(context, (_) => NewCircleSpaceScreen(circle: c))),
                SettingRow(key: const ValueKey('circle-arrange'), icon: AppIcon(Lucide.chevronsUpDown, size: 18), label: 'Arrange spaces', hint: const Text('Their order and headings'), onPress: () => push<void>(context, (_) => ArrangeCircleSpacesScreen(seed: c.seed))),
              ],
            ],
          ),
        ],
      CircleSettingsSection.members => [
          PaneSection(
            title: '${circlePeople(c).length} ${circlePeople(c).length == 1 ? 'person' : 'people'}',
            description: Text(circles.can(c, CirclePerm.roles) ? 'Press someone to give them roles${owner ? ', or make them an admin' : ''}.' : 'Who is in ${c.name}, and their roles.'),
            children: [
              if (circles.can(c, CirclePerm.invite)) SettingRow(key: const ValueKey('circle-settings-invite'), icon: AppIcon(Lucide.userPlus, size: 18), label: 'Invite people', hint: const Text('Friends in the app, anyone by a text, or the link.'), onPress: () => showCircleInvite(context, c)),
              for (final p in circlePeople(c))
                SettingRow(
                  key: ValueKey('circle-person-${p.id}'),
                  icon: AppIcon(p.owner ? Lucide.crown : (p.admin ? Lucide.shieldCheck : Lucide.userRound), size: 18),
                  label: p.me ? '${p.name} (you)' : p.name,
                  labelColor: circleRoleInk(t, p),
                  hint: c.manifest.rolesOf(p.id).isEmpty ? null : Text(c.manifest.rolesOf(p.id).map((r) => r.name).join(', ')),
                  value: CircleRoleTag(person: p),
                  onPress: !p.owner && (owner || circles.can(c, CirclePerm.roles)) ? () => _personMenu(context, c, p) : null,
                ),
            ],
          ),
        ],
      CircleSettingsSection.roles => () {
          final people = circlePeople(c);
          final m = c.manifest;
          final manage = circles.can(c, CirclePerm.roles);
          final owners = [for (final p in people) if (p.owner) p];
          // Admins made by hand, with no role: everything, as before roles.
          final admins = [for (final p in people) if (p.admin && m.rolesOf(p.id).isEmpty) p];
          String names(List<CirclePerson> l) => l.isEmpty ? 'No one yet' : l.map((p) => p.me ? 'You' : p.name).join(', ');
          String perms(Set<CirclePerm> ps) => ps.isEmpty ? 'Nothing more than everyone' : [for (final p in CirclePerm.values) if (ps.contains(p)) p.label].join(', ');
          return [
            PaneSection(
              title: 'Roles',
              description: Text(manage ? 'Each a name, a colour and what it lets people do. Press one to change it and choose who has it.' : 'The roles in ${c.name}, and what each lets people do.'),
              children: [
                for (final r in m.roles)
                  SettingRow(
                    key: ValueKey('circle-role-${r.id}'),
                    icon: GlacierScope(attrs: {'hue': r.hue}, child: AppIcon(Lucide.shieldCheck, size: 18)),
                    label: r.name,
                    hint: Text(perms(r.perms)),
                    value: Text('${m.roleAssignments.values.where((ids) => ids.contains(r.id)).length}'),
                    onPress: manage ? () => push<void>(context, (_) => _RolePage(seed: c.seed, roleId: r.id)) : null,
                  ),
                if (m.roles.isEmpty) SettingRow(icon: AppIcon(Lucide.shieldCheck, size: 18), label: 'No roles yet', disabled: true),
                if (manage && m.roles.length < circleRolesMax)
                  SettingRow(
                    key: const ValueKey('circle-role-new'),
                    icon: AppIcon(Lucide.plus, size: 18),
                    label: 'New role',
                    onPress: () => askCircleWords(context, title: 'New role', then: (name) async {
                      final r = CircleRole.make(name, hue: circleHues[m.roles.length % circleHues.length], perms: const {CirclePerm.invite});
                      final ok = await circles.saveRole(circles.bySeed(c.seed) ?? c, r);
                      if (!context.mounted) return;
                      if (!ok) return toast(context, 'Couldn\'t make the role', tone: GlacierToastTone.danger);
                      push<void>(context, (_) => _RolePage(seed: c.seed, roleId: r.id));
                    }),
                  ),
              ],
            ),
            gap,
            PaneSection(
              title: 'Everyone',
              description: const Text('What everyone in the circle may do, whatever their roles. Changing the circle, its spaces or its roles is never everyone\'s.'),
              children: [
                for (final p in CirclePerm.values)
                  if (!p.signs)
                    SettingRow(
                      key: ValueKey('circle-everyone-${p.wire}'),
                      label: p.label,
                      hint: Text(p.blurb),
                      control: GlacierSwitch(
                        checked: m.everyone.contains(p),
                        disabled: !manage,
                        ariaLabel: 'Everyone may ${p.label.toLowerCase()}',
                        onCheckedChange: (on) => circles.setEveryone(circles.bySeed(c.seed) ?? c, on ? {...m.everyone, p} : ({...m.everyone}..remove(p))),
                      ),
                    ),
              ],
            ),
            gap,
            PaneSection(
              title: 'Owner',
              description: const Text('Made the circle. Can do everything, give any role, make admins, and delete the circle.'),
              children: [SettingRow(key: const ValueKey('circle-role-owner'), icon: AppIcon(Lucide.crown, size: 18), label: names(owners))],
            ),
            gap,
            PaneSection(
              title: 'Admins',
              description: const Text('Made by the owner, with no role: they can do everything but delete the circle or make admins.'),
              children: [
                for (final p in admins)
                  SettingRow(key: ValueKey('circle-role-admin-${p.id}'), icon: AppIcon(Lucide.shieldCheck, size: 18), label: p.me ? 'You' : p.name, onPress: owner ? () => circlePersonMenu(context, c, p) : null),
                if (admins.isEmpty) SettingRow(icon: AppIcon(Lucide.shieldCheck, size: 18), label: 'No admins', disabled: true),
              ],
            ),
          ];
        }(),
      CircleSettingsSection.invite => [
          PaneSection(
            title: 'Invite link',
            description: const Text('Whoever has the link is in the circle, so share it with people you know.'),
            children: [
              if (circles.can(c, CirclePerm.invite)) SettingRow(key: const ValueKey('circle-settings-invite-people'), icon: AppIcon(Lucide.userPlus, size: 18), label: 'Invite people', onPress: () => showCircleInvite(context, c)),
              SettingRow(
                key: const ValueKey('circle-copy-link'),
                icon: AppIcon(Lucide.copy, size: 18),
                label: 'Copy invite link',
                onPress: () {
                  Clipboard.setData(ClipboardData(text: c.link));
                  toast(context, 'Invite link copied');
                },
              ),
              SettingRow(key: const ValueKey('circle-qr'), icon: AppIcon(Lucide.scanText, size: 18), label: qr ? 'Hide the QR code' : 'Show a QR code', onPress: onQr),
              if (qr)
                SettingRowBox(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(t.space(2)),
                      child: Semantics(label: 'The invite link to ${c.name}, as a QR code', child: ExcludeSemantics(child: QrView(data: c.link, size: 200, radius: isBevelChrome(t) ? 0 : 14))),
                    ),
                  ),
                ),
            ],
          ),
        ],
      CircleSettingsSection.leave => [
          PaneSection(children: [
            SettingRow(key: const ValueKey('circle-leave'), icon: AppIcon(Lucide.logOut, size: 18), label: 'Leave circle', hint: const Text('It goes from your list; its link brings you back.'), onPress: () => _leave(context, c)),
            if (owner) SettingRow(key: const ValueKey('circle-delete'), icon: AppIcon(Lucide.trash2, size: 18), label: 'Delete circle', hint: const Text('Takes every space out of it for everyone, then leaves it.'), onPress: () => _delete(context, c)),
          ]),
        ],
    };
    return GlacierScope(
      attrs: {'hue': section.hue},
      child: SettingsPaneScope(
        finder: SettingsFinder(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
          children: [Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)))],
        ),
      ),
    );
  }

  /// What can be done with someone from Members: their roles, and (the owner's) making them an admin by hand.
  void _personMenu(BuildContext context, Circle c, CirclePerson p) {
    final circles = Circles.instance;
    final owner = _isOwner(c);
    showChoices(context, title: '${p.name} · ${c.manifest.rolesOf(p.id).isEmpty ? p.role : c.manifest.rolesOf(p.id).map((r) => r.name).join(', ')}', choices: [
      if (circles.can(c, CirclePerm.roles)) Choice('Roles…', Lucide.shieldCheck, () => push<void>(context, (_) => _PersonRolesPage(seed: c.seed, person: p)), hint: c.manifest.roles.isEmpty ? 'Make roles in Roles first' : null),
      if (owner && c.manifest.rolesOf(p.id).isEmpty)
        p.admin
            ? Choice('Remove as admin', Lucide.userMinus, () => circles.grantAdmin(c, p.id, on: false))
            : Choice('Make admin', Lucide.crown, () => circles.grantAdmin(c, p.id), hint: 'Everything but deleting the circle'),
    ]);
  }

  void _leave(BuildContext context, Circle c) {
    showChoices(context, title: 'Leave ${c.name}? It goes from your list; its link brings you back.', choices: [
      Choice('Leave circle', Lucide.logOut, () => _gone(context, c, () => Circles.instance.leave(c), 'Left ${c.name}'), danger: true),
    ]);
  }

  void _delete(BuildContext context, Circle c) {
    showChoices(context, title: 'Delete ${c.name}? Every space goes from it for everyone in it, and it goes from your list. This can\'t be undone.', choices: [
      Choice('Delete circle', Lucide.trash2, () => _gone(context, c, () async {
            // A manifest has no "closed" mark: one with no spaces is said to everyone, then the circle is left here.
            for (final s in c.spaces) {
              final now = Circles.instance.bySeed(c.seed);
              if (now == null) break;
              await Circles.instance.removeSpace(now, s.seed);
            }
            final now = Circles.instance.bySeed(c.seed);
            if (now != null) await Circles.instance.leave(now);
          }, '${c.name} deleted'), danger: true),
    ]);
  }

  /// Does [away], then puts the settings and the circle away, saying [words].
  Future<void> _gone(BuildContext context, Circle c, Future<void> Function() away, String words) async {
    final nav = Navigator.of(context, rootNavigator: true);
    final shell = AppShell.maybeOf(context);
    final open = shell?.openCircleSeed == c.seed;
    await away();
    if (context.mounted) toast(context, words);
    nav.popUntil((r) => r.settings.name != 'circle-settings' || r.isFirst);
    if (open) shell?.go('messages');
  }
}


/// A role: its name and colour, what it lets people do, and who has it (lib/circles: CircleRole). What can change the
/// circle, its spaces or its roles is the owner's alone to give, since whoever has it becomes an admin too.
class _RolePage extends StatelessWidget {
  const _RolePage({required this.seed, required this.roleId});
  final String seed;
  final String roleId;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final circles = Circles.instance;
    return ListenableBuilder(
      listenable: circles,
      builder: (context, _) {
        final c = circles.bySeed(seed);
        final r = c?.manifest.roles.where((x) => x.id == roleId).firstOrNull;
        if (c == null || r == null) return GhostPage(title: 'Role', body: const Center(child: Text('This role is gone.')));
        final owner = _isOwner(c);
        Future<void> save(CircleRole next) async {
          final ok = await circles.saveRole(circles.bySeed(seed) ?? c, next);
          if (!ok && context.mounted) toast(context, 'Couldn\'t change the role', tone: GlacierToastTone.danger);
        }

        final people = [for (final p in circlePeople(c)) if (!p.owner) p];
        final holders = c.manifest.roleAssignments;
        return GhostPage(
          title: r.name,
          body: ListView(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
            children: [
              PaneSection(title: 'Role', children: [
                SettingRow(key: const ValueKey('role-rename'), icon: AppIcon(Lucide.pencil, size: 18), label: 'Name', value: Text(r.name), onPress: () => askCircleWords(context, title: 'Rename role', initial: r.name, then: (n) => save(r.copyWith(name: n)))),
              ]),
              SizedBox(height: t.space(6)),
              PaneSection(title: 'Colour', children: [SettingRowBox(child: CircleHuePicker(value: r.hue, onChanged: (h) => save(r.copyWith(hue: h))))]),
              SizedBox(height: t.space(6)),
              PaneSection(
                title: 'What it lets people do',
                description: Text(owner ? 'Changing the circle, its spaces or its roles makes whoever has the role an admin too.' : 'Changing the circle, its spaces or its roles is the owner\'s to give.'),
                children: [
                  for (final p in CirclePerm.values)
                    SettingRow(
                      key: ValueKey('role-perm-${p.wire}'),
                      label: p.label,
                      hint: Text(p.blurb),
                      control: GlacierSwitch(
                        checked: r.perms.contains(p),
                        disabled: p.signs && !owner,
                        ariaLabel: p.label,
                        onCheckedChange: (on) => save(r.copyWith(perms: on ? {...r.perms, p} : ({...r.perms}..remove(p)))),
                      ),
                    ),
                ],
              ),
              SizedBox(height: t.space(6)),
              PaneSection(
                title: 'Who has it',
                children: [
                  for (final p in people)
                    SettingRow(
                      key: ValueKey('role-holder-${p.id}'),
                      label: p.me ? '${p.name} (you)' : p.name,
                      control: GlacierSwitch(
                        checked: holders[p.id]?.contains(r.id) ?? false,
                        disabled: r.signs && !owner,
                        ariaLabel: '${p.name} has ${r.name}',
                        onCheckedChange: (on) async {
                          final now = circles.bySeed(seed) ?? c;
                          final mine = [...?now.manifest.roleAssignments[p.id]];
                          on ? mine.add(r.id) : mine.remove(r.id);
                          final ok = await circles.setRolesOf(now, p.id, mine);
                          if (!ok && context.mounted) toast(context, 'Couldn\'t change ${p.name}\'s roles', tone: GlacierToastTone.danger);
                        },
                      ),
                    ),
                  if (people.isEmpty) SettingRow(label: 'No one else is in the circle yet', disabled: true),
                ],
              ),
              SizedBox(height: t.space(6)),
              PaneSection(children: [
                SettingRow(
                  key: const ValueKey('role-delete'),
                  icon: AppIcon(Lucide.trash2, size: 18),
                  label: 'Delete role',
                  onPress: () => showChoices(context, title: 'Delete ${r.name}? Whoever has it loses what it gave.', choices: [
                    Choice('Delete role', Lucide.trash2, () async {
                      final nav = Navigator.of(context);
                      await circles.deleteRole(circles.bySeed(seed) ?? c, r.id);
                      nav.maybePop();
                    }, danger: true),
                  ]),
                ),
              ]),
            ],
          ),
        );
      },
    );
  }
}

/// Someone's roles in a circle, each switched on or off.
class _PersonRolesPage extends StatelessWidget {
  const _PersonRolesPage({required this.seed, required this.person});
  final String seed;
  final CirclePerson person;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final circles = Circles.instance;
    return ListenableBuilder(
      listenable: circles,
      builder: (context, _) {
        final c = circles.bySeed(seed);
        if (c == null) return GhostPage(title: person.name, body: const Center(child: Text('You left this circle.')));
        final owner = _isOwner(c);
        final mine = c.manifest.roleAssignments[person.id] ?? const [];
        return GhostPage(
          title: '${person.name}\'s roles',
          body: ListView(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
            children: [
              PaneSection(
                description: Text('What ${person.name} may do: what everyone may, and what these give.'),
                children: [
                  for (final r in c.manifest.roles)
                    SettingRow(
                      key: ValueKey('person-role-${r.id}'),
                      icon: GlacierScope(attrs: {'hue': r.hue}, child: AppIcon(Lucide.shieldCheck, size: 18)),
                      label: r.name,
                      hint: Text(r.perms.isEmpty ? 'Nothing more than everyone' : [for (final p in CirclePerm.values) if (r.perms.contains(p)) p.label].join(', ')),
                      control: GlacierSwitch(
                        checked: mine.contains(r.id),
                        disabled: r.signs && !owner,
                        ariaLabel: '${person.name} has ${r.name}',
                        onCheckedChange: (on) async {
                          final now = circles.bySeed(seed) ?? c;
                          final next = [...?now.manifest.roleAssignments[person.id]];
                          on ? next.add(r.id) : next.remove(r.id);
                          final ok = await circles.setRolesOf(now, person.id, next);
                          if (!ok && context.mounted) toast(context, 'Couldn\'t change ${person.name}\'s roles', tone: GlacierToastTone.danger);
                        },
                      ),
                    ),
                  if (c.manifest.roles.isEmpty) SettingRow(label: 'No roles yet: make them in Roles', disabled: true),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
