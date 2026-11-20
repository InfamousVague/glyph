import 'dart:async';
import 'composer_box.dart' show ComposerBox, ComposerField;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../friends/buddies.dart';
import '../inbox/inbox.dart';
import '../kit/settings_type.dart';
import '../me/me.dart';
import '../mentions.dart';
import '../me/pictures.dart';
import '../net/net.dart';
import '../sms.dart';
import '../standalone/chats.dart' show UsernameChats;
import '../voice/hangout.dart';
import 'common.dart';
import 'inbox_ui.dart' show openInboxChat, inboxMark;
import 'profile.dart';
import 'shell.dart';
import 'thread.dart';
import 'special_badges.dart';
import 'verified_badge.dart';

/// Who a profile card is about (Matt, 2026-11-19: "when clicking on a @mention anywhere including signal and telegram
/// chats show this profile popup with actions available for the user in context of where it's placed"): someone on
/// Ghost, by their id on the hub or their username, or someone on another network ([network]), by its own id or
/// username. [room] is the space it was opened in, for what makes sense there.
class ProfileSubject {
  const ProfileSubject.ghost({this.id = '', this.username = '', this.name = '', this.room, this.onMention, this.detail = ''}) : network = null;
  const ProfileSubject.on(InboxNetwork this.network, {this.id = '', this.username = '', this.name = '', this.onMention, this.detail = ''}) : room = null;

  final InboxNetwork? network;
  final String id;
  final String username;
  final String name;
  final HangoutRoom? room;

  /// Puts an "@Name" for them in the composer where the card was opened from, where that can be done.
  final VoidCallback? onMention;

  /// A line of what they are where the card was opened ("Admin · On now" in a circle's members).
  final String detail;
}

/// A mention's [id] as the message lines carry it, made a subject: a Ghost id in a space ([room]), `u:<name>` for a
/// username written in the words, `n:<id>` for someone a network named.
ProfileSubject subjectOfMention(String id, {String words = '', InboxNetwork? network, HangoutRoom? room, VoidCallback? onMention}) {
  final name = words.startsWith('@') ? words.substring(1) : words;
  if (network != null) {
    if (id.startsWith('n:')) return ProfileSubject.on(network, id: id.substring(2), name: name, onMention: onMention);
    return ProfileSubject.on(network, username: id.startsWith('u:') ? id.substring(2) : name, name: name, onMention: onMention);
  }
  if (id.startsWith('u:')) return ProfileSubject.ghost(username: id.substring(2), name: name, room: room, onMention: onMention);
  return ProfileSubject.ghost(id: id, name: name, room: room, onMention: onMention);
}

/// Opens [who]'s profile: their picture, name, username, status and line, what can be done with them from here, and
/// for someone on Ghost a small field to write to them straight away.
Future<void> showProfile(BuildContext context, ProfileSubject who, {List<Choice> more = const []}) {
  final ghost = who.network == null ? _ghostOf(who) : null;
  final choices = <Choice>[
    if (who.onMention != null) Choice('Mention ${_nameOf(who, ghost)}', Lucide.atSign, who.onMention!),
    ..._actions(context, who, ghost),
    ...more,
  ];
  return showChoices(context, header: _ProfileCard(who: who, ghost: ghost), choices: choices);
}

/// What is known here of someone on Ghost: a friend's own profile, else what they said in the space, else their
/// username alone.
class _Ghost {
  _Ghost({required this.id, required this.username, required this.name, this.buddy, this.status = '', this.pictureHash = '', this.me = false});
  final String id;
  final String username;
  final String name;
  final Buddy? buddy;
  final String status;
  final String pictureHash;
  final bool me;

  bool get friend => buddy?.state == 'yes';
}

_Ghost _ghostOf(ProfileSubject who) {
  final buddies = Buddies.instance;
  final user = who.username.startsWith('@') ? who.username.substring(1) : who.username;
  final buddy = (who.id.isNotEmpty ? buddies.byId(who.id) : null) ?? (user.isNotEmpty ? buddies.all.where((b) => b.username == tidyHandle(user)).firstOrNull : null);
  final here = who.id.isNotEmpty ? who.room?.present[who.id] : null;
  final myName = Me.instance.username;
  final me = (who.id.isNotEmpty && (who.id == Net.instance.id || who.id == who.room?.me)) || (user.isNotEmpty && myName != null && tidyHandle(user) == myName);
  return _Ghost(
    id: who.id.isNotEmpty ? who.id : (buddy?.id ?? ''),
    username: buddy?.username ?? here?.username ?? (me ? (myName ?? '') : tidyHandle(user)),
    name: me ? Me.instance.shownName : (buddy?.shown ?? (here?.name.isNotEmpty == true ? here!.name : who.name)),
    buddy: buddy,
    status: me ? Me.instance.status : (buddy?.status.isNotEmpty == true ? buddy!.status : (here?.status ?? '')),
    pictureHash: here?.pictureHash ?? '',
    me: me,
  );
}

