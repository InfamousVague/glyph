import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/ghost_icons.dart';
import '../art/lucide.g.dart';
import '../kit/fold.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../inbox/scams.dart';
import '../plugins/codes.dart' show CodesPlugin;
import '../plugins/spam.dart' show SpamPlugin;
import '../plugins/list.dart';
import '../plugins/plugin.dart' show MessageFacts, PluginAction, PluginHost, RowLook;
import '../art/lucide_more.dart';
import '../plugins/registry.dart' show PluginSection;
import '../plugins/ui.dart' show FilterButton, MarkAllRead, PluginRow;
import '../reactions.dart';
import '../sms.dart';
import '../summaries.dart';
import 'common.dart';
import 'voice_screen.dart';
import 'hangout_screen.dart';
import '../voice/voice.dart';
import '../voice/channels.dart';
import 'update_banner.dart';
import 'compose.dart';
import 'settings.dart';
import 'shell.dart';
import 'swipe_actions.dart';
import 'inbox_ui.dart';
import '../inbox/inbox.dart';
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
///
/// It is the list of the app's frame (lib/ui/shell.dart), on a phone and on a computer. The way to a new chat, the
/// contacts, the archive and Settings is the frame's pill at the list's foot, as the Mac's sidebar has it (Matt,
/// 2026-11-14: "the mobile app should gain the nav from desktop"); what a row opens goes to the frame's pane, and
/// the conversation open there is marked. Shown with no frame round it (a test of this screen alone) it has New
/// message and Settings in its header and Archived as a row at its foot, and opens pages over itself.
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key, this.archived = false, this.selectAll = false});

  /// The Archived page: the same list, of the conversations put away.
  final bool archived;

  /// The Archived page opens with every conversation in it chosen, for the bar at the top to take them back out or
  /// delete them: asked for from the Archive ring's menu (lib/ui/shell.dart).
  final bool selectAll;

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

  /// The Archived page that opens with everything chosen has chosen it.
  bool _choseAll = false;

  /// What can be seen of the texting app this one replaced (android/.../Arriving.kt), for the note about RCS.
  Arriving _arriving = const Arriving();

  /// Beside Google Messages (SmsStatus.beside): RCS stays on there on purpose, so the notice about it is not shown.
  bool _beside = false;

  bool get _selecting => _selected.isNotEmpty;

  /// The frame this list is in (lib/ui/shell.dart), which opens what the list asks for in its pane; null where the
  /// list is shown alone.
  AppShellState? _shell;

  // --- plugins (lib/plugins) -----------------------------------------------------------------------------------------
  // What the plugins that are switched on add to this list: sections with chips under the search field, how a
  // section's rows look, and what fills the list's slots. All of it is asked of [_plugins]; none of it is decided here.
  late final ListPlugins _plugins = ListPlugins(
    changed: () {
      if (mounted) setState(() {});
    },
    open: (thread) {
      final c = _all?.where((c) => c.id == thread).firstOrNull;
      if (c != null) _open(c);
    },
    refresh: _load,
  );

  /// The section whose chip is chosen; null is the main list.
  String? _section;

  void _back() {
    _look();
    _load();
  }

  @override
  void initState() {
    super.initState();
    // What was open in the pane has closed, or given way to something else: read again, as on coming back to the
    // list from a page.
    _shell = AppShell.maybeOf(context)?..closed.addListener(_back);
    // A summary made comes into its row; who is in a voice channel comes into its.
    Summaries.instance.addListener(_summed);
    Voice.instance.addListener(_summed);
    // Telegram's and Bluesky's chats (lib/inbox): each signed-in network is a tab, and its chats come into it.
    _inbox.addListener(_summed);
    _load();
    _look();
    _changes = Sms.instance.changes.stream.listen((_) {
      _debounce?.cancel();
      // A text came or went: it is among the newest, so only those are read again.
      _debounce = Timer(const Duration(milliseconds: 250), _newest);
    });
  }

  final Listenable _inbox = Inbox.instance.changes;

  void _summed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    Summaries.instance.removeListener(_summed);
    Voice.instance.removeListener(_summed);
    _inbox.removeListener(_summed);
    _shell?.closed.removeListener(_back);
    _plugins.dispose();
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
    if (Sms.remote) return;
    try {
      final s = await Sms.instance.status();
      if (mounted) setState(() => _beside = s.beside);
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
          // Opened to choose them all: once, as they first arrive.
          if (widget.selectAll && !_choseAll) {
            _choseAll = true;
            _selected.addAll(page.items.map((c) => c.id));
          }
        });
        // The number on the pill's Archive follows what is taken back out here.
        _shell?.archived.value = page.items.length;
        return;
      }
      Sms.instance.archivedCount().then((n) {
        if (!mounted || read != _reads) return;
        setState(() => _archived = n);
        _shell?.archived.value = n;
      }).catchError((_) {});
      final seen = <int>{};
      int? at = 0;
      while (at != null) {
        final page = await Sms.instance.conversationsPage(limit: at == 0 ? _first : _lot, offset: at, pinned: at == 0);
        if (!mounted || read != _reads) return;
        seen.addAll(page.items.map((c) => c.id));
        final last = page.next == null;
        _plugins.take(page.items);
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
      _plugins.take(page.items);
      setState(() {
        _all = mergeConversations(_all, page.items);
        _error = null;
      });
    } catch (_) {
      // The list shown stands; the next whole read says what is wrong.
    }
  }

  /// The main list with Telegram's and Bluesky's chats among the texts, newest first, after the pinned conversations
  /// (Matt, 2026-11-15: "Id like the telegram chats to be mixed into the normal text messages (same with bluesky) just
  /// add a telegram icon in thr corner of the bubble"). While older texts are still being read, a chat older than the
  /// oldest text held waits for them, so the list does not jump.
  List<Object> _mixed(List<Conversation> shown) {
    // Codes: a Telegram sign-in code is there among the texted ones (Matt, 2026-11-15: "proxy telegram codes through to
    // the codes tab as well"); any other section is the texts' own.
    final codes = !widget.archived && _codesHost != null;
    // Spam: a chat that looks like a scam is in Spam with spam texts, while the spam filter is on (lib/inbox/scams.dart;
    // Matt, 2026-11-15: "i also want spam filters on them to work and cut out fake romance scams and other telegram
    // scams").
    final spam = !widget.archived && _spamHost != null;
    String? spamOf(InboxChat c) => spam && !(Inbox.instance.named(c.network)?.localList('notspam').contains(c.id) ?? false) ? scamOf(c) : null;
    final q = _query.toLowerCase();
    // Every other kind the filters sort, as a text is (ListPlugins.sort's chats; Matt, 2026-11-16: "Filters should
    // apply to all chats including telegram and signal").
    bool sorted(InboxChat c) => widget.archived || _plugins.showsChat('${c.network}:${c.id}', _section, searching: q.isNotEmpty);
    // In the archive, the networks' archived chats among the archived texts.
    final chats = [
      for (final n in Inbox.instance.ready)
        for (final c in widget.archived ? n.archivedChats : n.shownChats)
          if ((q.isEmpty || c.title.toLowerCase().contains(q) || c.snippet.toLowerCase().contains(q)) &&
              switch (_section) {
                CodesPlugin.section => (codes && inboxCode(c) != null) || sorted(c),
                SpamPlugin.section => spamOf(c) != null || sorted(c),
                _ => !(codes && inboxCode(c) != null) && spamOf(c) == null && sorted(c),
              })
            c,
    ];
    if (chats.isEmpty) return shown;
    if (_section != null) {
      return ([for (final c in shown) (c.date, c as Object), for (final c in chats) (c.date, c as Object)]..sort((a, b) => b.$1.compareTo(a.$1))).map((e) => e.$2).toList();
    }
    bool pinnedChat(InboxChat c) => Inbox.instance.named(c.network)?.isPinned(c) ?? false;
    final pinned = <(DateTime, Object)>[for (final c in shown) if (c.pinned) (c.date, c), for (final c in chats) if (pinnedChat(c)) (c.date, c)]..sort((a, b) => b.$1.compareTo(a.$1));
    final rest = [for (final c in shown) if (!c.pinned) c];
    final oldest = _more && rest.isNotEmpty ? rest.last.date : null;
    final waiting = [for (final c in chats) if (!pinnedChat(c) && (oldest == null || !c.date.isBefore(oldest))) c];
    final merged = <(DateTime, Object)>[for (final c in rest) (c.date, c), for (final c in waiting) (c.date, c)]
      ..sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final m in pinned) m.$2, for (final m in merged) m.$2];
  }

  /// What each signed-in network's chat says of itself, for the filters to sort it with the texts: its newest message,
  /// whether whoever wrote is a contact, a group, unread, muted, and whether the newest message is this account's.
  List<({String key, MessageFacts facts})> _chatFacts() => [
        for (final n in Inbox.instance.ready)
          for (final c in n.shownChats)
            (
              key: '${c.network}:${c.id}',
              facts: MessageFacts(
                thread: ListPlugins.chatThread('${c.network}:${c.id}'),
                senders: [c.title],
                text: c.snippet,
                contact: !c.stranger && !c.service,
                group: c.group,
                date: c.date,
                unread: c.unread > 0,
                muted: c.muted,
                outgoing: c.lastFromMe,
              ),
            ),
      ];

  /// The spam filter's host while it is on: chats that look like scams go to Spam.
  PluginHost? get _spamHost => widget.archived ? null : _plugins.hostFor(context, SpamPlugin.section);

  /// A chat in Spam: why it is there, and Not spam to put it back for good.
  Widget _inboxSpamRow(InboxChat chat, InboxNetwork network, String why, PluginHost host) {
    final c = Conversation(
      id: -(chat.id.hashCode & 0x3fffffff) - 1,
      date: chat.date,
      people: [Person(address: '${chat.network}:${chat.id}', name: chat.title, photo: chat.avatar)],
      snippet: chat.snippet,
      unread: chat.unread > 0,
      error: false,
      archived: false,
    );
    final back = PluginAction(label: 'Not spam', icon: Lucide.check, run: (host) {
      network.setLocal('notspam', chat.id, true);
      host.say('Moved to Messages');
    });
    return PluginRow(conversation: c, look: RowLook(caption: why, word: back), host: host, onPress: () => openInboxChat(context, network, chat), onLongPress: () => openInboxChat(context, network, chat));
  }

  /// The Codes plugin's host while it is on: Telegram's codes go to its tab, and are copied by it.
  PluginHost? get _codesHost => widget.archived ? null : _plugins.hostFor(context, CodesPlugin.section);

  /// A Telegram chat in Codes, drawn as a texted code is: the code large, a tap or the button copies it.
  Widget _inboxCodeRow(InboxChat chat, InboxNetwork network, String code, PluginHost host) {
    final copy = PluginAction(
      label: 'Copy $code',
      icon: Lucide.copy,
      run: (host) async {
        host.copy(code, say: 'Copied $code');
        await network.markRead(chat.id);
      },
    );
    final c = Conversation(
      id: -(chat.id.hashCode & 0x3fffffff) - 1,
      date: chat.date,
      people: [Person(address: '${chat.network}:${chat.id}', name: chat.title, photo: chat.avatar)],
      snippet: chat.snippet,
      unread: chat.unread > 0,
      error: false,
      archived: false,
    );
    return PluginRow(conversation: c, look: RowLook(value: code, end: copy, tap: copy, title: network.name), host: host, onPress: () => openInboxChat(context, network, chat), onLongPress: () => openInboxChat(context, network, chat));
  }

  List<Conversation> get _shown {
    // Pinned conversations first, each group newest first (the order they arrive in).
    final held = (_all ?? const <Conversation>[]).where((c) => c.archived == widget.archived).toList();
    // Plugins: a section's own conversations, the newest first whether pinned or not; else the main list without
    // the ones a section has taken out of it.
    final all = widget.archived ? held : _plugins.pick(held, _section, searching: _query.trim().isNotEmpty);
    final list = _section != null ? all : [...all.where((c) => c.pinned), ...all.where((c) => !c.pinned)];
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

  // --- the tabs --------------------------------------------------------------------------------------------------------

  /// The tab of voice channels (the "tabs" layout).
  static const voiceTab = '*voice';

  /// The voice channels, the live ones first, then by when each last had anyone in it.
  List<VoiceChannel> _voices() {
    final v = Voice.instance;
    final all = [...v.channels];
    int when(VoiceChannel c) => v.lastActive(c)?.millisecondsSinceEpoch ?? 0;
    all.sort((a, b) => when(b).compareTo(when(a)));
    return all;
  }

  /// Hops into [c] and shows it.
  Future<void> _openVoice(VoiceChannel c) async {
    // A hangout opens its page: its chat, who is in it, and a way into voice (lib/ui/hangout_screen.dart).
    // In the conversation's place (Matt, 2026-11-15: "clicking on a voice chat should show me the chat in the normal
    // spot and connected participants with a "join" button").
    if (c.hangout && Voice.instance.session?.channel.room != c.room) {
      final shell = AppShell.maybeOf(context);
      if (shell != null) {
        Voice.instance.view(c);
        shell.go('voice');
      } else {
        push(context, (_) => HangoutScreen(channel: c));
      }
      return;
    }
    try {
      await Voice.instance.join(c);
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t join: $e', tone: GlacierToastTone.danger);
      return;
    }
    if (!mounted) return;
    final shell = AppShell.maybeOf(context);
    if (shell != null) {
      shell.go('voice');
    } else {
      push(context, (_) => const VoiceScreen());
    }
  }

  /// One tab's conversations (null: the main list's), whatever is typed in the search: not the archived ones.
  List<Conversation> _of(String? section) {
    final held = (_all ?? const <Conversation>[]).where((c) => !c.archived).toList();
    return _plugins.pick(held, section, searching: false);
  }

  /// The row under the search field: the tabs as a segmented toggle (Matt, 2026-11-14: "change the messages and
  /// codes to a segmented toggle") and, at its end, the filter. With neither there is no row. Mark all read is at the
  /// end of the title row.
  Widget? _tabsRow(Tokens t) {
    // Messages, codes and voice channels as the toggle's three icons (Matt, 2026-11-15: "use the segmented toggle with
    // the three icons instead of intertwining them remove the other options for now"). Voice is there always: it is
    // where calls are.
    final voices = Voice.instance.channels;
    final tabs = _plugins.tabs(_section, (section) => setState(() => _section = section), onMenu: _tabMenu, extra: [
      (id: voiceTab, icon: LucideMore.headphones, label: 'Spaces', count: voices.where(Voice.instance.live).length),
    ]);
    final kinds = _plugins.kinds;
    if (tabs == null && kinds.isEmpty) return null;
    final only = _section != null && (_section == ListPlugins.hiddenView || kinds.any((k) => k.id == _section));
    return Padding(
      // From the search field's edge, which is the cards' edge too.
      padding: EdgeInsets.fromLTRB(t.space(2), 0, t.space(2), t.space(2)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // As tall as the toggle, which is as tall as the round buttons beside it.
        SizedBox(
          height: MarkAllRead.size(t),
          child: Row(children: [
            Expanded(child: tabs ?? const SizedBox.shrink()),
            if (kinds.isNotEmpty) ...[
              if (tabs != null) SizedBox(width: t.space(2)) else const Spacer(),
              FilterButton(hidden: _plugins.hiddenCount, only: only, rows: (context) => _filterRows(kinds)),
            ],
          ]),
        ),
        // One kind shown alone: which, and the way back to everything.
        if (only)
          Padding(
            padding: EdgeInsets.only(top: t.space(2), left: t.space(2)),
            child: Row(children: [
              Expanded(
                child: Text(_section == ListPlugins.hiddenView ? 'Hidden by the filter' : 'Only ${_plugins.tabName(_section)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-ink-2'))),
              ),
              GlacierPressable(
                onPressed: () => setState(() => _section = null),
                builder: (context, state) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1)),
                  child: Text('Show all', style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color(state.pressed ? 'app-ink-3' : 'app-ink'))),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  /// The filter's menu (Matt, 2026-11-14: "a filter dropdown where showing spam, political messages, and debt
  /// collectors are filtered out by default"; then "Remove the show only toggle and just habe all at the top and each
  /// of these filters get ticked on or off With the icons"): All at the top, and under it each kind of text with its
  /// icon, how many there are, and a tick while it is shown in Messages. A press ticks or unticks it; All ticks every
  /// kind, or, with all ticked, unticks them.
  List<Widget> _filterRows(List<PluginSection> kinds) {
    final app = AppState.of(context);
    final t = context.tokens;
    bool on(PluginSection k) => ListPlugins.kindShown(app, k);
    final others = ListPlugins.othersShownFor(app);
    final all = others && kinds.every(on);
    Widget tick(bool shown) => shown ? AppIcon(Lucide.check, size: 16, color: t.color('app-ink')) : const SizedBox(width: 16, height: 16);
    Widget row(String label, int n, bool shown) => Opacity(
          opacity: shown ? 1 : 0.5,
          child: Row(children: [
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (n > 0) ...[SizedBox(width: t.space(3)), Opacity(opacity: 0.6, child: Text('$n')), SizedBox(width: t.space(2))],
          ]),
        );
    return [
      GlacierMenuItem(
        icon: const AppIcon(Lucide.listFilter, size: 16),
        shortcut: tick(all),
        closes: false,
        ariaLabel: all ? 'All, shown' : 'All',
        onSelect: () {
          for (final k in kinds) {
            app.setFlag('filter_${k.id}', !all);
          }
          app.setFlag(ListPlugins.othersKey, !all);
        },
        child: row('All', 0, true),
      ),
      const GlacierMenuSeparator(),
      // Everything no kind has: personal texts above all (Matt, 2026-11-14: "when only selecting political messages I
      // still see personal messages").
      GlacierMenuItem(
        icon: const AppIcon(LucideMore.messageCircle, size: 16),
        shortcut: tick(others),
        closes: false,
        ariaLabel: 'Personal & other, ${others ? 'shown' : 'hidden'}',
        onSelect: () => app.setFlag(ListPlugins.othersKey, !others),
        child: row('Personal & other', _plugins.othersCount, others),
      ),
      for (final k in kinds)
        GlacierMenuItem(
          icon: AppIcon(k.section.icon, size: 16),
          shortcut: tick(on(k)),
          closes: false,
          ariaLabel: '${k.section.label}, ${on(k) ? 'shown' : 'hidden'}',
          onSelect: () => app.setFlag('filter_${k.id}', !on(k)),
          child: row(k.section.label, _plugins.countOf(k.id), on(k)),
        ),
    ];
  }

  /// Marks every unread conversation of a tab as read: from the button beside the tabs, or a tab's own menu.
  Future<void> _markAllRead(String? section) async {
    final unread = _of(section).where((c) => c.unread).toList();
    // The chats from Telegram and the rest that are in this tab, read there too (Matt, 2026-11-15: "Marking all as read
    // should do the same for telegram chats").
    final saved = _section;
    _section = section;
    final chats = [for (final o in _mixed(const [])) if (o is InboxChat && o.unread > 0) o];
    _section = saved;
    for (final c in chats) {
      unawaited(Inbox.instance.named(c.network)?.markRead(c.id));
    }
    if (unread.isEmpty && chats.isNotEmpty) {
      toast(context, '${chats.length} marked as read');
      return;
    }
    if (unread.isEmpty) {
      toast(context, 'Nothing is unread in ${_plugins.tabName(section)}');
      return;
    }
    // Shown at once: the dots go as the button is let go, not as the phone gets round to each.
    final ids = {for (final c in unread) c.id};
    setState(() => _all = [for (final c in _all ?? const <Conversation>[]) ids.contains(c.id) ? c.copyWith(unread: false) : c]);
    var failed = 0;
    for (final c in unread) {
      try {
        await Sms.instance.markRead(c.id);
      } catch (_) {
        failed++;
      }
    }
    _load();
    if (!mounted) return;
    toast(
      context,
      failed == 0 ? '${_count(unread.length + chats.length)} marked as read' : '${unread.length + chats.length - failed} marked as read; $failed could not be',
      tone: failed == 0 ? GlacierToastTone.neutral : GlacierToastTone.danger,
    );
  }

  /// A tab's menu (Matt, 2026-11-14: "add a right click menu for the codes and messages tabs"): a press with the
  /// other button on it, or a long press where there is no other button.
  void _tabMenu(String? section) {
    if (section == voiceTab || inboxOfTab(section) != null) return;
    final all = _of(section);
    final unread = all.where((c) => c.unread).length;
    final name = _plugins.tabName(section);
    showChoices(context, title: '$name · ${unread == 0 ? 'nothing unread' : '$unread unread'}', choices: [
      Choice('Mark all as read', Lucide.checkCheck, () => _markAllRead(section)),
      // Every conversation of the tab chosen at once, for the bar at the top to archive or delete.
      if (all.isNotEmpty)
        Choice('Select all', Lucide.listChecks, () {
          setState(() {
            _section = section;
            _selected
              ..clear()
              ..addAll(all.map((c) => c.id));
          });
        }),
    ]);
  }

  Future<void> _open(Conversation c) async {
    final shell = _shell;
    if (shell != null) {
      shell.openThread(c.id, c.people);
      return;
    }
    await push<void>(context, (_) => ThreadScreen(thread: c.id, people: c.people));
    _load();
  }

  Future<void> _compose() async {
    final shell = _shell;
    if (shell != null) return shell.compose();
    await push<void>(context, (_) => const ComposeScreen());
    _load();
  }

  void _toggle(Conversation c) => setState(() => _selected.contains(c.id) ? _selected.remove(c.id) : _selected.add(c.id));

  void _menu(Conversation c) {
    showChoices(context, title: c.title, choices: [
      // Plugins: where a tap on the row is a section's own (a code's tap copies it), opening it is offered here.
      if (_section != null && _plugins.look(context, c)?.$1.tap != null) Choice('Open conversation', Lucide.messageSquare, () => _open(c)),
      Choice('Select', Lucide.circleCheck, () => _toggle(c)),
      if (c.unread) Choice('Mark as read', Lucide.checkCheck, () async { await Sms.instance.markRead(c.id); _load(); }),
      // Plugins: their own lines for this conversation ("Not spam").
      if (!widget.archived) ..._plugins.menu(context, c),
      Choice(c.pinned ? 'Unpin' : 'Pin to top', c.pinned ? Lucide.pinOff : Lucide.pin, () => _pin(c)),
      Choice(c.muted ? 'Unmute' : 'Mute notifications', c.muted ? Lucide.bell : GhostIcons.bellOff, () async {
        await Sms.instance.threadFlag('muted', c.id, !c.muted);
        await _load();
        if (mounted) toast(context, c.muted ? 'Notifications on' : 'Muted. Messages still arrive, quietly.');
      }),
      Choice(c.archived ? 'Unarchive' : 'Archive', c.archived ? Lucide.archiveRestore : Lucide.archive, () => _archive(c)),
      // On a computer, blocking and deleting are offered when the phone it is paired with does them for one.
      if (!c.group && c.people.isNotEmpty && Sms.can('setBlocked'))
        Choice(c.blocked ? 'Unblock' : 'Block number', Lucide.ban, () => c.blocked ? _setBlocked(c, false) : _confirmBlock(c), danger: !c.blocked),
      if (Sms.can('deleteThreads')) Choice('Delete conversation', Lucide.trash2, () => _confirmDelete(c), danger: true),
    ]);
  }

  /// What the list holds of one conversation is changed at once, before Android has answered: the row moves as the
  /// finger lets go, not when the read that follows comes back.
  void _patch(int id, Conversation Function(Conversation) change) {
    setState(() => _all = [for (final c in _all ?? const <Conversation>[]) c.id == id ? change(c) : c]);
  }

  /// Archives [c], or takes it back out: from its menu, or by dragging its row to the left.
  Future<void> _archive(Conversation c) async {
    _patch(c.id, (x) => x.copyWith(archived: !c.archived));
    try {
      await Sms.instance.archive(c.id, !c.archived);
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t ${c.archived ? 'unarchive' : 'archive'}: $e', tone: GlacierToastTone.danger);
    }
    _load();
    if (!mounted) return;
    toast(context, c.archived ? 'Moved back to Messages' : 'Archived',
        action: GlacierToastAction(label: 'Undo', onPress: () async {
          _patch(c.id, (x) => x.copyWith(archived: c.archived));
          await Sms.instance.archive(c.id, c.archived);
          _load();
        }));
  }

  /// Pins [c] to the top, or lets it go: from its menu, or by dragging its row to the right.
  Future<void> _pin(Conversation c) async {
    _patch(c.id, (x) => x.copyWith(pinned: !c.pinned));
    try {
      await Sms.instance.threadFlag('pinned', c.id, !c.pinned);
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t ${c.pinned ? 'unpin' : 'pin'}: $e', tone: GlacierToastTone.danger);
    }
    _load();
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

  /// Asks before deleting [c], unless it was [slid] and "Don't ask again" was chosen once (deleteAskOff).
  void _confirmDelete(Conversation c, {bool slid = false}) {
    // A swipe can ask for this where the menu would not offer it: a computer paired with a phone that is behind.
    if (!Sms.can('deleteThreads')) {
      toast(context, 'Update Ghost Messaging on your phone to delete from here.');
      return;
    }
    Future<void> delete() async {
      try {
        await Sms.instance.deleteThread(c.id);
        // Gone from the list at once, where it used to stay until every conversation had been read again.
        if (mounted) setState(() => _all = _all?.where((x) => x.id != c.id).toList());
        if (mounted) toast(context, 'Conversation deleted');
      } catch (e) {
        if (mounted) toast(context, 'Couldn\'t delete: ${e is PlatformException ? (e.message ?? e.code) : e}', tone: GlacierToastTone.danger);
      }
      _load();
    }

    final app = AppState.of(context);
    if (slid && deleteAskOff(app)) {
      delete();
      return;
    }
    showChoices(context, title: 'Delete every message with ${c.title}? This can\'t be undone.', choices: [
      Choice('Delete', Lucide.trash2, delete, danger: true),
      if (slid) dontAskAgainChoice(app, delete),
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
            if (mounted) {
              setState(() {
                _selected.clear();
                _all = _all?.where((x) => !ids.contains(x.id)).toList();
              });
            }
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
    final shell = _shell;
    if (shell != null) return shell.settings(section);
    await push<void>(context, (_) => section == null ? const SettingsScreen() : SettingsSectionScreen(section));
    _look();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = AppState.of(context);
    // Plugins: given the person's choices, then asked which section each conversation is in. A section that has
    // emptied gives way to the main list.
    if (!widget.archived) {
      _plugins.bind(app);
      // The filter: which kinds of text Messages shows, as the person chose or as each kind starts.
      _plugins.shown = (k) => ListPlugins.kindShown(app, k);
      _plugins.othersShown = () => ListPlugins.othersShownFor(app);
    }
    final sorted = _plugins.sort(widget.archived ? null : _all, chats: widget.archived ? const [] : _chatFacts());
    final voices = widget.archived ? const <VoiceChannel>[] : _voices();
    final inbox = widget.archived ? null : inboxOfTab(_section);
    if (!sorted.has(_section) && !(_section == ListPlugins.hiddenView && _plugins.hiddenCount > 0) && !(_section == voiceTab && !widget.archived) && inbox?.state != InboxState.ready) _section = null;
    final shown = _shown;
    // What the list holds: conversations, the voice channels in their tab, or a network's chats in its.
    final List<Object> rows = inbox != null && inbox.state == InboxState.ready
        ? [for (final c in inbox.chats) if (_query.isEmpty || c.title.toLowerCase().contains(_query.toLowerCase()) || c.snippet.toLowerCase().contains(_query.toLowerCase())) c]
        : _section == voiceTab
            ? voices
            : _mixed(shown);
    // Android's own count, where it has answered: the ones held are not all of them until the read ends.
    final archivedCount = widget.archived ? 0 : (_more ? _archived : (_all ?? const <Conversation>[]).where((c) => c.archived).length) + Inbox.instance.ready.fold<int>(0, (n, net) => n + net.archivedChats.length);
    // Older conversations still arriving: said at the foot of the list, and in place of "Nothing found".
    final more = _more && !widget.archived;
    final gutter = t.space(4);
    // Texts from people who use RCS may still be going to the app this one replaced: said until it is dismissed.
    final notice = !widget.archived && _query.isEmpty && !_selecting && _section == null && _arriving.rcsLikely && !_beside && app.flag('rcs_notice');
    // The conversation open in the pane, and whether that is beside the list: its row is marked for it there.
    final open = AppShell.threadOf(context);
    final beside = AppShell.wideOf(context) ? open : null;
    final status = AppShell.statusOf(context);
    final framed = _shell != null;

    Widget body;
    if (_all == null) {
      body = const Center(child: GhostSpinner(size: 28, label: 'Loading your conversations…'));
    } else if (_error != null && rows.isEmpty) {
      body = ListView(padding: EdgeInsets.fromLTRB(gutter, t.space(10), gutter, 0), children: [
        SettingsEmpty(
          icon: AppIcon(Lucide.circleAlert, size: 28, color: t.colorOf('#dd3a30')),
          title: 'Couldn\'t read your messages',
          body: Text('Android didn\'t hand them over: $_error\nNothing has been deleted. They are still in Android\'s store.'),
          action: SettingsEmptyAction('Try again', _load),
        ),
      ]);
    } else if (rows.isEmpty && inbox != null) {
      body = ListView(padding: EdgeInsets.fromLTRB(gutter, t.space(10), gutter, 0), children: [inboxEmpty(context, inbox)]);
    } else if (rows.isEmpty && _section == voiceTab) {
      body = ListView(padding: EdgeInsets.fromLTRB(gutter, t.space(10), gutter, 0), children: [
        SettingsEmpty(
          icon: AppIcon(LucideMore.headphones, size: 28, color: t.color('app-ink-3')),
          title: 'No spaces yet',
          body: const Text('Every group of friends has its own space. Start one with the new button, then share it with friends or by a link.'),
        ),
      ]);
    } else if (rows.isEmpty) {
      final rcs = _query.isEmpty && !widget.archived && _arriving.rcsLikely;
      body = ListView(padding: EdgeInsets.fromLTRB(gutter, t.space(10), gutter, 0), children: [
        SettingsEmpty(
          // The app's own mark, as it is on the home screen (Matt, 2026-11-14: "I also want the ghost image used
          // when there are no messages to use the logo"), where a drawn outline of a ghost stood.
          icon: const GhostLogo(),
          title: _query.isNotEmpty ? (more ? 'Nothing found yet' : 'Nothing found') : (widget.archived ? 'Nothing archived' : 'No conversations yet'),
          body: Text(_query.isNotEmpty
              ? (more ? 'Older conversations are still being read. Nothing so far matches "$_query".' : 'No name, number or message matches "$_query".')
              : widget.archived
                  ? 'Conversations you archive wait here.'
                  : rcs
                      ? 'There are no texts in Android\'s store. Chats that were RCS in ${_arriving.app} stay in that app, where no other app can read them: they are not deleted.'
                      : framed
                          ? 'Start one with New chat, the first button below.'
                          : 'Start one with the new message button at the top.'),
          action: rcs ? SettingsEmptyAction('What to do', () => _settings('android')) : null,
        ),
      ]);
    } else {
      final extras = (notice ? 1 : 0);
      // In the frame the way to the archive is the pill's ring, with its number.
      final tail = !framed && !widget.archived && archivedCount > 0 && _query.isEmpty && !_selecting && _section == null;
      // What the filter hides, said at the list's foot with the way to see it: nothing is lost quietly.
      final hiddenNow = !widget.archived && _query.isEmpty && !_selecting && _section == null ? _plugins.hiddenCount : 0;
      final foot = hiddenNow > 0;
      body = RefreshableList(
        onRefresh: _load,
        itemCount: extras + rows.length + (foot ? 1 : 0) + (tail ? 1 : 0) + (more ? 1 : 0) + 1,
        itemBuilder: (context, i) {
          if (notice && i == 0) {
            return _RcsNotice(app: _arriving.app, onFix: () => _settings('android'), onDismiss: () => app.setFlag('rcs_notice', false));
          }
          final at = i - extras;
          if (at < rows.length && rows[at] is InboxChat) {
            final chat = rows[at] as InboxChat;
            final network = inbox ?? Inbox.instance.named(chat.network);
            if (network == null) return const SizedBox.shrink();
            final code = _section == CodesPlugin.section ? inboxCode(chat) : null;
            final codesHost = code == null ? null : _codesHost;
            final why = _section == SpamPlugin.section ? scamOf(chat) : null;
            final spamHost = why == null ? null : _spamHost;
            final pinned = network.isPinned(chat);
            // Slid as a conversation of texts is (Matt, 2026-11-15: "Don't use a press and hold menu on telegram chats
            // use the same slide solution normal messages use"): left archives, further deletes (asked first), right
            // pins, each on the network itself where it can.
            return SwipeActions(
              key: ValueKey('swipe-inbox-${chat.network}-${chat.id}'),
              enabled: !_selecting,
              archiveLabel: widget.archived ? 'Unarchive' : 'Archive',
              archiveIcon: widget.archived ? Lucide.archiveRestore : Lucide.archive,
              pinLabel: pinned ? 'Unpin' : 'Pin',
              pinIcon: pinned ? Lucide.pinOff : Lucide.pin,
              onArchive: () => network.archive(chat.id, !widget.archived),
              onDelete: () => confirmInboxDelete(context, network, chat, slid: true),
              onPin: () => network.pin(chat.id, !pinned),
              card: (inset: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.lenOf('0.1875rem')), radius: t.lenOf('1rem')),
              child: code != null && codesHost != null
                  ? _inboxCodeRow(chat, network, code, codesHost)
                  : why != null && spamHost != null
                  ? _inboxSpamRow(chat, network, why, spamHost)
                  : InboxChatRow(
                      key: ValueKey('inbox-${chat.network}-${chat.id}'),
                      chat: chat,
                      onPress: () => openInboxChat(context, network, chat),
                    ),
            );
          }
          if (at < rows.length && rows[at] is VoiceChannel) {
            final v = rows[at] as VoiceChannel;
            return VoiceRow(key: ValueKey('voice-${v.room}'), channel: v, onPress: () => _openVoice(v));
          }
          if (at < rows.length) {
            // The one that is open is being read: its row does not say unread, however it came to be opened (a
            // tap here, a notification, another app's "text this number").
            final held = rows[at] as Conversation;
            final c = held.id == open && held.unread ? held.copyWith(unread: false) : held;
            // Plugins: in a section, the row is drawn as the section's plugin describes it (a code large, with Copy).
            final look = _section == null ? null : _plugins.look(this.context, c);
            final selected = _selecting ? _selected.contains(c.id) : c.id == beside;
            // Dragged left it archives, further it deletes (asked first), right it pins: lib/ui/swipe_actions.dart.
            return SwipeActions(
              key: ValueKey('swipe-${c.id}'),
              enabled: !_selecting,
              archiveLabel: c.archived ? 'Unarchive' : 'Archive',
              archiveIcon: c.archived ? Lucide.archiveRestore : Lucide.archive,
              pinLabel: c.pinned ? 'Unpin' : 'Pin',
              pinIcon: c.pinned ? Lucide.pinOff : Lucide.pin,
              onArchive: () => _archive(c),
              onDelete: () => _confirmDelete(c, slid: true),
              onPin: () => _pin(c),
              // The cards' shape, as ConversationRow and PluginRow draw it: the actions show inside it.
              card: (inset: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.lenOf('0.1875rem')), radius: t.lenOf('1rem')),
              child: look != null
                  ? PluginRow(conversation: c, look: look.$1, host: look.$2, selecting: _selecting, selected: selected, onPress: () => _selecting ? _toggle(c) : _open(c), onLongPress: () => _selecting ? _toggle(c) : _menu(c))
                  : ConversationRow(
                      conversation: c,
                      // Unread texts summed up by the phone's own model, made as the row is first shown.
                      summary: widget.archived ? null : (Summaries.instance..want(c)).of(c),
                      selecting: _selecting,
                      selected: selected,
                      onPress: () => _selecting ? _toggle(c) : _open(c),
                      onLongPress: () => _selecting ? _toggle(c) : _menu(c),
                    ),
            );
          }
          if (foot && at == rows.length) {
            return GlacierPressable(
              onPressed: () => setState(() => _section = ListPlugins.hiddenView),
              semanticLabel: '$hiddenNow hidden by the filter. Show them.',
              builder: (context, state) => Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter, vertical: t.space(4)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  AppIcon(LucideMore.funnel, size: 15, color: t.color(state.pressed ? 'app-ink-4' : 'app-ink-3')),
                  SizedBox(width: t.space(2)),
                  Text('$hiddenNow hidden · Show', style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color(state.pressed ? 'app-ink-4' : 'app-ink-3'))),
                ]),
              ),
            );
          }
          if (tail && at == rows.length + (foot ? 1 : 0)) {
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
          if (more && at == rows.length + (foot ? 1 : 0) + (tail ? 1 : 0)) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: t.space(4)),
              child: const Center(child: GhostSpinner(size: 18, label: 'Loading older conversations…')),
            );
          }
          // Clear of the bar at the foot of the phone's screen, and of the frame's pill floating over the list's end.
          return SizedBox(height: MediaQuery.paddingOf(context).bottom + (framed ? AppShell.pillRoom(context) : t.space(4)));
        },
      );
    }

    final page = GhostPage(
      title: widget.archived ? 'Archived' : 'Messages',
      back: widget.archived && !_selecting,
      // A newer version waiting: above the title and the search (Matt, 2026-11-14: "move the update banner on desktop
      // and mobile to show at the top of the sidebar above where it says messages and has the search bar").
      top: widget.archived ? null : const UpdateCard(),
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
          if (Sms.can('deleteThreads')) IconTap(icon: Lucide.trash2, label: 'Delete', color: t.colorOf('#dd3a30'), onPressed: _confirmDeleteSelected),
        ] else if (!widget.archived) ...[
          // Plugins: their buttons for the list's header, in the frame and out of it.
          ..._plugins.header(context, ListPlace(section: _section, shown: shown.length, groups: _plugins.groups(_all ?? const []))),
          // Mark all read for the tab shown, at the title row's end (Matt, 2026-11-14: "make the mark all read aligned
          // to the right of the messages title row instead of next to the filter").
          Padding(
            padding: EdgeInsets.only(left: t.space(1)),
            child: MarkAllRead(unread: _of(_section).where((c) => c.unread).length, onPress: () => _markAllRead(_section)),
          ),
          // Shown alone, with no frame and so no pill: the two it would hold.
          if (!framed) IconTap(icon: Lucide.messageSquarePlus, label: 'New message', onPressed: _compose),
          if (!framed) IconTap(icon: Lucide.settings, label: 'Settings', onPressed: _settings),
        ],
      ],
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // As wide as the cards under it, edge to edge with them.
              Padding(
                padding: EdgeInsets.fromLTRB(t.space(2), 0, t.space(2), t.space(2)),
                child: GlacierSearchField(
                  placeholder: widget.archived ? 'Search archived' : 'Search messages',
                  size: GlacierFieldSize.md,
                  onValueChange: (v) => setState(() => _query = v),
                ),
              ),
              // What the frame keeps under the search: on a computer, how the phone is connected.
              if (status != null) Padding(padding: EdgeInsets.fromLTRB(gutter, 0, gutter, t.space(2)), child: status),
              // The tabs: "Messages" and each section that has conversations in it, as one toggle, and beside them
              // the button that marks the tab shown as read (_tabsRow).
              if (!widget.archived && !_selecting) ?_tabsRow(t),
              // The search is this page's header too.
              const HeaderEnd(),
              // A read of Android's store that is taking a moment: a thin bar, where the list already shows.
              SizedBox(
                height: 3,
                child: _slow && _all != null ? const GlacierProgressBar(indeterminate: true, ariaLabel: 'Loading your conversations') : null,
              ),
              // Plugins: what they put between the search field and the list.
              if (!widget.archived)
                ..._plugins.above(
                  context,
                  ListPlace(section: _section, shown: shown.length, counts: _plugins.counts, unread: _plugins.unreadSections, show: (section) => setState(() => _section = section)),
                ),
              Expanded(child: body),
            ],
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
  const ConversationRow({super.key, required this.conversation, required this.onPress, required this.onLongPress, this.selecting = false, this.selected = false, this.summary, this.badge});
  final Conversation conversation;

  /// A mark on the face's corner: the network a chat from Telegram or Bluesky is on (lib/ui/inbox_ui.dart).
  final Widget? badge;

  /// What its unread texts come to, in a line, by the phone's own model (lib/summaries.dart): shown in place of the
  /// last words, marked as a summary.
  final String? summary;
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
      // A press with the other button, as a computer's lists have it, where a phone has a long press.
      onSecondaryTap: onLongPress,
      child: GlacierPressable(
        onPressed: onPress,
        semanticLabel: selecting ? '${c.title}, ${selected ? 'selected' : 'not selected'}' : null,
        // Each conversation is a card, and the one chosen (the one open on a computer, the ones ticked on a phone)
        // wears a line round it in the page's ink, white on the dark page (Matt, 2026-11-14: "I don't like the style
        // of selected messages having the light blue background, instead make each in cards so the card can have a
        // 2px white outline for selected chats with rounded borders"). The line's room is always kept, so choosing
        // one moves nothing.
        builder: (context, state) => Padding(
          padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.lenOf('0.1875rem')),
          child: Container(
            decoration: BoxDecoration(
              color: t.color(state.pressed ? 'app-paper-3' : 'app-paper-2'),
              borderRadius: BorderRadius.circular(t.lenOf('1rem')),
              border: Border.all(color: selected ? t.color('app-ink') : const Color(0x00000000), width: 2),
            ),
            padding: EdgeInsets.symmetric(horizontal: t.space(3) - 2, vertical: t.space(3) - 2),
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
                else if (badge != null)
                  SizedBox.square(
                    dimension: face,
                    child: Stack(clipBehavior: Clip.none, children: [
                      Avatar(people: c.people, size: face),
                      Positioned(
                        right: -3,
                        bottom: -3,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: t.color(state.pressed ? 'app-paper-3' : 'app-paper-2')),
                          child: badge,
                        ),
                      ),
                    ]),
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
                                : summary != null && !c.error
                                    // A summary, as Apple marks one: the model's mark, then its line.
                                    ? TextSpan(children: [
                                        WidgetSpan(
                                          alignment: PlaceholderAlignment.middle,
                                          child: Padding(
                                            padding: EdgeInsets.only(right: t.space(1)),
                                            child: Semantics(label: 'Summary', child: AppIcon(Lucide.sparkles, size: 13, strokeWidth: 2.2, wash: false, color: t.color('app-ink-2'))),
                                          ),
                                        ),
                                        TextSpan(text: summary),
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
