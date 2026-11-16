import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../friends/buddies.dart';
import '../kit/settings_type.dart';
import '../me/me.dart';
import '../sms.dart';
import 'common.dart';
import 'profile.dart';

/// Friends by username at the top of Contacts (Matt, 2026-11-16: "We need a way to add friends on the network by
/// username on the contacts page and see friend requests"): a field to ask someone by their @username, the requests
/// waiting for an answer with Accept and Decline on each, the ones you sent, and the friends you have. Without a
/// username of your own it says to choose one first. Buddies (lib/friends/buddies.dart) does the asking.
class UsernameFriends extends StatefulWidget {
  const UsernameFriends({super.key, this.buddies, this.me});

  /// For a test or a picture; the app's own otherwise.
  final Buddies? buddies;
  final Me? me;

  @override
  State<UsernameFriends> createState() => _UsernameFriendsState();
}

class _UsernameFriendsState extends State<UsernameFriends> {
  final _who = TextEditingController();
  String? _problem;
  bool _busy = false;

  Buddies get _buddies => widget.buddies ?? Buddies.instance;
  Me get _me => widget.me ?? Me.instance;

  @override
  void dispose() {
    _who.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = tidyHandle(_who.text);
    if (!Me.goodUsername(name)) {
      setState(() => _problem = 'Type their username, like @maya.');
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final b = await _buddies.add(name);
      _who.clear();
      if (mounted) toast(context, b.state == 'yes' ? 'You and @$name are friends' : 'Friend request sent to @$name');
    } catch (e) {
      if (mounted) setState(() => _problem = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: Listenable.merge([_buddies, _me]),
      builder: (context, _) {
        final b = _buddies;
        Widget heading(String words) => Padding(
              padding: EdgeInsets.fromLTRB(t.space(4), t.space(4), t.space(4), t.space(1)),
              child: Text(words, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-3'))),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          if (_me.username == null)
            _Row(
              icon: Lucide.atSign,
              title: 'Add friends by username',
              sub: 'Choose a username first, so friends know it\'s you',
              onPress: () => push(context, (_) => const ProfileScreen()),
            )
          else
            Padding(
              padding: EdgeInsets.fromLTRB(t.space(4), t.space(1), t.space(4), t.space(1)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: GlacierInput(
                      key: const ValueKey('add-friend-field'),
                      controller: _who,
                      placeholder: 'Add a friend by @username',
                      ariaLabel: 'Their username',
                      autoCorrect: false,
                      autoCapitalize: TextCapitalization.none,
                      size: GlacierFieldSize.md,
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                  SizedBox(width: t.space(2)),
                  _Pill(key: const ValueKey('add-friend'), label: _busy ? 'Asking…' : 'Add', icon: Lucide.userPlus, filled: true, onPress: _busy ? null : _add),
                ]),
                if (_problem != null)
                  Padding(
                    padding: EdgeInsets.only(top: t.space(1) + 2, left: t.space(1)),
                    child: Text(_problem!, style: pageText(t, t.fontSize('sm'), color: t.colorOf('#dd3a30'))),
                  ),
              ]),
            ),
          // Who asked: an answer on each, right there.
          if (b.requests.isNotEmpty) ...[
            heading(b.requests.length == 1 ? 'Friend request' : 'Friend requests · ${b.requests.length}'),
            for (final r in b.requests)
              _Row(
                key: ValueKey('request-${r.username}'),
                name: r.shown,
                title: r.shown,
                sub: r.name.isEmpty ? (r.bio.isEmpty ? 'Wants to be friends' : r.bio) : '@${r.username}${r.bio.isEmpty ? '' : ' · ${r.bio}'}',
                trailing: Row(mainAxisSize: MainAxisSize.min, spacing: t.space(2), children: [
                  _Pill(key: ValueKey('decline-${r.username}'), label: 'Decline', onPress: () => b.decline(r)),
                  _Pill(key: ValueKey('accept-${r.username}'), label: 'Accept', filled: true, onPress: () => b.accept(r)),
                ]),
              ),
          ],
          if (b.friends.isNotEmpty) ...[
            heading('Friends by username'),
            for (final f in b.friends)
              _Row(
                name: f.shown,
                title: f.shown,
                sub: f.name.isEmpty ? (f.bio.isEmpty ? 'Friends' : f.bio) : '@${f.username}${f.bio.isEmpty ? '' : ' · ${f.bio}'}',
                onPress: () => showChoices(context, title: f.shown, choices: [
                  Choice('Remove friend', Lucide.userX, () => b.remove(f), danger: true),
                ]),
              ),
          ],
          // The ones sent: a press takes one back.
          if (b.asked.isNotEmpty) ...[
            heading('Waiting for them'),
            for (final a in b.asked)
              _Row(
                icon: Lucide.clock,
                title: '@${a.username}',
                sub: 'Friend request sent',
                onPress: () => showChoices(context, title: 'Take back your request to @${a.username}?', choices: [
                  Choice('Take it back', Lucide.x, () => b.remove(a), danger: true),
                ]),
              ),
          ],
        ]);
      },
    );
  }
}

/// A line as the Contacts list draws its people: a face (or a mark), a name and a line under it, and what goes at the
/// end.
class _Row extends StatelessWidget {
  const _Row({super.key, required this.title, required this.sub, this.name, this.icon, this.onPress, this.trailing});
  final String title;
  final String sub;

  /// Whose initials the face shows; [icon] stands in where there is nobody.
  final String? name;
  final LucideIcon? icon;
  final VoidCallback? onPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final face = name != null
        ? Avatar(people: [Person(address: '@$name', name: name)], size: t.lenOf('2.5rem'))
        : Container(
            width: t.lenOf('2.5rem'),
            height: t.lenOf('2.5rem'),
            decoration: BoxDecoration(shape: BoxShape.circle, color: t.color('app-paper-3')),
            child: Center(child: AppIcon(icon ?? Lucide.userPlus, size: 18, color: t.color('app-ink'))),
          );
    final body = Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2) + 2),
      child: Row(children: [
        face,
        SizedBox(width: t.space(3)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'medium')),
            Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
          ]),
        ),
        if (trailing != null) ...[SizedBox(width: t.space(2)), trailing!],
      ]),
    );
    if (onPress == null) return body;
    return GlacierPressable(
      onPressed: onPress,
      semanticLabel: '$title, $sub',
      builder: (context, state) => ColoredBox(color: state.pressed || state.hovered ? t.color('app-paper-2') : const Color(0x00000000), child: body),
    );
  }
}

/// A small capsule: Accept (filled, the page's ink) or Decline (a ring).
class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.label, required this.onPress, this.filled = false, this.icon});
  final String label;
  final VoidCallback? onPress;
  final bool filled;
  final LucideIcon? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = filled ? t.color('app-paper') : t.color('app-ink');
    return GlacierPressable(
      onPressed: onPress,
      semanticLabel: label,
      builder: (context, state) => AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: onPress == null ? 0.5 : (state.pressed ? 0.8 : 1),
        child: Container(
          height: t.lenOf('2.1rem'),
          padding: EdgeInsets.symmetric(horizontal: t.space(3)),
          decoration: ShapeDecoration(
            color: filled ? t.color('app-ink') : const Color(0x00000000),
            shape: StadiumBorder(side: filled ? BorderSide.none : BorderSide(color: t.color('app-rule'))),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[AppIcon(icon!, size: 14, strokeWidth: 2.3, wash: false, color: ink), SizedBox(width: t.space(1))],
            Text(label, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: ink)),
          ]),
        ),
      ),
    );
  }
}
