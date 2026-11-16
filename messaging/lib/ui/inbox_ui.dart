

import 'package:flutter/services.dart' show Clipboard, ClipboardData, HapticFeedback, TextCapitalization, TextInputAction, TextInputType;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../backgrounds.dart';
import '../inbox/bluesky.dart';
import '../inbox/inbox.dart';
import '../inbox/telegram.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../me/me.dart' as me;
import '../sms.dart';
import 'common.dart';
import 'composer_box.dart';
import 'conversations.dart' show ConversationRow;
import 'me.dart' show NetworkMark;
import 'settings.dart';
import 'shell.dart';

/// The screens of the inbox of other networks (lib/inbox): a chat's row in the list, the chat itself, signing in, and
/// the sections of Settings for each network.

/// The list's tab for [network] (lib/ui/conversations.dart).
String inboxTab(InboxNetwork network) => '*inbox-${network.id}';

/// The network a tab of the list is, or null for any other tab.
InboxNetwork? inboxOfTab(String? tab) => tab != null && tab.startsWith('*inbox-') ? Inbox.instance.named(tab.substring(7)) : null;

/// A network's logo, as Settings › Me draws it.
Widget inboxMark(InboxNetwork network, {double size = 18}) => NetworkMark(me.networks.firstWhere((n) => n.id == network.id), size: size);

/// One chat in the list: drawn as a conversation is, so the tab reads like the rest of the app.
class InboxChatRow extends StatelessWidget {
  const InboxChatRow({super.key, required this.chat, required this.onPress, this.onLongPress, this.selected = false});
  final InboxChat chat;
  final VoidCallback onPress;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = Conversation(
      // The row draws from the conversation alone; the id is only for keys.
      id: -(chat.id.hashCode & 0x3fffffff) - 1,
      date: chat.date,
      people: [Person(address: '${chat.network}:${chat.id}', name: chat.title, photo: chat.avatar)],
      snippet: chat.lastFromMe && chat.snippet.isNotEmpty ? 'You: ${chat.snippet}' : chat.snippet,
      unread: chat.unread > 0,
      error: false,
      archived: false,
    );
    final network = Inbox.instance.named(chat.network);
    // Its network's mark on the corner of the face, so a Telegram or Bluesky chat among the texts says what it is.
    return ConversationRow(conversation: c, selected: selected, onPress: onPress, onLongPress: onLongPress ?? onPress, badge: network == null ? null : inboxMark(network, size: 16));
  }
}

/// A chat pressed and held in the list: archived or brought back, or deleted, on its network where it can be (Matt,
/// 2026-11-15: "if possible proxy the archive and delete messages too, if we can't actually delete telegram messages
/// add them to a ignore or archive list"). Telegram does both itself; a network that can't keeps Ghost's own list.
void inboxChatMenu(BuildContext context, InboxNetwork network, InboxChat chat, {required bool archived}) {
  HapticFeedback.mediumImpact();
  showChoices(context, title: chat.title, choices: [
    Choice(archived ? 'Unarchive' : 'Archive', archived ? Lucide.archiveRestore : Lucide.archive, () => network.archive(chat.id, !archived)),
    Choice(chat.group ? 'Leave and delete' : 'Delete', Lucide.trash2, () {
      showChoices(context, title: chat.group ? 'Leave ${chat.title} and delete it on ${network.name}?' : 'Delete this chat on ${network.name}?', choices: [
        Choice(chat.group ? 'Leave and delete' : 'Delete', Lucide.trash2, () => network.deleteChat(chat.id), danger: true),
      ]);
    }, danger: true),
  ]);
}

/// Opens [chat] in the pane beside the list, or over it on a phone.
void openInboxChat(BuildContext context, InboxNetwork network, InboxChat chat) {
  final page = InboxChatScreen(network: network, chatId: chat.id);
  final shell = AppShell.maybeOf(context);
  if (shell != null) {
    shell.show(page, showing: 'inbox:${network.id}:${chat.id}');
  } else {
    push<void>(context, (_) => page);
  }
}

/// A chat on another network: its messages as bubbles, and a line to answer in. Sent from here, a message goes as
/// the network's own app would send it.
class InboxChatScreen extends StatefulWidget {
  const InboxChatScreen({super.key, required this.network, required this.chatId});
  final InboxNetwork network;
  final String chatId;

  @override
  State<InboxChatScreen> createState() => _InboxChatScreenState();
}

