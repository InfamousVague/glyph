import 'dart:async';

import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../account/not_yet.dart';
import '../account/ui_state.dart';
import '../art/art.dart';
import '../orgs/join_links.dart';
import '../orgs/orgs.dart';
import '../orgs/ui/parts.dart';
import '../sheet/css.dart' show snapBorder;
import 'kit/settings_type.dart';

/// Invite by email, for the owner and admins (Matt, 2026-11-03: "I'd like you to update our app so we can email
/// invites to join orgs on ghost markdown so people can click a link download the app and be redirected on the app to
/// join an org"; docs/TEAMS.md, "Invite by email"; server/src/orgs.rs). An address and Send: the service mails a link
/// of one use that lasts a fortnight, `https://ghostmarkdown.com/join#<code>`, which opens the app where it is
/// installed and helps get it where it is not. The invitations waiting are listed under the field, each to send again
/// or turn off. Shown beside [InviteLinks] on the organization's Members page (organization_sheet.dart) and under its
/// dashboard's invite field (lib/orgs/ui/organization_screen.dart), in Simple mode too: it is the plain way in.
///
/// The service's refusals - too many in an hour, an address that will not do, mail that could not be sent - are said
/// under the field in its own words. Where the service has no email invitations yet (`notYet`) nothing is drawn, the
/// heading [around] would have put over the panel included; where it has them but sends no mail, the panel says so in
/// place of the field.
class InviteEmails extends StatefulWidget {
  const InviteEmails({super.key, required this.services, required this.orgId, this.inset = false, this.around, this.now, this.missing, this.autoFocus = false});

  final AccountServices services;
  final String orgId;

  /// Inside a settings card, which pads its forms rather than its contents: padded as they are.
  final bool inset;

  /// The heading the panel sits under, drawn by the page around it and gone with it.
  final Widget Function(Widget panel)? around;

  /// This moment, in ms, for "Sent 2 hours ago"; the clock's when left out.
  final int Function()? now;

  /// What is drawn where the service has no email invitations yet, in place of nothing: the invite modal's Email tab
  /// (lib/orgs/ui/invite_sheet.dart), which would otherwise stand empty.
  final Widget? missing;

  /// The address field takes the focus as it is drawn: the invite modal opens on it.
  final bool autoFocus;

  @override
  State<InviteEmails> createState() => _InviteEmailsState();
}

class _InviteEmailsState extends State<InviteEmails> {
  List<EmailInvite>? _invites;
  bool _missing = false;
  bool _mail = true;
  String _address = '';
  bool _busy = false;
  ({String words, bool problem})? _said;

  Orgs? get _orgs => widget.services.orgs;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void didUpdateWidget(InviteEmails old) {
    super.didUpdateWidget(old);
    if (old.orgId != widget.orgId) {
      _invites = null;
      unawaited(_read());
    }
  }

  Future<void> _read() async {
    final orgs = _orgs;
    if (orgs == null) return setState(() => _missing = true);
    try {
      final answer = await orgs.listEmailInvites(widget.orgId);
      if (mounted) {
        setState(() {
          _invites = answer.invites;
          _mail = answer.mail;
        });
      }
    } catch (failure) {
      if (!mounted) return;
      if (notYet(failure)) return setState(() => _missing = true);
      setState(() {
        _invites = const [];
        _said = (words: accountFailureText(failure), problem: true);
      });
    }
  }

  void _say(Object failure) {
    if (!mounted) return;
    // The service sends no mail after all (a 503): the field goes, and the panel says why.
    if (failure is Refusal && failure.status == 503) {
      setState(() {
        _mail = false;
        _said = null;
      });
      return;
    }
    setState(() => _said = (words: accountFailureText(failure), problem: true));
  }

