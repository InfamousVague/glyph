import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/ghost_icons.dart';
import '../art/lucide.g.dart';
import '../kit/fold.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../reactions.dart';
import '../sms.dart';
import 'common.dart';
import 'compose.dart';
import 'settings.dart';
import 'thread.dart';

/// Home: every conversation, the newest first, with a search over names, numbers and the last message.
///
/// While Android's store is being read it says so: an arc and "Loading your conversations…" the first time, and a
/// thin bar under the search when a later read takes a moment (Matt, 2026-11-13: "Show a loading indicator when
/// messages are syncing"). A read that fails is said, with a way to try again, never shown as an empty list.
///
/// Several conversations can be chosen at once and deleted or archived together (Matt, the same day: "allow selecting
/// multiple convos to delete them"): a conversation's long press has Select, then a tap adds or takes away, and the
/// bar at the top counts them.
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

  /// Why the last read failed, in Android's words; null when it did not.
  String? _error;

  /// A read has been going for long enough to say so.
  bool _slow = false;
  Timer? _slowTimer;
  int _reads = 0;

  /// Older conversations are still being read behind the ones shown.
  bool _more = false;

  /// A whole read is under way, and a text came or went meanwhile: the newest are read again once it ends.
  bool _reading = false;
  bool _stale = false;

  /// How many conversations are archived, for the row that leads to them.
  int _archived = 0;

  /// The first lot: what fills the screen a few times over. And each lot after it.
  static const _first = 40;
  static const _lot = 250;

  /// The conversations chosen, while several are being chosen. Empty: not choosing.
  final Set<int> _selected = {};

  /// What can be seen of the texting app this one replaced (android/.../Arriving.kt), for the note about RCS.
  Arriving _arriving = const Arriving();

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
    _look();
    _changes = Sms.instance.changes.stream.listen((_) {
      _debounce?.cancel();
      // A text came or went: it is among the newest, so only those are read again.
      _debounce = Timer(const Duration(milliseconds: 250), _newest);
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    _debounce?.cancel();
    _slowTimer?.cancel();
    super.dispose();
  }

  Future<void> _look() async {
    try {
      final a = await Sms.instance.arriving();
      if (mounted) setState(() => _arriving = a);
    } catch (_) {}
  }

  /// Reads the conversations, the newest first (Matt, 2026-11-13: "Users with a ton of messages stored on their phone
  /// are taking forever to load, see if we can load by most recent first so that things are faster"): the first
  /// [_first] and the pinned ones at once, which is the screen, then the rest a lot at a time behind them. What was
  /// shown before stays until it is read again, and what the whole read did not find has gone.
  Future<void> _load() async {
    final read = ++_reads;
    _reading = true;
    // Said only once it has taken a moment: a quick read would only flicker.
    _slowTimer?.cancel();
    _slowTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted && read == _reads) setState(() => _slow = true);
    });
    void quiet() {
      _slowTimer?.cancel();
      if (mounted && _slow) setState(() => _slow = false);
    }

    try {
      if (widget.archived) {
        // The archived ones are asked for by name, all at once: there are few.
        final page = await Sms.instance.conversationsPage(archived: true);
        if (!mounted || read != _reads) return;
        setState(() {
          _all = page.items;
          _error = null;
          _selected.removeWhere((id) => !page.items.any((c) => c.id == id));
        });
        return;
      }
      Sms.instance.archivedCount().then((n) {
        if (mounted && read == _reads) setState(() => _archived = n);
      }).catchError((_) {});
      final seen = <int>{};
      int? at = 0;
      while (at != null) {
        final page = await Sms.instance.conversationsPage(limit: at == 0 ? _first : _lot, offset: at, pinned: at == 0);
        if (!mounted || read != _reads) return;
        seen.addAll(page.items.map((c) => c.id));
        final last = page.next == null;
        setState(() {
          _all = mergeConversations(_all, page.items, only: last ? seen : null);
          _error = null;
          _more = !last;
          // A conversation that has gone is no longer chosen.
          if (last) _selected.removeWhere((id) => !seen.contains(id));
        });
        // The screen has its conversations: the rest arrive without a word.
        if (at == 0) quiet();
        at = page.next;
      }
    } catch (e) {
      if (!mounted || read != _reads) return;
      setState(() {
        _all ??= const [];
        _error = '$e';
        _more = false;
      });
    } finally {
      if (read == _reads) {
        quiet();
        _reading = false;
        if (_stale && mounted) {
          _stale = false;
          _newest();
        }
      }
    }
  }

  /// Reads the newest conversations again and lays them over the ones held: what a text that has just come or gone
  /// changes. A whole read under way is left to finish, and this follows it.
  Future<void> _newest() async {
    if (widget.archived || _all == null) return _load();
    if (_reading) {
      _stale = true;
      return;
    }
    final read = _reads;
    try {
      final page = await Sms.instance.conversationsPage(limit: _first, pinned: true);
      if (!mounted || read != _reads) return;
      setState(() {
        _all = mergeConversations(_all, page.items);
        _error = null;
      });
    } catch (_) {
      // The list shown stands; the next whole read says what is wrong.
    }
  }

  List<Conversation> get _shown {
    // Pinned conversations first, each group newest first (the order they arrive in).
    final all = (_all ?? const <Conversation>[]).where((c) => c.archived == widget.archived).toList();
    final list = [...all.where((c) => c.pinned), ...all.where((c) => !c.pinned)];
    if (_query.trim().isEmpty) return list;
    final q = fold(_query.trim());
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    return list.where((c) {
      if (fold(c.snippet).contains(q) || (c.draft != null && fold(c.draft!).contains(q))) return true;
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

  void _toggle(Conversation c) => setState(() => _selected.contains(c.id) ? _selected.remove(c.id) : _selected.add(c.id));

  void _menu(Conversation c) {
    showChoices(context, title: c.title, choices: [
      Choice('Select', Lucide.circleCheck, () => _toggle(c)),
      if (c.unread) Choice('Mark as read', Lucide.checkCheck, () async { await Sms.instance.markRead(c.id); _load(); }),
      Choice(c.pinned ? 'Unpin' : 'Pin to top', c.pinned ? Lucide.pinOff : Lucide.pin, () async { await Sms.instance.threadFlag('pinned', c.id, !c.pinned); _load(); }),
      Choice(c.muted ? 'Unmute' : 'Mute notifications', c.muted ? Lucide.bell : GhostIcons.bellOff, () async {
        await Sms.instance.threadFlag('muted', c.id, !c.muted);
        await _load();
        if (mounted) toast(context, c.muted ? 'Notifications on' : 'Muted. Messages still arrive, quietly.');
      }),
      Choice(c.archived ? 'Unarchive' : 'Archive', c.archived ? Lucide.archiveRestore : Lucide.archive, () async {
        await Sms.instance.archive(c.id, !c.archived);
        await _load();
        if (!mounted) return;
        toast(context, c.archived ? 'Moved back to Messages' : 'Archived',
            action: GlacierToastAction(label: 'Undo', onPress: () async { await Sms.instance.archive(c.id, c.archived); _load(); }));
      }),
      if (!c.group && c.people.isNotEmpty)
        Choice(c.blocked ? 'Unblock' : 'Block number', Lucide.ban, () => c.blocked ? _setBlocked(c, false) : _confirmBlock(c), danger: !c.blocked),
      Choice('Delete conversation', Lucide.trash2, () => _confirmDelete(c), danger: true),
    ]);
  }

  void _confirmBlock(Conversation c) {
    showChoices(context, title: 'Block ${c.title}? Android will stop their texts and calls before they reach you.', choices: [
      Choice('Block', Lucide.ban, () => _setBlocked(c, true), danger: true),
    ]);
  }

  Future<void> _setBlocked(Conversation c, bool blocked) async {
    try {
      await Sms.instance.setBlocked(c.people.first.address, blocked);
      if (blocked) await Sms.instance.archive(c.id, true);
      await _load();
      if (mounted) toast(context, blocked ? 'Blocked and archived' : 'Unblocked');
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t change the block: $e', tone: GlacierToastTone.danger);
    }
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

  // --- several at once ------------------------------------------------------------------------------------------------

  String _count(int n) => '$n ${n == 1 ? 'conversation' : 'conversations'}';

  /// Asked first, with how many: a deleted conversation is gone from the phone, for every app.
  void _confirmDeleteSelected() {
    final ids = _selected.toList();
    showChoices(
      context,
      title: 'Delete ${_count(ids.length)}? Every message in ${ids.length == 1 ? 'it' : 'them'} is deleted from this phone, for every app. This can\'t be undone.',
      choices: [
        Choice('Delete ${_count(ids.length)}', Lucide.trash2, () async {
          try {
            await Sms.instance.deleteThreads(ids);
            if (mounted) setState(_selected.clear);
            await _load();
            if (mounted) toast(context, '${_count(ids.length)} deleted');
          } catch (e) {
            if (mounted) toast(context, 'Couldn\'t delete: $e', tone: GlacierToastTone.danger);
          }
        }, danger: true),
      ],
    );
  }

  Future<void> _archiveSelected() async {
    final ids = _selected.toList();
    final to = !widget.archived;
    for (final id in ids) {
      await Sms.instance.archive(id, to);
    }
    if (mounted) setState(_selected.clear);
    await _load();
    if (!mounted) return;
    toast(context, to ? '${_count(ids.length)} archived' : '${_count(ids.length)} moved back to Messages', action: GlacierToastAction(label: 'Undo', onPress: () async {
      for (final id in ids) {
        await Sms.instance.archive(id, !to);
      }
      _load();
    }));
  }

  void _settings([String? section]) async {
    await push<void>(context, (_) => section == null ? const SettingsScreen() : SettingsSectionScreen(section));
    _look();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shown = _shown;
    // Android's own count, where it has answered: the ones held are not all of them until the read ends.
    final archivedCount = widget.archived ? 0 : (_more ? _archived : (_all ?? const <Conversation>[]).where((c) => c.archived).length);
    // Older conversations still arriving: said at the foot of the list, and in place of "Nothing found".
    final more = _more && !widget.archived;
    final gutter = t.space(4);
    final app = AppState.of(context);
    // Texts from people who use RCS may still be going to the app this one replaced: said until it is dismissed.
    final notice = !widget.archived && _query.isEmpty && !_selecting && _arriving.rcsLikely && app.flag('rcs_notice');

    Widget body;
    if (_all == null) {
      body = const Center(child: GhostSpinner(size: 28, label: 'Loading your conversations…'));
    } else if (_error != null && shown.isEmpty) {
      body = ListView(padding: EdgeInsets.fromLTRB(gutter, t.space(10), gutter, 0), children: [
        SettingsEmpty(
          icon: AppIcon(Lucide.circleAlert, size: 28, color: t.colorOf('#dd3a30')),
          title: 'Couldn\'t read your messages',
          body: Text('Android didn\'t hand them over: $_error\nNothing has been deleted. They are still in Android\'s store.'),
          action: SettingsEmptyAction('Try again', _load),
        ),
      ]);
    } else if (shown.isEmpty) {
      final rcs = _query.isEmpty && !widget.archived && _arriving.rcsLikely;
      body = ListView(padding: EdgeInsets.fromLTRB(gutter, t.space(10), gutter, 0), children: [
        SettingsEmpty(
          icon: AppIcon(Lucide.ghost, size: 28, color: t.color('app-ink-3')),
          title: _query.isNotEmpty ? (more ? 'Nothing found yet' : 'Nothing found') : (widget.archived ? 'Nothing archived' : 'No conversations yet'),
          body: Text(_query.isNotEmpty
              ? (more ? 'Older conversations are still being read. Nothing so far matches "$_query".' : 'No name, number or message matches "$_query".')
              : widget.archived
                  ? 'Conversations you archive wait here.'
                  : rcs
                      ? 'There are no texts in Android\'s store. Chats that were RCS in ${_arriving.app} stay in that app, where no other app can read them: they are not deleted.'
                      : 'Start one with the button below.'),
          action: rcs ? SettingsEmptyAction('What to do', () => _settings('android')) : null,
        ),
      ]);
    } else {
      final extras = (notice ? 1 : 0);
      final tail = !widget.archived && archivedCount > 0 && _query.isEmpty && !_selecting;
      body = RefreshableList(
        onRefresh: _load,
        itemCount: extras + shown.length + (tail ? 1 : 0) + (more ? 1 : 0) + 1,
        itemBuilder: (context, i) {
          if (notice && i == 0) {
            return _RcsNotice(app: _arriving.app, onFix: () => _settings('android'), onDismiss: () => app.setFlag('rcs_notice', false));
          }
          final at = i - extras;
          if (at < shown.length) {
            final c = shown[at];
            return ConversationRow(
              conversation: c,
              selecting: _selecting,
              selected: _selected.contains(c.id),
              onPress: () => _selecting ? _toggle(c) : _open(c),
              onLongPress: () => _selecting ? _toggle(c) : _menu(c),
            );
          }
          if (tail && at == shown.length) {
            return GlacierPressable(
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
            );
          }
          if (more && at == shown.length + (tail ? 1 : 0)) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: t.space(4)),
              child: const Center(child: GhostSpinner(size: 18, label: 'Loading older conversations…')),
            );
          }
          return SizedBox(height: t.lenOf('6rem'));
        },
      );
    }

    final page = GhostPage(
      title: widget.archived ? 'Archived' : 'Messages',
      back: widget.archived && !_selecting,
      // While several are being chosen the bar counts them, and holds what can be done with them.
      titleWidget: !_selecting
          ? null
          : Row(children: [
              if (!widget.archived) const SizedBox(width: 0) else SizedBox(width: t.space(3)),
              IconTap(icon: Lucide.x, label: 'Stop selecting', onPressed: () => setState(_selected.clear)),
              SizedBox(width: t.space(1)),
              Expanded(child: Text('${_selected.length} selected', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('lg'), weight: 'semibold', color: t.color('app-ink')))),
            ]),
      actions: [
        if (_selecting) ...[
          IconTap(icon: Lucide.checkCheck, label: 'Select all', onPressed: () => setState(() => _selected.addAll(shown.map((c) => c.id)))),
          IconTap(icon: widget.archived ? Lucide.archiveRestore : Lucide.archive, label: widget.archived ? 'Unarchive' : 'Archive', onPressed: _archiveSelected),
          IconTap(icon: Lucide.trash2, label: 'Delete', color: t.colorOf('#dd3a30'), onPressed: _confirmDeleteSelected),
        ] else if (!widget.archived)
          IconTap(icon: Lucide.settings, label: 'Settings', onPressed: _settings),
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
              // A read of Android's store that is taking a moment: a thin bar, where the list already shows.
              SizedBox(
                height: 3,
                child: _slow && _all != null ? const GlacierProgressBar(indeterminate: true, ariaLabel: 'Loading your conversations') : null,
              ),
              Expanded(child: body),
            ],
          ),
          if (!widget.archived && !_selecting)
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
    // Android's back leaves choosing before it leaves the page.
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) setState(_selected.clear);
      },
      child: page,
    );
  }
}

