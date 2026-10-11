/// "Join it?" for an invite link that opened the app. A port of `src/app/notes/JoinSheet.tsx` (docs/TEAMS.md,
/// "Invite by link"; lib/orgs/join_links.dart): the organization's name, who made the link and how many are in it,
/// then Join or Not now. Nothing is joined until Join is pressed.
///
/// Signed out, the sheet says to sign in and the code waits on this device; once an account is signed in the sheet
/// asks again ([JoinInvites]). Not now, signed in, lets the code go; a link that has stopped working says so in the
/// service's words, and lets it go too.
///
/// What differs from the web original: the account and the organizations are the [AccountServices] it is handed,
/// and a code that waits is kept in their device's memory ([AccountServices.kept]); with none, the sheet is the
/// signed-out one.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../account/ui_state.dart';
import '../../notes/org_mark.dart';
import '../../sheet/kit.dart';
import '../../sheet/sheet.dart';
import '../join_links.dart';
import '../orgs.dart';
import 'parts.dart';

/// The join sheet (`JoinSheet`).
class JoinSheet extends StatefulWidget {
  const JoinSheet({super.key, required this.services, required this.code, required this.onClose, required this.onOpen, required this.onAccount});

  final AccountServices? services;
  final String code;

  /// Closed: `keep` when the code should wait for an account.
  final void Function({bool keep}) onClose;

  /// The organization's dashboard, once joined or already in.
  final ValueChanged<String> onOpen;

  /// Settings › Account, to sign in or sign up.
  final VoidCallback onAccount;

  @override
  State<JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<JoinSheet> {
  JoinPreview? _preview;
  String? _problem;
  bool _busy = false;
  String? _readFor;

  bool get _signedIn => widget.services?.signedIn ?? false;

  @override
  void initState() {
    super.initState();
    widget.services?.account.addListener(_look);
    _look();
  }

  @override
  void didUpdateWidget(JoinSheet old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code) _look();
  }

  @override
  void dispose() {
    widget.services?.account.removeListener(_look);
    super.dispose();
  }

  /// The link read again for each code, and once someone is signed in (`useEffect(…, [code, signedIn])`).
  void _look() {
    final key = '${widget.code}:$_signedIn';
    if (key == _readFor) return;
    _readFor = key;
    if (mounted) setState(() {});
    final orgs = widget.services?.orgs;
    if (!_signedIn || orgs == null) return;
    _preview = null;
    _problem = null;
    unawaited(() async {
      try {
        final read = await orgs.previewJoin(widget.code);
        if (mounted && key == _readFor) setState(() => _preview = read);
      } catch (failure) {
        if (mounted && key == _readFor) setState(() => _problem = accountFailureText(failure));
      }
    }());
  }

