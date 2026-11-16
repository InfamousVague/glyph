import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../friends/buddies.dart';
import '../kit/settings_type.dart';
import '../sms.dart';
import '../voice/channels.dart';
import '../voice/voice.dart';
import 'add_friend_drawer.dart';
import 'common.dart';
import 'ripple_avatar.dart';
import 'shell.dart';
import 'voice_screen.dart';

/// The words an invite to [c] goes with, by a text or the share sheet.
String spaceInviteWords(VoiceChannel c) => 'Join me in ${c.name} on Ghost Messaging: ${c.link}';

/// Inviting people into a space, from wherever invite is offered (Matt, 2026-11-16: "make a way to invite friends from
/// the app into spaces and invite people into spaces through the app"): friends on Ghost Messaging, chosen and sent the
/// space at once (Voice.share: it shows on their phone as an invite), and anyone else by a text already written, the
/// link copied, or the system's share sheet.
///
/// [send], [compose], [buddies] and [inSpace] (who is in it, by id) are for a test; the app's own otherwise ([compose]
/// opens a new text with the words written, through the phone on a computer, or the share sheet where there is no
/// shell). A group's channel is its members' alone: nothing is raised for one.
Future<void> showSpaceInvite(
  BuildContext context,
  VoiceChannel channel, {
  Future<List<Buddy>> Function(VoiceChannel channel, List<Buddy> friends)? send,
  void Function(String words)? compose,
  Buddies? buddies,
  Set<String>? inSpace,
}) {
  if (channel.group != null) return Future.value();
  // The shell stands under the outermost navigator the sheet is raised on: found here, before.
  final shell = AppShell.maybeOf(context);
  final write = compose ?? (shell == null ? (String words) => unawaited(Sms.instance.shareText(channel.name, words)) : (String words) => shell.compose(body: words));
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: const Color(0x66000000),
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => SpaceInviteSheet(channel: channel, send: send ?? Voice.instance.share, compose: write, buddies: buddies ?? Buddies.instance, inSpace: inSpace),
    transitionsBuilder: (context, a, _, child) => SlideTransition(
      position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ));
}

/// The invite sheet itself: friends to choose and Send invites, then the ways to reach anyone else.
class SpaceInviteSheet extends StatefulWidget {
  const SpaceInviteSheet({super.key, required this.channel, required this.send, required this.compose, required this.buddies, this.inSpace});
  final VoiceChannel channel;

  /// Who is in the space, by id, where not as Voice says (a test).
  final Set<String>? inSpace;
  /// Sends the space to the friends chosen; gives back those it could not reach.
  final Future<List<Buddy>> Function(VoiceChannel channel, List<Buddy> friends) send;
  final void Function(String words) compose;
  final Buddies buddies;

  @override
  State<SpaceInviteSheet> createState() => _SpaceInviteSheetState();
}

class _SpaceInviteSheetState extends State<SpaceInviteSheet> {
  final Set<String> _chosen = {};
  bool _sending = false;

  /// Who is in the space now, by id: in the call here, or as the hub says.
  Set<String> get _inSpace {
    if (widget.inSpace != null) return widget.inSpace!;
    final v = Voice.instance;
    final s = v.session;
    if (s != null && s.channel.room == widget.channel.room) return s.members.keys.toSet();
    return v.inChannel(widget.channel).toSet();
  }