class _InboxChatScreenState extends State<InboxChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  bool _loadingOlder = false;

  InboxNetwork get _n => widget.network;

  @override
  void initState() {
    super.initState();
    _n.watching = widget.chatId;
    _n.load(widget.chatId).then((_) => _n.markRead(widget.chatId));
    _n.addListener(_changed);
    _scroll.addListener(_nearTop);
    // The composer lays itself out by whether there are words (lib/ui/composer_box.dart).
    _text.addListener(_typed);
  }

  final _focus = FocusNode();
  bool _wasTyping = false;
  void _typed() {
    final typing = _text.text.isNotEmpty;
    if (typing != _wasTyping && mounted) setState(() => _wasTyping = typing);
  }

  /// Pressed and held: copy it, or delete it, for this account or, where the network allows, for everyone (Matt,
  /// 2026-11-15: "if possible proxy the archive and delete messages too").
  void _messageMenu(InboxMessage m) {
    HapticFeedback.mediumImpact();
    showChoices(context, choices: [
      if (m.text.isNotEmpty) Choice('Copy', Lucide.copy, () => Clipboard.setData(ClipboardData(text: m.text))),
      if (_n.canDeleteForEveryone(widget.chatId, m)) Choice('Delete for everyone', Lucide.trash2, () => _n.deleteMessage(widget.chatId, m.id, forEveryone: true), danger: true),
      Choice(m.mine && _n.canDeleteForEveryone(widget.chatId, m) ? 'Delete for me' : 'Delete', Lucide.trash2, () => _n.deleteMessage(widget.chatId, m.id), danger: true),
    ]);
  }

  int _seen = 0;
  void _changed() {
    // Read as it arrives, while the chat is open.
    final count = _n.messagesOf(widget.chatId).length;
    if (count != _seen) {
      _seen = count;
      _n.markRead(widget.chatId);
    }
  }

  void _nearTop() {
    if (_loadingOlder || !_scroll.hasClients) return;
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 400) return;
    final more = switch (_n) { Bluesky b => b.hasOlder(widget.chatId), Telegram t => t.hasOlder(widget.chatId), _ => false };
    if (!more) return;
    _loadingOlder = true;
    _n.load(widget.chatId, older: true).whenComplete(() => _loadingOlder = false);
  }

  @override
  void dispose() {
    _n.removeListener(_changed);
    _n.watching = null;
    _text.removeListener(_typed);
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _text.text;
    if (text.trim().isEmpty) return;
    _text.clear();
    _n.send(widget.chatId, text);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = AppState.of(context);
    return ListenableBuilder(
      listenable: _n,
      builder: (context, _) {
        final chat = _n.chats.where((c) => c.id == widget.chatId).firstOrNull;
        final list = _n.shownMessages(widget.chatId).reversed.toList();
        final (mineBg, mineInk) = myBubble(t, app);
        return GhostPage(
          title: chat?.title ?? _n.name,
          titleWidget: Row(mainAxisSize: MainAxisSize.min, children: [
            inboxMark(_n, size: 16),
            SizedBox(width: t.space(2)),
            Flexible(child: Text(chat?.title ?? _n.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('lg'), weight: 'semibold'))),
          ]),
          footer: Padding(
            padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(2) + MediaQuery.paddingOf(context).bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (_n.error != null)
                Padding(
                  padding: EdgeInsets.only(bottom: t.space(2)),
                  child: Text(_n.error!, style: pageText(t, t.fontSize('xs'), color: t.colorOf('#dd3a30'))),
                ),
              // The same box as a conversation of texts (lib/ui/composer_box.dart; Matt, 2026-11-15: "Also use the same
              // composer for telegram"): words alone here, so no + or microphone, and Send at its end.
              Builder(builder: (context) {
                final style = composerTextStyle(t);
                final strut = composerStrutStyle(t);
                final enterSends = app.enterSends;
                final send = IconTap(icon: Lucide.send, label: 'Send', filled: true, size: 16, box: t.lenOf('2.25rem'), onPressed: _text.text.trim().isEmpty ? null : _send);
                return ComposerBox(
                  typing: _text.text.isNotEmpty,
                  ends: [send],
                  below: [send],
                  field: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _focus.requestFocus(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: t.lenOf('2.25rem')),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: t.lenOf('0.3rem')),
                          child: Stack(children: [
                            if (_text.text.isEmpty)
                              IgnorePointer(child: Text('Message on ${_n.name}', style: style.copyWith(color: t.color('app-ink-3')), strutStyle: strut, textHeightBehavior: composerLeading)),
                            EditableText(
                              controller: _text,
                              focusNode: _focus,
                              style: style,
                              strutStyle: strut,
                              textHeightBehavior: composerLeading,
                              cursorColor: t.color('app-ink'),
                              backgroundCursorColor: t.color('app-ink-3'),
                              minLines: 1,
                              maxLines: 6,
                              keyboardType: enterSends ? TextInputType.text : TextInputType.multiline,
                              textInputAction: enterSends ? TextInputAction.send : TextInputAction.newline,
                              onSubmitted: (_) => _send(),
                              onEditingComplete: enterSends ? () {} : null,
                              textCapitalization: TextCapitalization.sentences,
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ]),
          ),
          body: list.isEmpty
              ? Center(child: Text(_n.state == InboxState.ready ? 'No messages yet' : 'Not signed in to ${_n.name}', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))))
              : ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(2)),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final m = list[i];
                    final older = i + 1 < list.length ? list[i + 1] : null;
                    final newer = i > 0 ? list[i - 1] : null;
                    final firstOfRun = older == null || older.mine != m.mine || older.sender != m.sender || m.date.difference(older.date).inMinutes > 10;
                    final lastOfRun = newer == null || newer.mine != m.mine || newer.sender != m.sender || newer.date.difference(m.date).inMinutes > 10;
                    final newDay = older == null || older.date.day != m.date.day || older.date.month != m.date.month || older.date.year != m.date.year;
                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (newDay)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: t.space(3)),
                          child: Text(dayHeading(m.date), textAlign: TextAlign.center, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-3'))),
                        ),
                      GestureDetector(
                        onLongPress: () => _messageMenu(m),
                        child: _InboxBubble(key: ValueKey(m.id), message: m, group: chat?.group ?? false, first: firstOfRun, last: lastOfRun, mineBg: mineBg, mineInk: mineInk),
                      ),
                    ]);
                  },
                ),
        );
      },
    );
  }
}

