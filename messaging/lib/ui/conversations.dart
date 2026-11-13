import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/fold.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../sms.dart';
import 'common.dart';
import 'compose.dart';
import 'settings.dart';
import 'thread.dart';

/// Home: every conversation, the newest first, with a search over names, numbers and the last message.
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key, this.archived = false});

  /// The Archived page: the same list, of the conversations put away.
  final bool archived;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<Conversation>? _all;
  String _query = '';
  StreamSubscription<int>? _changes;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
    _changes = Sms.instance.changes.stream.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), _load);
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final all = await Sms.instance.conversations();
      if (mounted) setState(() => _all = all);
    } catch (e) {
      if (mounted) setState(() => _all ??= const []);
    }
  }

  List<Conversation> get _shown {
    final list = (_all ?? const <Conversation>[]).where((c) => c.archived == widget.archived);
    if (_query.trim().isEmpty) return list.toList();
    final q = fold(_query.trim());
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    return list.where((c) {
      if (fold(c.snippet).contains(q)) return true;
      for (final p in c.people) {
        if (fold(p.label).contains(q)) return true;
        if (digits.length >= 3 && p.address.replaceAll(RegExp(r'[^0-9]'), '').contains(digits)) return true;
      }
      return false;
    }).toList();
  }

  Future<void> _open(Conversation c) async {
    await push<void>(context, (_) => ThreadScreen(thread: c.id, people: c.people));
    _load();
  }

  void _menu(Conversation c) {
    showChoices(context, title: c.title, choices: [
      if (c.unread) Choice('Mark as read', Lucide.checkCheck, () async { await Sms.instance.markRead(c.id); _load(); }),
      Choice(c.archived ? 'Unarchive' : 'Archive', c.archived ? Lucide.archiveRestore : Lucide.archive, () async {
        await Sms.instance.archive(c.id, !c.archived);
        await _load();
        if (!mounted) return;
        toast(context, c.archived ? 'Moved back to Messages' : 'Archived',
            action: GlacierToastAction(label: 'Undo', onPress: () async { await Sms.instance.archive(c.id, c.archived); _load(); }));
      }),
      Choice('Delete conversation', Lucide.trash2, () => _confirmDelete(c), danger: true),
    ]);
  }

  void _confirmDelete(Conversation c) {
    showChoices(context, title: 'Delete every message with ${c.title}? This can\'t be undone.', choices: [
      Choice('Delete', Lucide.trash2, () async {
        await Sms.instance.deleteThread(c.id);
        await _load();
        if (mounted) toast(context, 'Conversation deleted');
      }, danger: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shown = _shown;
    final archivedCount = (_all ?? const <Conversation>[]).where((c) => c.archived).length;
    final gutter = t.space(4);

    Widget body;
    if (_all == null) {
      body = const SizedBox.shrink();
    } else if (shown.isEmpty) {
      body = ListView(padding: EdgeInsets.fromLTRB(gutter, t.space(10), gutter, 0), children: [
        SettingsEmpty(
          icon: AppIcon(Lucide.ghost, size: 28, color: t.color('app-ink-3')),
          title: _query.isNotEmpty ? 'Nothing found' : (widget.archived ? 'Nothing archived' : 'No conversations yet'),
          body: Text(_query.isNotEmpty ? 'No name, number or message matches "$_query".' : (widget.archived ? 'Conversations you archive wait here.' : 'Start one with the button below.')),
        ),
      ]);
    } else {
      body = RefreshableList(
        onRefresh: _load,
        children: [
          for (var i = 0; i < shown.length; i++) _Row(conversation: shown[i], onPress: () => _open(shown[i]), onLongPress: () => _menu(shown[i])),
          if (!widget.archived && archivedCount > 0 && _query.isEmpty)
            GlacierPressable(
              onPressed: () async {
                await push<void>(context, (_) => const ConversationsScreen(archived: true));
                _load();
              },
              builder: (context, state) => Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter, vertical: t.space(4)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  AppIcon(Lucide.archive, size: 16, color: t.color(state.pressed ? 'app-ink-4' : 'app-ink-3')),
                  SizedBox(width: t.space(2)),
                  Text('Archived ($archivedCount)', style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color(state.pressed ? 'app-ink-4' : 'app-ink-3'))),
                ]),
              ),
            ),
          SizedBox(height: t.lenOf('6rem')),
        ],
      );
    }

    return GhostPage(
      title: widget.archived ? 'Archived' : 'Messages',
      back: widget.archived,
      actions: [
        if (!widget.archived) IconTap(icon: Lucide.settings, label: 'Settings', onPressed: () => push<void>(context, (_) => const SettingsScreen())),
      ],
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(gutter, 0, gutter, t.space(2)),
                child: GlacierSearchField(
                  placeholder: widget.archived ? 'Search archived' : 'Search messages',
                  size: GlacierFieldSize.md,
                  onValueChange: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(child: body),
            ],
          ),
          if (!widget.archived)
            Positioned(
              right: gutter,
              bottom: MediaQuery.paddingOf(context).bottom + gutter,
              child: _ComposeButton(onPressed: () async {
                await push<void>(context, (_) => const ComposeScreen());
                _load();
              }),
            ),
        ],
      ),
    );
  }
}