/// A list that refreshes when pulled past its top. Its rows are built as they come into view, so a phone with
/// thousands of conversations opens as fast as one with ten.
class RefreshableList extends StatefulWidget {
  const RefreshableList({super.key, required this.itemCount, required this.itemBuilder, required this.onRefresh});
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
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
      child: ListView.builder(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.zero,
        itemCount: widget.itemCount,
        itemBuilder: widget.itemBuilder,
      ),
    );
  }
}

/// Over the list until it is dismissed, where the app this one replaced keeps RCS chats: why some people's texts may
/// not be arriving, and the way to what to do about it (Settings › Android).
class _RcsNotice extends StatelessWidget {
  const _RcsNotice({required this.app, required this.onFix, required this.onDismiss});
  final String app;
  final VoidCallback onFix;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(4), t.space(1), t.space(4), t.space(2)),
      child: Container(
        padding: EdgeInsets.fromLTRB(t.space(3), t.space(3), t.space(1), t.space(3)),
        decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.radius('lg')), border: Border.all(color: t.color('app-rule'))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: AppIcon(Lucide.triangleAlert, size: 18, color: t.colorOf('#c27c00'))),
          SizedBox(width: t.space(3)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Texts from some people not arriving?', style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink'))),
              SizedBox(height: t.lenOf('0.15rem')),
              Text('If RCS chats were on in $app, people who use RCS are still sending you chats there, not texts. Your old RCS chats are kept there too.', style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'), height: 1.4)),
              SizedBox(height: t.space(2)),
              GlacierPressable(
                onPressed: onFix,
                semanticLabel: 'What to do',
                builder: (context, state) => Text('What to do', style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color(state.pressed ? 'app-ink-3' : 'app-ink')).copyWith(decoration: TextDecoration.underline)),
              ),
            ]),
          ),
          IconTap(icon: Lucide.x, label: 'Dismiss', size: 16, box: t.lenOf('2.25rem'), onPressed: onDismiss),
        ]),
      ),
    );
  }
}

