import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../account/ui_state.dart';
import 'kit/settings_kit.dart';
import 'kit/settings_type.dart';

/// Port of `InviteActions` (src/app/settings/InviteActions.tsx, InviteActions.module.css): Accept and Decline,
/// inline, for an invitation to an organization. One pair of words, drawn wherever an invitation is - the row on
/// Settings › Organizations, the organization's own pages - so they cannot drift apart: Accept in ink at the
/// semibold weight, Decline in the second ink, both dim while the answer is on its way, and the service's words
/// under them if it did not arrive.
///
/// The answer is [AccountServices.answerInvite]: the feed's own, applied here at once, then a pass of the
/// notifications and the organizations. The words are shown only while the queue still holds this organization's
/// answer; [onAnswered] is told of a delivered one even when the pass took these words away with it.
///
/// What differs from the web original: the notifications drawer (lib/notes/notifications_drawer.dart) draws a pair
/// of its own, written before this one, and is handed the same [AccountServices.answerInvite].
class InviteActions extends StatefulWidget {
  const InviteActions({super.key, required this.services, required this.orgId, this.onAnswered});

  final AccountServices services;
  final String orgId;

  /// After the pass that delivered the answer: the page may want to move on (open the organization, say).
  final ValueChanged<bool>? onAnswered;

  @override
  State<InviteActions> createState() => _InviteActionsState();
}

class _InviteActionsState extends State<InviteActions> {
  bool _pending = false;
  String? _problem;

  Future<void> _answer(bool accept) async {
    // Read before the wait: the page hears of a delivered answer whether or not these words are still drawn.
    final answered = widget.onAnswered;
    setState(() {
      _pending = true;
      _problem = null;
    });
    final problem = await widget.services.answerInvite(widget.orgId, accept);
    if (mounted) {
      setState(() {
        _pending = false;
        _problem = problem;
      });
    }
    if (problem == null) answered?.call(accept);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final problem = _problem;
    Widget word(String words, bool accept) => SettingsWord(
          key: ValueKey(accept ? 'invite-accept' : 'invite-decline'),
          onPressed: _pending ? null : () => unawaited(_answer(accept)),
          color: _pending ? null : t.color(accept ? 'app-ink' : 'app-ink-2'),
          weight: accept ? 'semibold' : 'medium',
          child: Text(words),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // `.actions[data-pending] .words { opacity: 0.5 }`
        Opacity(
          opacity: _pending ? 0.5 : 1,
          child: DefaultTextStyle(
            style: pageText(t, t.lenOf('1rem')),
            child: Row(mainAxisSize: MainAxisSize.min, children: [word('Accept', true), SizedBox(width: t.space(3)), word('Decline', false)]),
          ),
        ),
        if (problem != null) ...[
          SizedBox(height: t.space(1)),
          Semantics(liveRegion: true, child: Text(problem, style: pageText(t, t.fontSize('sm'), height: t.len('glacier-leading-sm'), color: t.color('app-ink-2')))),
        ],
      ],
    );
  }
}