  Future<void> _send(List<Buddy> friends) async {
    final chosen = [for (final f in friends) if (_chosen.contains(f.id)) f];
    if (chosen.isEmpty || _sending) return;
    setState(() => _sending = true);
    final nav = Navigator.of(context);
    final shown = context;
    try {
      final missed = await widget.send(widget.channel, chosen);
      if (!shown.mounted) return;
      final reached = [for (final f in chosen) if (!missed.any((m) => m.id == f.id)) f];
      final away = missed.map((f) => f.shown).join(', ');
      if (reached.isEmpty) {
        toast(shown, 'Couldn\'t reach $away. Try again in a moment, or text them an invite.', tone: GlacierToastTone.danger);
        setState(() => _sending = false);
        return;
      }
      final invited = reached.length == 1 ? 'Invited ${reached.first.shown}' : 'Invited ${reached.length}';
      toast(shown, missed.isEmpty ? invited : '$invited; couldn\'t reach $away', tone: missed.isEmpty ? GlacierToastTone.neutral : GlacierToastTone.warning);
      nav.pop();
    } catch (e) {
      if (shown.mounted) toast(shown, 'Couldn\'t send the invites: $e', tone: GlacierToastTone.danger);
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    final c = widget.channel;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {},
          child: Padding(
            padding: EdgeInsets.fromLTRB(t.space(3), 0, t.space(3), pad.bottom + t.space(3)),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: t.lenOf('30rem'), maxHeight: MediaQuery.sizeOf(context).height - pad.top - pad.bottom - t.space(8)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(t.radius('xl')),
                child: ColoredBox(
                  color: t.color('app-paper-2'),
                  child: ListenableBuilder(
                    listenable: Listenable.merge([widget.buddies, Voice.instance]),
                    builder: (context, _) {
                      final friends = widget.buddies.friends;
                      final here = _inSpace;
                      final n = _chosen.length;
                      return SingleChildScrollView(
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(t.space(4), t.space(4), t.space(4), t.space(1)),
                            child: Text('Invite to ${c.name}', maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('lg'), weight: 'bold', color: t.color('app-ink'))),
                          ),
                          _Heading('Friends on Ghost Messaging'),
                          if (friends.isEmpty) ...[
                            Padding(
                              padding: EdgeInsets.fromLTRB(t.space(4), 0, t.space(4), t.space(1)),
                              child: Text('No friends here yet. Add someone by their username and you can invite them in one press.', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'), height: 1.4)),
                            ),
                            _Row(
                              icon: Lucide.userPlus,
                              label: 'Add a friend',
                              onPress: () {
                                final root = Navigator.of(context, rootNavigator: true).context;
                                Navigator.of(context).pop();
                                unawaited(showAddFriendDrawer(root));
                              },
                            ),
                          ] else ...[
                            for (final f in friends) _FriendRow(friend: f, inSpace: here.contains(f.id), chosen: _chosen.contains(f.id), onPress: () => setState(() => _chosen.contains(f.id) ? _chosen.remove(f.id) : _chosen.add(f.id))),
                            Padding(
                              padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(1)),
                              child: GlacierPressable(
                                onPressed: n == 0 || _sending ? null : () => _send(friends),
                                semanticLabel: n == 1 ? 'Send invite' : 'Send invites',
                                builder: (context, state) => Opacity(
                                  opacity: n == 0 ? 0.4 : 1,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(vertical: t.space(3)),
                                    decoration: BoxDecoration(color: t.color(state.pressed ? 'app-ink-2' : 'app-ink'), borderRadius: BorderRadius.circular(t.radius('full'))),
                                    alignment: Alignment.center,
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      AppIcon(Lucide.send, size: 16, wash: false, color: t.color('app-paper')),
                                      SizedBox(width: t.space(2)),
                                      Text(n == 0 ? 'Send invites' : n == 1 ? 'Send invite' : 'Send $n invites', style: pageText(t, t.fontSize('md'), weight: 'bold', color: t.color('app-paper'))),
                                    ]),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          SizedBox(height: t.space(2)),
                          Container(height: t.len('glacier-hairline'), color: t.color('app-rule')),
                          _Heading('Anyone else'),
                          _Row(
                            icon: Lucide.messageSquare,
                            label: 'Text an invite',
                            hint: 'To anyone in your contacts, by text',
                            onPress: () {
                              Navigator.of(context).pop();
                              widget.compose(spaceInviteWords(c));
                            },
                          ),
                          _Row(
                            icon: Lucide.link,
                            label: 'Copy invite link',
                            hint: 'Anyone with it can join, from the app or a browser',
                            onPress: () {
                              final root = Navigator.of(context, rootNavigator: true).context;
                              Navigator.of(context).pop();
                              copyInvite(root, c);
                            },
                          ),
                          _Row(
                            icon: Lucide.share2,
                            label: 'Share link…',
                            hint: 'Send it with another app',
                            onPress: () {
                              Navigator.of(context).pop();
                              unawaited(Sms.instance.shareText(c.name, spaceInviteWords(c)).catchError((_) {}));
                            },
                          ),
                          SizedBox(height: t.space(2)),
                        ]),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small heading over a part of the sheet.
class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(4), t.space(1)),
      child: Text(text, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink-3'))),
    );
  }
}

/// A friend to invite: their face, name and @username, and a check while chosen. One already in the space says so.
class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.friend, required this.inSpace, required this.chosen, required this.onPress});
  final Buddy friend;
  final bool inSpace, chosen;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.lenOf('1.5rem');
    return GlacierPressable(
      onPressed: inSpace ? null : onPress,
      semanticLabel: inSpace ? '${friend.shown}, in the space' : '${friend.shown}${chosen ? ', chosen' : ''}',
      builder: (context, state) => ColoredBox(
        color: state.pressed ? t.color('app-paper-3') : const Color(0x00000000),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
          child: Row(children: [
            RippleAvatar(name: friend.shown, level: 0, size: 40),
            SizedBox(width: t.space(3)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(friend.shown, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink'))),
                if (friend.name.isNotEmpty) Text('@${friend.username}', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
              ]),
            ),
            SizedBox(width: t.space(2)),
            if (inSpace)
              Text('In the space', style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.colorOf('#2fb35a')))
            else
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: chosen ? t.color('app-ink') : const Color(0x00000000),
                  border: Border.all(color: t.color(chosen ? 'app-ink' : 'app-ink-3'), width: 2),
                ),
                alignment: Alignment.center,
                child: chosen ? AppIcon(Lucide.check, size: 14, strokeWidth: 3, wash: false, color: t.color('app-paper')) : null,
              ),
          ]),
        ),
      ),
    );
  }
}

/// One of the ways to reach anyone else: an icon, what it does, and a line under it.
class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, this.hint, required this.onPress});
  final LucideIcon icon;
  final String label;
  final String? hint;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPress,
      semanticLabel: label,
      builder: (context, state) => ColoredBox(
        color: state.pressed ? t.color('app-paper-3') : const Color(0x00000000),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(3)),
          child: Row(children: [
            AppIcon(icon, size: 20, color: t.color('app-ink')),
            SizedBox(width: t.space(3)),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: pageText(t, t.fontSize('md'), weight: 'medium', color: t.color('app-ink'))),
                if (hint != null) Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