class _InboxBubble extends StatelessWidget {
  const _InboxBubble({super.key, required this.message, required this.group, required this.first, required this.last, required this.mineBg, required this.mineInk});
  final InboxMessage message;
  final bool group, first, last;
  final Color mineBg, mineInk;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final m = message;
    final round = Radius.circular(t.lenOf('1.125rem'));
    final tight = Radius.circular(t.lenOf('0.375rem'));
    final failed = m.state == 'failed';
    return Padding(
      padding: EdgeInsets.only(top: first ? t.space(2) : 2),
      child: Column(crossAxisAlignment: m.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        if (group && !m.mine && first && m.sender.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(left: t.space(3), bottom: 2),
            child: Text(m.sender, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-3'))),
          ),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
          child: Opacity(
            opacity: m.state == 'sending' ? 0.6 : 1,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
              decoration: BoxDecoration(
                // The conversation's own colours (lib/backgrounds.dart): a white bubble on the light page has a line round it.
                color: m.mine ? mineBg : theirBubble(t, onBackground: false),
                border: m.mine && bubbleNeedsRim(mineBg, t.color('glacier-bg')) ? Border.all(color: t.color('app-ink-4'), width: 1) : null,
                borderRadius: BorderRadius.only(
                  topLeft: !m.mine && !first ? tight : round,
                  bottomLeft: !m.mine && !last ? tight : round,
                  topRight: m.mine && !first ? tight : round,
                  bottomRight: m.mine && !last ? tight : round,
                ),
              ),
              child: Text(m.text, style: pageText(t, t.fontSize('md'), color: m.mine ? mineInk : t.color('app-ink'), height: 1.3)),
            ),
          ),
        ),
        if (last || failed)
          Padding(
            padding: EdgeInsets.only(top: 2, left: t.space(2), right: t.space(2)),
            child: Text(
              failed ? 'Not sent' : (m.state == 'sending' ? 'Sending…' : clock(m.date)),
              style: pageText(t, t.fontSize('xs'), color: failed ? t.colorOf('#dd3a30') : t.color('app-ink-3')),
            ),
          ),
      ]),
    );
  }
}

/// What the list's tab shows where a network has no chats.
Widget inboxEmpty(BuildContext context, InboxNetwork network) {
  final t = context.tokens;
  return Padding(
    padding: EdgeInsets.all(t.space(6)),
    child: SettingsEmpty(
      icon: inboxMark(network, size: 28),
      title: network.state == InboxState.ready ? 'No chats yet' : 'Not signed in to ${network.name}',
      body: Text(network.state == InboxState.ready ? 'Chats on ${network.name} appear here as they come.' : 'Sign in from Settings › ${network.name}.'),
    ),
  );
}

