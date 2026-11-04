/// Inviting people to an organization, in a modal of its own (Matt, 2026-11-04: "Open the invite section as a modal
/// and default to email based invites"): "Invite to" and its name, and the three ways, Email, Link and Handle, as segments
/// over the one that is chosen. It opens on Email, its address field focused (the keyboard up on a phone).
///
/// Each way is the widget it was inline, unchanged: Email is [InviteEmails] (an address and Send, the invitations
/// waiting with Send again and Turn off), Link is [InviteLinks] (make, copy, send, turn off), Handle is
/// [InviteByHandle] (a handle and Invite, the invitation in their notifications). Opened from the organization's
/// dashboard - its hero's Invite and the dock's - and from Invite people on the Members page of its settings
/// (lib/orgs/ui/organization_screen.dart, lib/settings/organization_sheet.dart); only for an owner or an admin, never
/// while the app is local only, as before.
///
/// A drawer from the foot on a phone, a card in the middle on a wide window (the opened Fold, a tablet, the Mac). In
/// Simple mode it is the same three ways without the sentence under the segments.
library;

import 'dart:async';

import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../settings/invite_emails.dart';
import '../../settings/invite_links.dart';
import '../../settings/kit/settings_type.dart';
import '../../shell/wide_screen.dart';
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import 'parts.dart';

/// The ways in the modal, in its order.
enum InviteWay { email, link, handle }

/// The invite modal (`InviteSheet`): build it while it is open, stop building it to close ([Sheet]).
class InviteSheet extends StatefulWidget {
  const InviteSheet({super.key, required this.services, required this.orgId, required this.name, required this.onClose, required this.onInvite, this.onSendLink, this.way = InviteWay.email, this.now});

  final AccountServices services;
  final String orgId;

  /// The organization's name, for the title.
  final String name;
  final VoidCallback onClose;

  /// Invites a handle; the page that opened the modal reads its members again after.
  final Future<void> Function(String handle) onInvite;

  /// Hands an invite link to the platform's share sheet ([InviteLinks.onSend]).
  final void Function(String title, String url)? onSendLink;

  /// The way chosen as it opens: Email, unless asked otherwise.
  final InviteWay way;
  final int Function()? now;

  @override
  State<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<InviteSheet> {
  late InviteWay _way = widget.way;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final simple = widget.services.prefs.value.simple;
    final wide = wideScreen(MediaQuery.sizeOf(context));
    final quiet = pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'));
    final title = 'Invite to ${widget.name}';
    final note = switch (_way) {
      InviteWay.email => 'We email them a link to join. It opens Ghost.md if they have it, or helps them get it first, and works once, for 14 days.',
      InviteWay.link => 'Anyone signed in who has the link can join as a member, until it stops or you turn it off. Send it however you like.',
      InviteWay.handle => 'They get an invitation in their notifications, with Accept and Decline, and join once they accept.',
    };
    final Widget panel = switch (_way) {
      InviteWay.email => InviteEmails(
          key: const ValueKey('invite-sheet:email'),
          services: widget.services,
          orgId: widget.orgId,
          now: widget.now,
          autoFocus: true,
          missing: Text('Email invitations aren’t on this service yet. Send an invite link instead.', style: quiet),
        ),
      InviteWay.link => InviteLinks(
          key: const ValueKey('invite-sheet:link'),
          services: widget.services,
          orgId: widget.orgId,
          now: widget.now,
          onSend: widget.onSendLink,
          missing: Text('Invite links aren’t on this service yet. Invite them by handle instead.', style: quiet),
        ),
      InviteWay.handle => InviteByHandle(key: const ValueKey('invite-sheet:handle'), autoFocus: true, onInvite: widget.onInvite),
    };
    return Sheet(
      key: const ValueKey('invite-sheet'),
      label: title,
      onClose: widget.onClose,
      centred: wide ? true : null,
      children: [
        SheetTitle.text(title),
        GlacierSegmentedControl(
          key: const ValueKey('invite-sheet-ways'),
          ariaLabel: 'How to invite',
          fullWidth: true,
          options: const [
            GlacierSegmentedOption(value: 'email', label: Text('Email')),
            GlacierSegmentedOption(value: 'link', label: Text('Link')),
            GlacierSegmentedOption(value: 'handle', label: Text('Handle')),
          ],
          value: _way.name,
          onValueChange: (value) => setState(() => _way = InviteWay.values.byName(value)),
        ),
        SizedBox(height: t.space(3)),
        if (!simple) ...[
          Text(note, key: const ValueKey('invite-sheet-note'), style: quiet),
          SizedBox(height: t.space(3)),
        ],
        panel,
        SizedBox(height: t.space(2)),
      ],
    );
  }
}

/// Invite by handle (the dashboard's `Invite`): a handle in, Invite, the service's answer under it in its own words.
/// They get an invitation in their notifications, and join once they accept.
class InviteByHandle extends StatefulWidget {
  const InviteByHandle({super.key, required this.onInvite, this.autoFocus = false});
  final Future<void> Function(String handle) onInvite;
  final bool autoFocus;

  @override
  State<InviteByHandle> createState() => _InviteByHandleState();
}

class _InviteByHandleState extends State<InviteByHandle> {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: GlacierInput(
                key: const ValueKey('invite-handle-field'),
                ariaLabel: 'Handle',
                placeholder: 'Handle',
                autoFocus: widget.autoFocus,
                autoCapitalize: TextCapitalization.none,
                autoCorrect: false,
                spellCheck: false,
                value: _handle,
                onChange: (text) => setState(() => _handle = text),
                onSubmitted: (_) => unawaited(_submit()),
              ),
            ),
            SizedBox(width: t.space(2)),
            OrgAction(key: const ValueKey('org-invite-submit'), label: _busy ? 'One moment…' : 'Invite', primary: true, dim: 0.6, onPressed: _busy || _handle.trim().isEmpty ? null : () => unawaited(_submit())),
          ],
        ),
        if (words != null) ...[
          SizedBox(height: t.space(2)),
          Semantics(liveRegion: true, child: Text(words, key: const ValueKey('invite-handle-said'), style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2')))),
        ],
      ],
    );
  }
}
