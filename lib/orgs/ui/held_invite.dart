import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../core/stored.dart';
import '../../settings/account_forms.dart';
import '../../settings/kit/settings_kit.dart' show SettingsWord;
import '../../settings/kit/settings_type.dart';
import '../join_links.dart';

/// "Have an invite link?" on the way in (lib/shell/account_gate.dart; Matt, 2026-11-03: "email invites to join orgs
/// on ghost markdown so people can click a link download the app and be redirected on the app to join an org"). A
/// link followed before the app was installed cannot reach it - a download from the site carries nothing - so the
/// first screen offers to take it by hand: pasted here, the code is held on this device as a followed link's is
/// ([holdJoin]), and once an account is signed in or made, "Join it?" asks (lib/orgs/ui/join_sheet.dart
/// `JoinInvites`). Nothing is joined here.
///
/// Closed, it is one quiet word; open, a field and Keep it. Any shape a link arrives in is read ([readJoinLink]): the
/// emailed one, the reader page's, the app's own, or the code alone.
class HeldInviteField extends StatefulWidget {
  const HeldInviteField({super.key, this.kept, this.now});

  /// This device's memory; the app's own when left out.
  final Stored? kept;

  /// This moment, in ms, for the hold's week.
  final int Function()? now;

  @override
  State<HeldInviteField> createState() => _HeldInviteFieldState();
}

class _HeldInviteFieldState extends State<HeldInviteField> {
  bool _open = false;
  String _text = '';
  String? _said;

  @override
  void initState() {
    super.initState();
    // A link followed before (or pasted on an earlier open) is held already: said, so it is not asked for twice.
    if (heldJoin(now: widget.now?.call(), kept: widget.kept) != null) {
      _open = true;
      _said = _heldWords;
    }
  }

  static const String _heldWords = 'Invitation kept. Sign in or sign up, and Ghost.md asks you to join.';

  void _keep() {
    final code = readJoinLink(_text);
    if (code == null) {
      setState(() => _said = 'That isn’t an invite link. Paste the whole link from the invitation.');
      return;
    }
    holdJoin(code, now: widget.now?.call(), kept: widget.kept);
    setState(() {
      _text = '';
      _said = _heldWords;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (!_open) {
      return Align(
        child: DefaultTextStyle(
          style: pageText(t, t.fontSize('sm')),
          child: SettingsWord(
            key: const ValueKey('held-invite-open'),
            color: t.color('glacier-text-subtle'),
            onPressed: () => setState(() => _open = true),
            child: const Text('Have an invite link?'),
          ),
        ),
      );
    }
    final said = _said;
    return Semantics(
      container: true,
      label: 'Invite link',
      child: SettingsForm(
        bare: true,
        children: [
          Text('Paste the link from your invitation. Ghost.md keeps it and asks you to join once you’re signed in.', style: pageText(t, t.fontSize('sm'), color: t.color('glacier-text-subtle'))),
          GlacierInput(
            key: const ValueKey('held-invite-field'),
            ariaLabel: 'Invite link',
            placeholder: 'https://ghostmarkdown.com/join#…',
            type: GlacierInputType.url,
            autoCapitalize: TextCapitalization.none,
            autoCorrect: false,
            spellCheck: false,
            value: _text,
            onChange: (text) => setState(() => _text = text),
            onSubmitted: (_) => _keep(),
          ),
          if (said != null) FormProblem(said, key: const ValueKey('held-invite-said')),
          FormSubmit(wordKey: const ValueKey('held-invite-keep'), 'Keep it', stretch: true, onPressed: _text.trim().isEmpty ? null : _keep),
        ],
      ),
    );
  }
}