// --- signing in ------------------------------------------------------------------------------------------------------

Widget _icon(LucideIcon icon) => AppIcon(icon, size: 18);

/// Signing in to Bluesky: a handle and an app password that may read direct messages.
class BlueskySignInScreen extends StatefulWidget {
  const BlueskySignInScreen({super.key, required this.network});
  final Bluesky network;

  @override
  State<BlueskySignInScreen> createState() => _BlueskySignInScreenState();
}

class _BlueskySignInScreenState extends State<BlueskySignInScreen> {
  final _handle = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _handle.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    if (_handle.text.trim().isEmpty || _password.text.trim().isEmpty) return;
    await widget.network.signIn(_handle.text, _password.text);
    if (!mounted) return;
    if (widget.network.state == InboxState.ready) {
      _password.clear();
      toast(context, 'Signed in to Bluesky as @${widget.network.account}');
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final n = widget.network;
    return ListenableBuilder(
      listenable: n,
      builder: (context, _) {
        final busy = n.state == InboxState.signingIn;
        return GhostPage(
          title: 'Sign in to Bluesky',
          body: SettingsPaneScope(
            finder: SettingsFinder(),
            child: ListView(
              padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                PaneSection(
                  title: 'Your account',
                  description: const Text(
                      'Use an app password, not your account\'s password. Make one in Bluesky: Settings › Privacy and security › App passwords › Add, with "Allow access to your direct messages" ticked. It can be taken back there at any time.'),
                  footer: n.error == null ? null : Text(n.error!, style: TextStyle(color: t.colorOf('#dd3a30'))),
                  children: [
                    SettingRowBox(
                      child: GlacierInput(controller: _handle, placeholder: 'you.bsky.social', ariaLabel: 'Your handle', autoCorrect: false, autoFocus: true, size: GlacierFieldSize.md),
                    ),
                    SettingRowBox(
                      child: GlacierInput(controller: _password, type: GlacierInputType.password, placeholder: 'xxxx-xxxx-xxxx-xxxx', ariaLabel: 'App password', autoCorrect: false, size: GlacierFieldSize.md, onSubmitted: (_) => _go()),
                    ),
                    SettingRow(icon: _icon(Lucide.arrowRight), label: busy ? 'Signing in…' : 'Sign in', disabled: busy, onPress: _go),
                  ],
                ),
                SizedBox(height: t.space(4)),
                const SettingsFootnote(child: Text('Your messages go between this device and Bluesky. Ghost\'s own server never sees them, and the app password itself isn\'t kept: only the session Bluesky gives back.')),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Signing in to Telegram: the phone number, the code Telegram sends, and the two-step password where there is one.
class TelegramSignInScreen extends StatefulWidget {
  const TelegramSignInScreen({super.key, required this.network});
  final Telegram network;

  @override
  State<TelegramSignInScreen> createState() => _TelegramSignInScreenState();
}

class _TelegramSignInScreenState extends State<TelegramSignInScreen> {
  final _field = TextEditingController();
  InboxStep _shown = InboxStep.none;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.network.begin();
    widget.network.addListener(_changed);
  }

  void _changed() {
    final n = widget.network;
    if (n.step != _shown) {
      _shown = n.step;
      _field.clear();
    }
    if (n.state == InboxState.ready && mounted) {
      toast(context, 'Signed in to Telegram${n.account == null ? '' : ' as ${n.account}'}');
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    widget.network.removeListener(_changed);
    _field.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final n = widget.network;
    final v = _field.text;
    if (v.trim().isEmpty) return;
    setState(() => _busy = true);
    switch (n.step) {
      case InboxStep.phone:
        await n.sendPhone(v);
      case InboxStep.code:
        await n.sendCode(v);
      case InboxStep.password:
        await n.sendPassword(v);
      default:
        break;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final n = widget.network;
    return ListenableBuilder(
      listenable: n,
      builder: (context, _) {
        final (title, about, placeholder, type, action) = switch (n.step) {
          InboxStep.phone => ('Your phone number', 'The number of your Telegram account, with its country code. Telegram sends a code to your Telegram app, or texts it.', '+1 555 010 0199', GlacierInputType.tel, 'Send the code'),
          InboxStep.code => ('The code', 'Telegram sent a code to ${n.codeWhere ?? 'you'}.', '12345', GlacierInputType.number, 'Sign in'),
          InboxStep.password => ('Your password', 'This account has a two-step password${n.passwordHint == null ? '' : ' (hint: ${n.passwordHint})'}.', 'Password', GlacierInputType.password, 'Sign in'),
          _ => ('', '', '', GlacierInputType.text, ''),
        };
        return GhostPage(
          title: 'Sign in to Telegram',
          body: SettingsPaneScope(
            finder: SettingsFinder(),
            child: ListView(
              padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (n.state == InboxState.unavailable)
                  SettingsCallout(child: Text(n.error ?? 'Telegram isn\'t in this build of the app.'))
                else if (n.step == InboxStep.none)
                  Padding(padding: EdgeInsets.all(t.space(8)), child: const Center(child: GhostSpinner(size: 26, label: 'Starting Telegram…')))
                else
                  PaneSection(
                    key: ValueKey(n.step),
                    title: title,
                    description: Text(about),
                    footer: n.error == null ? null : Text(n.error!, style: TextStyle(color: t.colorOf('#dd3a30'))),
                    children: [
                      SettingRowBox(child: GlacierInput(controller: _field, type: type, placeholder: placeholder, ariaLabel: title, autoCorrect: false, autoFocus: true, size: GlacierFieldSize.md, onSubmitted: (_) => _go())),
                      SettingRow(icon: _icon(n.step == InboxStep.phone ? Lucide.messageSquare : Lucide.arrowRight), label: _busy ? 'One moment…' : action, disabled: _busy, onPress: _go),
                    ],
                  ),
                SizedBox(height: t.space(4)),
                const SettingsFootnote(child: Text('Ghost signs in as a Telegram app of its own, on this device. Your chats go between it and Telegram; Ghost\'s own server never sees them. Sign out here, or end the session in Telegram › Settings › Devices.')),
              ],
            ),
          ),
        );
      },
    );
  }
}

// --- Settings --------------------------------------------------------------------------------------------------------

/// Telegram's and Bluesky's sections of Settings: who is signed in, and signing in or out.
List<SettingsSection> inboxSettingsSections() => [
      for (final n in Inbox.instance.networks)
        SettingsSection(
          id: 'inbox-${n.id}',
          label: n.name,
          icon: inboxMark(n),
          hue: n.id == 'telegram' ? 'cyan' : 'blue',
          group: 'me',
          summary: (_) => _summary(n),
          page: (context, m) => _pane(context, n),
        ),
    ];

String _summary(InboxNetwork n) => n.soon ? 'Coming soon' : switch (n.state) {
      InboxState.ready => 'Signed in${n.account == null ? '' : ' as ${n.account}'}',
      InboxState.signingIn => 'Signing in…',
      InboxState.signedOut => 'Not signed in',
      InboxState.unavailable => 'Not in this build',
    };

List<Widget> _pane(BuildContext context, InboxNetwork n) {
  void signIn() {
    final page = switch (n) { Telegram tg => TelegramSignInScreen(network: tg), Bluesky b => BlueskySignInScreen(network: b), _ => null };
    if (page != null) push<void>(context, (_) => page);
  }

  return [
    PaneSection(
      title: n.name,
      description: Text('Your ${n.name} chats in a tab of their own beside Messages, read and answered here. They go between this device and ${n.name} only.'),
      footer: n.error == null || n.state == InboxState.ready ? null : Text(n.error!),
      children: [
        if (n.soon)
          SettingRow(icon: _icon(Lucide.info), label: 'Coming soon', hint: Text('${n.name} chats aren\'t offered yet.'), disabled: true)
        else if (n.state == InboxState.ready) ...[
          SettingRow(icon: _icon(Lucide.userRound), label: n.account ?? 'Signed in', hint: Text('${n.chats.length} chat${n.chats.length == 1 ? '' : 's'}')),
          SettingRow(
            icon: _icon(Lucide.logOut),
            label: 'Sign out',
            onPress: () => showChoices(context, title: 'Sign out of ${n.name}?', choices: [Choice('Sign out', Lucide.logOut, () => n.signOut(), danger: true)]),
          ),
        ] else if (n.state == InboxState.unavailable)
          SettingRow(icon: _icon(Lucide.info), label: 'Not in this build', hint: Text(n.error ?? '${n.name} isn\'t set up in this build of the app.'), disabled: true)
        else
          SettingRow(icon: _icon(Lucide.arrowRight), label: n.state == InboxState.signingIn ? 'Carry on signing in' : 'Sign in', onPress: signIn),
      ],
    ),
  ];
}

/// Puts the networks' sections into Settings, and redraws it as they change.
void addInboxSettings() => SettingsSources.add(inboxSettingsSections, watch: Inbox.instance.networks);

