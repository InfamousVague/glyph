import 'dart:async';

import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../orgs/orgs.dart';
import '../../orgs/ui/parts.dart';
import '../account_forms.dart';
import '../invite_actions.dart';
import '../kit/settings_icons.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import '../settings_sections.dart' show SettingsNotPorted, settingsSections;
import 'pane_parts.dart';
import 'settings_host.dart';

/// What Settings' search finds on Organizations (`findable`, src/app/settings/OrganizationsPane.findable.ts), by the
/// names the page draws. Signed out the page is one sentence sending the person to Account, so nothing is listed.
List<SettingsFindable> organizationsFindable({required bool signedIn}) => signedIn
    ? const [
        SettingsFindable('Your organizations', 'teams org team members'),
        SettingsFindable('New organization', 'create make team org start'),
      ]
    : const [];

/// Organizations' row in the list (SettingsSheet.tsx): how many are joined, or "Signed out".
String organizationsSummary(AccountServices? services) => services != null && services.signedIn ? '${services.joined.length} joined' : 'Signed out';

/// Port of `OrganizationsPane` (src/app/settings/OrganizationsPane.tsx; docs/TEAMS.md, D6): the organizations the
/// account is in, each a row that opens the organization's own screen (organization_sheet.dart); the invitations
/// waiting, each with Accept and Decline inline ([InviteActions]); and a name to make a new one, which opens as
/// soon as the service answers. The list is the one the sync pass keeps (`Orgs.orgsState`), so the page draws at
/// once and is the service's truth by the next pass.
///
/// Signed out there is nothing to list and nothing to make: the words send the person to Account.
///
/// What differs from the web original:
/// - The account and the organizations are the [AccountServices] it is handed ([services], or the [AccountScope]
///   over Settings). Without one it is as it was before there was an account: the sentence signed out, and for
///   [signedIn] with nothing behind it the card that says the page waits.
/// - **Joining by a link pasted in** is not on this page on the web either: a link opens the app and the join
///   sheet (lib/orgs/ui/join_sheet.dart).
class OrganizationsPane extends StatelessWidget {
  const OrganizationsPane({super.key, this.signedIn = false, this.services, this.onOpenAccount, this.onOrganization});

  /// Whether an account is signed in, for a build with no [services] to say so.
  final bool signedIn;
  final AccountServices? services;

  /// Lands on Account; without it the word is a plain word.
  final VoidCallback? onOpenAccount;

  /// Opens an organization's own screen, from its row or once it is made.
  final void Function(String orgId)? onOrganization;

  static Widget hosted(BuildContext context) {
    final host = SettingsHost.maybeOf(context);
    return OrganizationsPane(
      signedIn: host?.features.signedIn ?? false,
      services: AccountScope.maybeOf(context),
      onOpenAccount: host == null ? null : () => host.go('account'),
      onOrganization: host?.onOrganization,
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = this.services;
    if (services == null && signedIn) return SettingsNotPorted(spec: settingsSections.firstWhere((spec) => spec.id == 'organizations'));
    return AccountBuilder(
      services: services,
      builder: (context) {
        if (services == null || !services.signedIn) {
          return PaneBody(
            children: [
              SettingsCallout(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Organizations come with an account. Sign in under '),
                      WidgetSpan(alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic, child: GoWord('Account', onPress: onOpenAccount)),
                      const TextSpan(text: ' to make or join one.'),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
        final list = services.orgState.list;
        final joined = [for (final row in list) if (row.state == 'member') row];
        final invited = [for (final row in list) if (row.state == 'invited') row];
        return PaneBody(
          children: [
            if (invited.isNotEmpty)
              PaneSection(
                title: 'Invitations',
                children: [
                  for (final row in invited)
                    SettingRow(
                      key: ValueKey('invitation:${row.id}'),
                      icon: HueMark(hue: row.hue),
                      label: row.name,
                      hint: Text(row.invitedBy != null && row.invitedBy!.isNotEmpty ? 'Invited by ${row.invitedBy} · ${memberWords(row.members)}' : memberWords(row.members)),
                      layout: SettingRowLayout.stacked,
                      control: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: InviteActions(
                          services: services,
                          orgId: row.id,
                          onAnswered: (accepted) {
                            if (accepted) onOrganization?.call(row.id);
                          },
                        ),
                      ),
                    ),
                ],
              ),
            PaneSection(
              title: 'Your organizations',
              children: [
                if (joined.isNotEmpty)
                  for (final row in joined)
                    SettingRow(
                      key: ValueKey('organization:${row.id}'),
                      icon: HueMark(hue: row.hue),
                      label: row.name,
                      hint: Text('${roleWords(row.role)} · ${memberWords(row.members)}'),
                      onPress: () => onOrganization?.call(row.id),
                    )
                else
                  const SettingRow(
                    icon: SettingsIcon(SettingsGlyph.userGroup, size: 20),
                    label: 'None yet',
                    hint: Text('Make one below, or accept an invitation when one arrives.'),
                  ),
              ],
            ),
            NewOrganizationCard(orgs: services.orgs, onMade: (id) => onOrganization?.call(id)),
            const SettingsFootnote(
              child: Text('An organization’s name and its members’ handles are kept on the service in the clear, so an invitation can reach them. Notes stay encrypted on your own devices.'),
            ),
          ],
        );
      },
    );
  }
}

/// A name to make a new organization (OrganizationsPane.tsx `NewOrganization`): made on the service, and opened at
/// once.
class NewOrganizationCard extends StatefulWidget {
  const NewOrganizationCard({super.key, required this.orgs, required this.onMade});
  final Orgs? orgs;
  final ValueChanged<String> onMade;

  @override
  State<NewOrganizationCard> createState() => _NewOrganizationCardState();
}

class _NewOrganizationCardState extends State<NewOrganizationCard> {
  String _name = '';
  bool _busy = false;
  String? _problem;

  Future<void> _submit() async {
    final clean = _name.trim();
    final orgs = widget.orgs;
    if (clean.isEmpty || _busy || orgs == null) return;
    final made = widget.onMade;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final org = await orgs.createOrg(clean);
      if (mounted) setState(() => _name = '');
      made(org.id);
    } catch (failure) {
      if (mounted) setState(() => _problem = accountFailureText(failure));
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final ready = !_busy && _name.trim().isNotEmpty && widget.orgs != null;
    return PaneSection(
      title: 'New organization',
      description: const Text('A team by name. You own it, and can invite people by their handle; each member gets its workspace.'),
      children: [
        SettingsForm(
          children: [
            GlacierInput(
              ariaLabel: 'Organization name',
              placeholder: 'Name',
              autoCapitalize: TextCapitalization.words,
              maxLength: 60,
              value: _name,
              onChange: (text) => setState(() => _name = text),
              onSubmitted: (_) => unawaited(_submit()),
            ),
            if (problem != null) FormProblem(problem),
            FormSubmit(wordKey: const ValueKey('new-organization-submit'), _busy ? 'One moment…' : 'Create', onPressed: ready ? () => unawaited(_submit()) : null),
          ],
        ),
      ],
    );
  }
}