  Future<void> _join() async {
    final orgs = widget.services?.orgs;
    if (orgs == null) return;
    final close = widget.onClose, open = widget.onOpen;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final org = await orgs.joinByLink(widget.code);
      close();
      open(org.id);
    } catch (failure) {
      if (mounted) {
        setState(() {
          _problem = accountFailureText(failure);
          _busy = false;
        });
      }
    }
  }

  Widget _title(BuildContext context, String words) {
    final t = context.tokens;
    return SheetTitle(
      child: Text.rich(TextSpan(children: [OrgMark.span(em: t.fontSize('lg'), color: t.color('glacier-text')), TextSpan(text: words)])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final close = widget.onClose;
    if (!_signedIn) {
      return Sheet(
        label: 'Join a team',
        onClose: () => close(keep: true),
        children: [
          _title(context, 'Join a team'),
          const SheetNote('You opened an invite link. Sign in, or sign up, to see which organization it is for and join it. The link waits on this device until you do.'),
          SheetGroup(
            children: [
              SheetRow(
                label: 'Sign in or sign up',
                onPress: () {
                  close(keep: true);
                  widget.onAccount();
                },
              ),
              SheetRow(label: 'Not now', onPress: () => close(keep: true)),
            ],
          ),
        ],
      );
    }

    final preview = _preview;
    final problem = _problem;
    if (preview == null) {
      return Sheet(
        label: 'Invite link',
        onClose: close,
        children: [
          _title(context, problem != null ? 'This invite link doesn’t work' : 'Reading the invite link…'),
          if (problem != null) SheetNote(problem),
          SheetGroup(children: [SheetRow(label: 'Close', onPress: close)]),
        ],
      );
    }

    if (preview.member) {
      return Sheet(
        label: preview.name,
        onClose: close,
        children: [
          _title(context, 'You’re in ${preview.name}'),
          const SheetNote('You’re already a member, so the link has nothing to add.'),
          SheetGroup(
            children: [
              SheetRow(
                label: 'Open ${preview.name}',
                onPress: () {
                  close();
                  widget.onOpen(preview.orgId);
                },
              ),
              SheetRow(label: 'Close', onPress: close),
            ],
          ),
        ],
      );
    }

    final by = preview.by;
    return Sheet(
      label: 'Join ${preview.name}',
      onClose: close,
      children: [
        _title(context, 'Join ${preview.name}?'),
        SheetNote(
          '${by != null && by.isNotEmpty ? '$by shared this invite link. ' : ''}${memberWords(preview.members)} so far. You join as a member, and its workspace is made on each of your devices. Notes filed there are the team’s: everyone in it reads and edits them.',
        ),
        if (problem != null) SheetNote(problem),
        SheetGroup(
          children: [
            SheetRow(label: _busy ? 'Joining…' : 'Join ${preview.name}', disabled: _busy, onPress: () => unawaited(_join())),
            SheetRow(label: 'Not now', disabled: _busy, onPress: close),
          ],
        ),
      ],
    );
  }
}

/// A link that arrived (`request` of `JoinInvites`): its code, and a number that tells one arrival from the next.
@immutable
class JoinRequest {
  const JoinRequest(this.code, this.nonce);
  final String code;
  final int nonce;
}

/// Where an invite link lands in the app (`JoinInvites`): each one that arrives ([request]) is held on this device
/// and asked about, and a code held from before - followed signed out - is asked about as soon as an account is
/// signed in. [hold] keeps it back while the way into an account is up at launch (lib/shell/account_gate.dart).
class JoinInvites extends StatefulWidget {
  const JoinInvites({super.key, required this.services, required this.request, this.hold = false, required this.onOpen, required this.onAccount});

  final AccountServices? services;
  final JoinRequest? request;
  final bool hold;
  final ValueChanged<String> onOpen;
  final VoidCallback onAccount;

  @override
  State<JoinInvites> createState() => _JoinInvitesState();
}

class _JoinInvitesState extends State<JoinInvites> {
  String? _code;
  int? _accountId;

  @override
  void initState() {
    super.initState();
    widget.services?.account.addListener(_account);
    _arrived(widget.request);
    _account();
  }

  @override
  void didUpdateWidget(JoinInvites old) {
    super.didUpdateWidget(old);
    if (old.request?.nonce != widget.request?.nonce || old.request?.code != widget.request?.code) _arrived(widget.request);
  }

  @override
  void dispose() {
    widget.services?.account.removeListener(_account);
    super.dispose();
  }

  void _arrived(JoinRequest? request) {
    if (request == null) return;
    holdJoin(request.code, kept: widget.services?.kept);
    _code = request.code;
  }

  void _account() {
    final id = widget.services?.session?.accountId;
    if (id == _accountId) return;
    _accountId = id;
    if (id == null) return;
    final held = heldJoin(kept: widget.services?.kept);
    if (held != null && mounted) setState(() => _code = held);
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    if (code == null || widget.hold) return const SizedBox.shrink();
    return JoinSheet(
      services: widget.services,
      code: code,
      onClose: ({bool keep = false}) {
        if (!keep) dropHeldJoin(kept: widget.services?.kept);
        setState(() => _code = null);
      },
      onOpen: widget.onOpen,
      onAccount: widget.onAccount,
    );
  }
}