String _nameOf(ProfileSubject who, _Ghost? g) => (g?.name.isNotEmpty == true ? g!.name : (who.name.isNotEmpty ? who.name : (who.username.isNotEmpty ? who.username : 'them')));

/// What can be done with [who] from here, under the card.
List<Choice> _actions(BuildContext context, ProfileSubject who, _Ghost? g) {
  final network = who.network;
  if (network != null) {
    final handle = who.username;
    return [
      Choice('Message on ${network.name}', Lucide.messageSquare, () => unawaited(_openNetworkChat(context, who)), mark: inboxMark(network, size: 20)),
      if (handle.isNotEmpty) Choice('Copy @$handle', Lucide.copy, () => _copy(context, '@$handle')),
    ];
  }
  final ghost = g!;
  if (ghost.me) {
    return [Choice('Edit your profile', Lucide.pencil, () => push<void>(context, (_) => const ProfileScreen()))];
  }
  final links = ghost.buddy?.links ?? const <String, String>{};
  final phone = links['phone'];
  return [
    if (ghost.friend) Choice('Open chat', Lucide.messageSquare, () => unawaited(_openGhostChat(context, ghost))),
    if (phone != null && phone.isNotEmpty) Choice('Text $phone', Lucide.messageSquare, () => unawaited(_openNumber(context, phone, ghost.name)), hint: 'Their number, as they shared it'),
    for (final e in links.entries)
      if (e.key != 'phone' && Inbox.instance.named(e.key)?.state == InboxState.ready)
        Choice('Message on ${Inbox.instance.named(e.key)!.name}', Lucide.messageSquare, () => unawaited(_openNetworkChat(context, ProfileSubject.on(Inbox.instance.named(e.key)!, username: e.value.replaceFirst('@', ''), name: ghost.name))),
            mark: inboxMark(Inbox.instance.named(e.key)!, size: 20), hint: e.value),
    if (!ghost.friend && ghost.buddy == null && ghost.username.isNotEmpty && Me.instance.username != null)
      Choice('Add @${ghost.username} as a friend', Lucide.userPlus, () => unawaited(_addFriend(context, ghost.username)), hint: 'You can write to them once they say yes'),
    if (ghost.buddy?.state == 'invited') Choice('Accept friend request', Lucide.userCheck, () => unawaited(Buddies.instance.accept(ghost.buddy!))),
    if (ghost.username.isNotEmpty) Choice('Copy @${ghost.username}', Lucide.copy, () => _copy(context, '@${ghost.username}')),
  ];
}

void _copy(BuildContext context, String text) {
  unawaited(Clipboard.setData(ClipboardData(text: text)));
  toast(context, 'Copied $text');
}

Future<void> _addFriend(BuildContext context, String username) async {
  try {
    await Buddies.instance.add(username);
    if (context.mounted) toast(context, 'Asked @$username to be friends');
  } catch (e) {
    if (context.mounted) toast(context, '$e', tone: GlacierToastTone.danger);
  }
}

Future<void> _openGhostChat(BuildContext context, _Ghost g) async {
  final address = UsernameChats.addressOf(g.username);
  final person = Person(address: address, name: g.name);
  final thread = await Sms.instance.threadFor([address]);
  if (!context.mounted) return;
  final shell = AppShell.maybeOf(context);
  if (shell != null) return shell.openThread(thread, [person]);
  push<void>(context, (_) => ThreadScreen(thread: thread, people: [person]));
}

Future<void> _openNumber(BuildContext context, String number, String name) async {
  try {
    final person = Person(address: number, name: name);
    final thread = await Sms.instance.threadFor([number]);
    if (!context.mounted) return;
    final shell = AppShell.maybeOf(context);
    if (shell != null) return shell.openThread(thread, [person]);
    push<void>(context, (_) => ThreadScreen(thread: thread, people: [person]));
  } catch (e) {
    if (context.mounted) toast(context, 'Couldn\'t start that chat: $e', tone: GlacierToastTone.danger);
  }
}

Future<void> _openNetworkChat(BuildContext context, ProfileSubject who) async {
  final network = who.network!;
  try {
    var id = who.id;
    var name = who.name;
    if (id.isEmpty) {
      final p = await network.profileOf(username: who.username);
      id = p?.id ?? '';
      if (p != null && p.name.isNotEmpty) name = p.name;
    }
    if (id.isEmpty) throw StateError('${network.name} didn\'t say who that is');
    // A username that is a channel or a group (Telegram's are below zero): the chat itself.
    final chat = id.startsWith('-') ? id : await network.chatWith(InboxContact(network: network.id, id: id, name: name));
    if (!context.mounted) return;
    if (chat == null) throw StateError('${network.name} didn\'t open a chat');
    openInboxChat(context, network, network.chats.where((x) => x.id == chat).firstOrNull ?? InboxChat(network: network.id, id: chat, title: name, date: DateTime.now()));
  } catch (e) {
    if (context.mounted) toast(context, 'Couldn\'t start that chat: $e', tone: GlacierToastTone.danger);
  }
}