/// One conversation in the list: its face, its name, its last words and when. The Mac's list (lib/desktop) draws its
/// rows with it too.
class ConversationRow extends StatelessWidget {
  const ConversationRow({super.key, required this.conversation, required this.onPress, required this.onLongPress, this.selecting = false, this.selected = false});
  final Conversation conversation;
  final VoidCallback onPress;
  final VoidCallback onLongPress;

  /// Several conversations are being chosen: the face gives way to a tick, and a tap chooses.
  final bool selecting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = conversation;
    final unread = c.unread;
    final face = t.lenOf('3rem');
    return GestureDetector(
      onLongPress: onLongPress,
      child: GlacierPressable(
        onPressed: onPress,
        semanticLabel: selecting ? '${c.title}, ${selected ? 'selected' : 'not selected'}' : null,
        builder: (context, state) => ColoredBox(
          color: selected ? t.colorOf('color-mix(in srgb, #4f5bd5 14%, transparent)') : (state.pressed ? t.color('app-paper-2') : const Color(0x00000000)),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(3)),
            child: Row(
              children: [
                if (selecting)
                  Container(
                    width: face,
                    height: face,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? t.colorOf('#4f5bd5') : const Color(0x00000000),
                      border: Border.all(color: selected ? t.colorOf('#4f5bd5') : t.color('app-ink-4'), width: 2),
                    ),
                    alignment: Alignment.center,
                    child: selected ? const AppIcon(Lucide.check, size: 22, strokeWidth: 2.6, wash: false, color: Color(0xFFFFFFFF)) : null,
                  )
                else
                  Avatar(people: c.people, size: face),
                SizedBox(width: t.space(3)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Row(children: [
                            Flexible(child: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: unread ? 'bold' : 'semibold', color: t.color('app-ink')))),
                            // Texts with this person go sealed (Ghost Messaging's own encryption).
                            if (c.encrypted) ...[
                              SizedBox(width: t.space(1)),
                              Semantics(label: 'Encrypted', child: AppIcon(Lucide.lock, size: 12, strokeWidth: 2.4, wash: false, color: t.color('app-ink-3'))),
                            ],
                          ]),
                        ),
                        if (c.pinned) ...[SizedBox(width: t.space(1)), AppIcon(Lucide.pin, size: 13, color: t.color('app-ink-3'))],
                        if (c.muted) ...[SizedBox(width: t.space(1)), AppIcon(GhostIcons.bellOff, size: 13, color: t.color('app-ink-3'))],
                        if (c.blocked) ...[SizedBox(width: t.space(1)), AppIcon(Lucide.ban, size: 13, color: t.colorOf('#dd3a30'))],
                        SizedBox(width: t.space(2)),
                        Text(listWhen(c.date), style: pageText(t, t.fontSize('xs'), weight: unread ? 'semibold' : 'regular', color: t.color(unread ? 'app-ink' : 'app-ink-3'))),
                      ]),
                      SizedBox(height: t.lenOf('0.15rem')),
                      Row(children: [
                        if (c.error) ...[AppIcon(Lucide.circleAlert, size: 14, color: t.colorOf('#dd3a30')), SizedBox(width: t.space(1))],
                        Expanded(
                          child: Text.rich(
                            c.draft != null && c.draft!.trim().isNotEmpty
                                ? TextSpan(children: [
                                    TextSpan(text: 'Draft: ', style: TextStyle(color: t.colorOf('#dd3a30'), fontWeight: t.weight('medium'))),
                                    TextSpan(text: c.draft!.replaceAll('\n', ' ')),
                                  ])
                                : TextSpan(text: c.error ? 'Not sent' : (reactionSnippet(c.snippet) ?? c.snippet).replaceAll('\n', ' ')),
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