  Future<void> _send() async {
    final orgs = _orgs;
    final address = _address.trim();
    if (orgs == null || address.isEmpty || _busy) return;
    if (!looksLikeEmail(address)) {
      setState(() => _said = (words: 'That doesn’t look like an email address.', problem: true));
      return;
    }
    setState(() {
      _busy = true;
      _said = null;
    });
    try {
      final invite = await orgs.inviteByEmail(widget.orgId, address);
      if (mounted) {
        setState(() {
          _invites = [invite, for (final each in _invites ?? const <EmailInvite>[]) if (each.id != invite.id) each];
          _address = '';
          _said = (words: 'Invitation sent to ${invite.email}. The link in it works once, for 14 days.', problem: false);
        });
      }
    } catch (failure) {
      _say(failure);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _resend(EmailInvite invite) async {
    final orgs = _orgs;
    if (orgs == null || _busy) return;
    setState(() {
      _busy = true;
      _said = null;
    });
    try {
      final sent = await orgs.resendEmailInvite(widget.orgId, invite.id);
      if (mounted) {
        setState(() {
          _invites = [for (final each in _invites ?? const <EmailInvite>[]) each.id == sent.id ? sent : each];
          _said = (words: 'Sent again to ${sent.email}.', problem: false);
        });
      }
    } catch (failure) {
      _say(failure);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _revoke(EmailInvite invite) async {
    final orgs = _orgs;
    if (orgs == null) return;
    setState(() => _said = null);
    try {
      await orgs.dropEmailInvite(widget.orgId, invite.id);
      if (!mounted) return;
      setState(() {
        _invites = [for (final each in _invites ?? const <EmailInvite>[]) if (each.id != invite.id) each];
        _said = (words: 'The invitation to ${invite.email} is turned off. Its link no longer works.', problem: false);
      });
    } catch (failure) {
      _say(failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_missing) return widget.missing ?? const SizedBox.shrink();
    final t = context.tokens;
    final sm = t.fontSize('sm'), xs = t.fontSize('xs');
    final quiet = pageText(t, sm, color: t.color('app-ink-2'));
    final invites = _invites;
    final said = _said;
    final now = (widget.now ?? widget.services.now)();

    Widget icon(LucideIcon mark, String label, VoidCallback? onPressed) => GlacierPressable(
          onPressed: onPressed,
          semanticLabel: label,
          builder: (context, state) => GlacierFocusRing(
            visible: state.focused,
            radius: t.radius('full'),
            child: Container(
              width: t.lenOf('2.25rem'),
              height: t.lenOf('2.25rem'),
              decoration: BoxDecoration(shape: BoxShape.circle, color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 7%, transparent)') : null),
              alignment: Alignment.center,
              child: AppIcon(mark, size: 16, color: state.hovered ? t.color('app-ink') : t.color('app-ink-2')),
            ),
          ),
        );

    final parts = <Widget>[
      if (!_mail)
        Text('Email invitations aren’t set up on this service yet. Send an invite link instead.', style: quiet)
      else
        Row(
          children: [
            Expanded(
              child: GlacierInput(
                key: const ValueKey('invite-email-field'),
                ariaLabel: 'Email address',
                placeholder: 'name@example.com',
                type: GlacierInputType.email,
                autoFocus: widget.autoFocus,
                autoCapitalize: TextCapitalization.none,
                autoCorrect: false,
                spellCheck: false,
                value: _address,
                onChange: (text) => setState(() => _address = text),
                onSubmitted: (_) => unawaited(_send()),
              ),
            ),
            SizedBox(width: t.space(2)),
            OrgAction(
              key: const ValueKey('invite-email-send'),
              label: _busy ? 'One moment…' : 'Send',
              icon: const AppIcon(Lucide.send, size: 14),
              primary: true,
              dim: 0.6,
              onPressed: _busy || _address.trim().isEmpty ? null : () => unawaited(_send()),
            ),
          ],
        ),
      if (invites == null)
        Text('Reading the invitations…', style: quiet)
      else if (invites.isNotEmpty)
        Semantics(
          label: 'Email invitations waiting',
          container: true,
          explicitChildNodes: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final invite in invites)
                Container(
                  key: ValueKey('invite-email:${invite.id}'),
                  padding: EdgeInsets.symmetric(vertical: t.space(2)),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.color('app-rule'), width: snapBorder(context, t.len('glacier-hairline'))))),
                  child: Row(
                    children: [
                      ExcludeSemantics(child: AppIcon(Lucide.mail, size: 16, color: t.color('app-ink-3'))),
                      SizedBox(width: t.space(2)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(invite.email, style: pageText(t, sm, weight: 'medium', color: t.color('app-ink')), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 0.1 * 16),
                            Text(emailTermsWords(invite, now), style: pageText(t, xs, color: t.color('app-ink-3')), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      SizedBox(width: t.space(2)),
                      if (_mail) ...[
                        icon(Lucide.refreshCw, 'Send the invitation to ${invite.email} again', _busy ? null : () => unawaited(_resend(invite))),
                        SizedBox(width: t.space(2)),
                      ],
                      icon(Lucide.x, 'Turn off the invitation to ${invite.email}', () => unawaited(_revoke(invite))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      if (said != null) Semantics(liveRegion: true, child: Text(said.words, key: const ValueKey('invite-email-said'), style: quiet)),
    ];

    final panel = Padding(
      padding: EdgeInsets.all(widget.inset ? t.space(3) : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) SizedBox(height: t.space(2)),
            parts[i],
          ],
        ],
      ),
    );
    return widget.around?.call(panel) ?? panel;
  }
}