/// The card at the top of the sheet: picture, name, username and status, the line about them, and on Ghost the field
/// to write to them.
class _ProfileCard extends StatefulWidget {
  const _ProfileCard({required this.who, this.ghost});
  final ProfileSubject who;
  final _Ghost? ghost;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  InboxProfile? _network;
  String? _picture;
  bool _looking = true;
  final _dm = TextEditingController();
  final _dmFocus = FocusNode();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(_look());
  }

  @override
  void dispose() {
    _dm.dispose();
    _dmFocus.dispose();
    super.dispose();
  }

  Future<void> _look() async {
    final who = widget.who, g = widget.ghost;
    try {
      if (who.network != null) {
        _network = await who.network!.profileOf(user: who.id, username: who.username).timeout(const Duration(seconds: 10));
      } else if (g != null) {
        if (g.me) {
          _picture = Me.instance.picture;
        } else if (g.buddy != null && g.buddy!.picture.isNotEmpty) {
          _picture = g.buddy!.picture;
        } else if (g.id.isNotEmpty) {
          _picture = ProfilePictures.instance.of(g.id, hash: g.pictureHash) ?? await who.room?.pictureOf(g.id);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _looking = false);
  }

  Future<void> _send() async {
    final g = widget.ghost!;
    final words = _dm.text.trim();
    if (words.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await Sms.instance.send([UsernameChats.addressOf(g.username)], words);
      _dm.clear();
      if (mounted) toast(context, 'Sent to ${g.name.isNotEmpty ? g.name : '@${g.username}'}');
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t send: $e', tone: GlacierToastTone.danger);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final who = widget.who, g = widget.ghost, n = _network;
    final name = n?.name.isNotEmpty == true ? n!.name : (g?.name.isNotEmpty == true ? g!.name : (who.name.isNotEmpty ? who.name : who.username));
    final username = n?.username.isNotEmpty == true ? n!.username : (g?.username ?? who.username);
    final status = n?.status.isNotEmpty == true ? n!.status : (g?.status ?? '');
    final bio = n?.bio.isNotEmpty == true ? n!.bio : (g?.me == true ? Me.instance.bio : (g?.buddy?.bio ?? ''));
    final where = who.network?.name ?? 'Ghost';
    final sub = [if (username.isNotEmpty) '@$username', where, if (n != null && n.seen.isNotEmpty) n.seen, if (n != null && n.bot) 'bot'].join(' · ');
    // What they shared beyond Ghost: their number and the accounts they linked (Me.shareLinks), or a network's number.
    final links = <(String, String)>[
      for (final e in (g?.buddy?.links ?? const <String, String>{}).entries) (e.key == 'phone' ? 'Phone' : (Inbox.instance.named(e.key)?.name ?? _titled(e.key)), e.value),
      if (n != null && n.number.isNotEmpty) ('Phone', n.number),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(4), t.space(2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          ProfileFace(name: name, picture: _picture, file: n?.avatar, size: t.lenOf('4rem')),
          SizedBox(width: t.space(3)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Flexible(child: Text(name.isEmpty ? 'Someone' : name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('lg'), weight: 'bold', color: t.color('app-ink')))),
                // On Ghost: the verified-number badge, where they verified a number (Matt, 2026-11-19).
                if (g != null && g.id.isNotEmpty) VerifiedBadge(id: g.id, username: g.username, me: g.me, size: 18),
              ]),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
              if (status.isNotEmpty) ...[
                SizedBox(height: t.space(1)),
                Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-ink-2'))),
              ],
            ]),
          ),
          if (_looking) const GhostSpinner(size: 16),
        ]),
        // Their special badges by name (lib/ui/special_badges.dart), given from the admin page.
        if (g != null && g.id.isNotEmpty)
          ListenableBuilder(
            listenable: Listenable.merge([SpecialBadges.instance, Me.instance]),
            builder: (context, _) {
              final badges = SpecialBadges.instance.of(g.id, username: g.username, me: g.me);
              if (badges.isEmpty) return const SizedBox.shrink();
              return Padding(
                key: const ValueKey('profile-special'),
                padding: EdgeInsets.only(top: t.space(3)),
                child: Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [for (final b in badges) SpecialBadgeChip(badge: b)]),
              );
            },
          ),
        if (who.detail.isNotEmpty) ...[
          SizedBox(height: t.space(2)),
          Text(who.detail, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-ink-2'))),
        ],
        if (links.isNotEmpty) ...[
          SizedBox(height: t.space(2)),
          for (final (label, value) in links)
            Padding(
              padding: EdgeInsets.only(top: t.space(1)),
              child: Row(children: [
                SizedBox(width: t.lenOf('5.5rem'), child: Text(label, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')))),
                Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-ink')))),
              ]),
            ),
        ],
        if (bio.isNotEmpty) ...[
          SizedBox(height: t.space(3)),
          Text(bio, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'), height: 1.4)),
        ],
        if (g != null && g.friend && !g.me) ...[
          SizedBox(height: t.space(3)),
          // The box every conversation writes in, Send inside it at its end (Matt, 2026-11-19: "move the send message
          // button inside the input like we have on the rest of the app as well within that drawer").
          ListenableBuilder(
            listenable: _dm,
            builder: (context, _) => ComposerBox(
              key: const ValueKey('profile-dm'),
              typing: false,
              // Its edges on the card's, lined up with the choices under it (Matt, 2026-11-19: "there is too much
              // padding on the left and right of the send message bar in the profile popup it doesn't line up with the
              // @mention open chat and copy options").
              flush: true,
              // The card is the composer's grey already: the box in the page's own colour stands out on it.
              ground: t.color('app-paper'),
              ends: [
                IconTap(
                  key: const ValueKey('profile-dm-send'),
                  icon: Lucide.arrowUp,
                  label: 'Send',
                  filled: true,
                  size: 19,
                  box: t.lenOf('2.25rem'),
                  onPressed: _sending || _dm.text.trim().isEmpty ? null : () => unawaited(_send()),
                ),
              ],
              field: ComposerField(controller: _dm, focusNode: _dmFocus, hint: 'Message ${g.name.isNotEmpty ? g.name : g.username}', onSubmitted: () => unawaited(_send()), enterSends: true),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Someone's face: their picture (a base64 [picture], or a [file] a network fetched), else their initial on a disc.
class ProfileFace extends StatelessWidget {
  const ProfileFace({super.key, required this.name, this.picture, this.file, this.size = 44});
  final String name;
  final String? picture;
  final String? file;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget? image;
    final p = picture;
    if (p != null && p.isNotEmpty) {
      try {
        image = Image.memory(base64Decode(p), width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true);
      } catch (_) {}
    }
    final f = file;
    if (image == null && f != null && f.isNotEmpty && File(f).existsSync()) image = Image.file(File(f), width: size, height: size, fit: BoxFit.cover);
    if (image != null) return ClipOval(child: SizedBox(width: size, height: size, child: image));
    final letter = name.trim().isEmpty ? '?' : String.fromCharCodes(name.trim().runes.take(1)).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: t.color('app-paper-2'), border: Border.all(color: t.color('app-rule'))),
      child: name.trim().isEmpty ? AppIcon(Lucide.circleUser, size: size * 0.45, color: t.color('app-ink-3')) : Text(letter, style: pageText(t, size * 0.4, weight: 'bold', color: t.color('app-ink-2'))),
    );
  }
}

/// The "@username"s written in [text] as plain words (a Ghost username's shape: three to twenty letters, numbers, dots
/// or underscores, not inside an email address), as mentions whose id is `u:<username>` ([subjectOfMention]): in a
/// conversation, where nothing says who an "@" means, the name written is who is meant.
List<Mention> handleMentions(String text) {
  if (!text.contains('@')) return const [];
  final out = <Mention>[];
  for (final m in _handle.allMatches(text)) {
    final at = m.start + m.group(1)!.length;
    var name = m.group(2)!;
    while (name.endsWith('.')) {
      name = name.substring(0, name.length - 1);
    }
    if (name.length < 3) continue;
    out.add(Mention(at, name.length + 1, 'u:${name.toLowerCase()}'));
    if (out.length >= Mention.most) break;
  }
  return Mention.checked(out, text);
}

final _handle = RegExp(r'(^|[^A-Za-z0-9_.@])@([A-Za-z0-9][A-Za-z0-9._]{2,19})(?![A-Za-z0-9_@])');

/// [m]'s mentions as the message lines carry them: `n:<id>` where the network named the person, `u:<username>` where
/// only their username was written.
List<Mention> inboxMentions(InboxMessage m) => Mention.checked([
      for (final x in m.mentions)
        if (x.user.isNotEmpty || x.username.isNotEmpty) Mention(x.start, x.length, x.user.isNotEmpty ? 'n:${x.user}' : 'u:${x.username}'),
    ], m.text);

String _titled(String network) => network.isEmpty ? network : network[0].toUpperCase() + network.substring(1);