/// A list that refreshes when pulled past its top.
class RefreshableList extends StatefulWidget {
  const RefreshableList({super.key, required this.children, required this.onRefresh});
  final List<Widget> children;
  final Future<void> Function() onRefresh;

  @override
  State<RefreshableList> createState() => _RefreshableListState();
}

class _RefreshableListState extends State<RefreshableList> {
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is OverscrollNotification && n.overscroll < 0 && n.metrics.pixels <= 0) _armed = true;
        if (n is ScrollUpdateNotification && n.metrics.pixels < -60) _armed = true;
        if (n is ScrollEndNotification && _armed) {
          _armed = false;
          widget.onRefresh();
        }
        return false;
      },
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.zero,
        children: widget.children,
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.conversation, required this.onPress, required this.onLongPress});
  final Conversation conversation;
  final VoidCallback onPress;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = conversation;
    final unread = c.unread;
    return GestureDetector(
      onLongPress: onLongPress,
      child: GlacierPressable(
        onPressed: onPress,
        builder: (context, state) => ColoredBox(
          color: state.pressed ? t.color('app-paper-2') : const Color(0x00000000),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(3)),
            child: Row(
              children: [
                Avatar(people: c.people, size: t.lenOf('3rem')),
                SizedBox(width: t.space(3)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: unread ? 'bold' : 'semibold', color: t.color('app-ink'))),
                        ),
                        SizedBox(width: t.space(2)),
                        Text(listWhen(c.date), style: pageText(t, t.fontSize('xs'), weight: unread ? 'semibold' : 'regular', color: t.color(unread ? 'app-ink' : 'app-ink-3'))),
                      ]),
                      SizedBox(height: t.lenOf('0.15rem')),
                      Row(children: [
                        if (c.error) ...[AppIcon(Lucide.circleAlert, size: 14, color: t.colorOf('#dd3a30')), SizedBox(width: t.space(1))],
                        Expanded(
                          child: Text(
                            c.error ? 'Not sent' : c.snippet.replaceAll('\n', ' '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: pageText(t, t.fontSize('sm'), weight: unread ? 'medium' : 'regular', color: t.color(unread ? 'app-ink' : 'app-ink-2'), height: 1.35),
                          ),
                        ),
                        if (unread) ...[
                          SizedBox(width: t.space(2)),
                          Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: t.colorOf('#4f5bd5'))),
                        ],
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The round button that starts a new message.
class _ComposeButton extends StatelessWidget {
  const _ComposeButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: 'New message',
      builder: (context, state) => AnimatedScale(
        scale: state.pressed ? 0.94 : 1,
        duration: const Duration(milliseconds: 120),
        child: Container(
          height: t.lenOf('3.5rem'),
          padding: EdgeInsets.symmetric(horizontal: t.space(5)),
          decoration: BoxDecoration(
            color: t.color('app-ink'),
            borderRadius: BorderRadius.circular(t.lenOf('1.75rem')),
            boxShadow: t.shadowOf('0 4px 14px rgba(0,0,0,0.12)'),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(Lucide.messageSquarePlus, size: 20, color: t.color('app-paper')),
            SizedBox(width: t.space(2)),
            Text('New message', style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-paper'))),
          ]),
        ),
      ),
    );
  }
}
