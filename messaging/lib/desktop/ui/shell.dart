import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/ghost_icons.dart';
import '../../kit/fold.dart';
import '../../kit/settings_kit.dart';
import '../../kit/settings_type.dart';
import '../../sms.dart';
import '../../ui/common.dart';
import '../../ui/compose.dart';
import '../../ui/conversations.dart';
import '../../ui/nav_bar.dart';
import '../../ui/thread.dart';
import '../desk.dart';
import 'desk_settings.dart';
import '../../ui/contacts.dart';
import '../../ui/update_banner.dart';
import 'wizard.dart';

/// The Mac's window once paired: the conversations down the side, the one chosen beside them. The conversation, the
/// new-message page and the list's rows are the phone's own screens (lib/ui), asking the phone over the link where
/// they ask Android on the phone (lib/desktop/remote.dart).
class DeskShell extends StatefulWidget {
  const DeskShell({super.key});

  @override
  State<DeskShell> createState() => _DeskShellState();
}

class _DeskShellState extends State<DeskShell> {
  final _pane = GlobalKey<NavigatorState>();
  List<Conversation>? _all;
  String? _error;
  String _query = '';
  bool _archived = false;
  int _archivedCount = 0;
  int? _current;

  /// What the pane beside the list shows when it is not a conversation: 'new' (a new message), 'contacts' (the
  /// address book) or 'settings'. It is
  /// the navigation bar's item then; with a conversation or nothing there, the list's own (Messages or Archive) is.
  String? _showing;
  StreamSubscription<int>? _changes;
  Timer? _debounce;
  int _reads = 0;

  /// A whole read is under way, and something changed meanwhile: the newest are read again once it ends.
  bool _reading = false;
  bool _stale = false;

  /// The first lot, which fills the list a few times over, and each lot after it: as the phone's own list reads
  /// them (lib/ui/conversations.dart), so a phone with thousands shows its newest here at once.
  static const _first = 40;
  static const _lot = 250;

  @override
  void initState() {
    super.initState();
    _load();
    _changes = Sms.instance.changes.stream.listen((thread) {
      _debounce?.cancel();
      // A text came or went: it is among the newest, so only those are read again. -1 is "anything may have
      // changed" (the phone is back, a pin, an archive): the whole list.
      _debounce = Timer(const Duration(milliseconds: 200), thread < 0 ? _load : _newest);
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  /// Reads the conversations from the phone, the newest first: the first lot and the pinned ones at once, then the
  /// rest a lot at a time behind them. What the whole read did not find has gone.
  Future<void> _load() async {
    final read = ++_reads;
    _reading = true;
    try {
      Sms.instance.archivedCount().then((n) {
        if (mounted && read == _reads) setState(() => _archivedCount = n);
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
        });
        at = page.next;
      }
      // The archived ones are asked for by name: they may lie anywhere among thousands.
      final archived = await Sms.instance.conversationsPage(archived: true);
      if (!mounted || read != _reads) return;
      setState(() => _all = mergeConversations(_all, archived.items));
    } catch (e) {
      if (!mounted || read != _reads) return;
      setState(() => _error = '$e');
    } finally {
      if (read == _reads) {
        _reading = false;
        if (_stale && mounted) {
          _stale = false;
          _newest();
        }
      }
    }
  }

  /// Reads the newest conversations again and lays them over the ones held: what a text that has just come or gone
  /// changes.
  Future<void> _newest() async {
    if (_all == null) return _load();
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
      // The list shown stands.
    }
  }

  List<Conversation> get _shown {
    final all = (_all ?? const <Conversation>[]).where((c) => c.archived == _archived).toList();
    final list = [...all.where((c) => c.pinned), ...all.where((c) => !c.pinned)];
    if (_query.trim().isEmpty) return list;
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

  PageRouteBuilder<void> _page(Widget page) => PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 140),
        reverseTransitionDuration: const Duration(milliseconds: 100),
        pageBuilder: (context, _, _) => page,
        transitionsBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
      );

  /// Shows [page] in the pane beside the list, in place of whatever was there.
  void _show(Widget page, {int? thread, String? showing}) {
    setState(() {
      _current = thread;
      _showing = showing;
    });
    _pane.currentState?.pushAndRemoveUntil(_page(page), (r) => r.isFirst);
  }

  /// The navigation bar at the sidebar's foot (nav_bar.dart): a new message and Settings open beside the list;
  /// Messages and Archive are the list itself, and put away a new message or Settings that was open.
  void _go(String id) {
    switch (id) {
      case 'new':
        _show(const ComposeScreen(key: ValueKey('compose')), showing: 'new');
      case 'settings':
        _show(const DeskSettingsScreen(key: ValueKey('settings')), showing: 'settings');
      case 'contacts':
        _show(const ContactsScreen(key: ValueKey('contacts')), showing: 'contacts');
      default:
        final wasBeside = _showing != null;
        setState(() {
          _archived = id == 'archive';
          _showing = null;
          if (wasBeside) _current = null;
        });
        if (wasBeside) _pane.currentState?.popUntil((r) => r.isFirst);
    }
  }

  void _open(Conversation c) => _show(ThreadScreen(key: ValueKey('thread-${c.id}'), thread: c.id, people: c.people), thread: c.id);

  Future<void> _try(Future<void> Function() what) async {
    try {
      await what();
    } catch (e) {
      final context = _pane.currentContext;
      if (context != null && context.mounted) toast(context, '$e', tone: GlacierToastTone.danger);
    }
    _load();
  }

  void _menu(Conversation c) {
    final context = _pane.currentContext;
    if (context == null) return;
    showChoices(context, title: c.title, choices: [
      if (c.unread) Choice('Mark as read', Lucide.checkCheck, () => _try(() => Sms.instance.markRead(c.id))),
      Choice(c.pinned ? 'Unpin' : 'Pin to top', c.pinned ? Lucide.pinOff : Lucide.pin, () => _try(() => Sms.instance.threadFlag('pinned', c.id, !c.pinned))),
      Choice(c.muted ? 'Unmute' : 'Mute notifications on the phone', c.muted ? Lucide.bell : GhostIcons.bellOff, () => _try(() => Sms.instance.threadFlag('muted', c.id, !c.muted))),
      Choice(c.archived ? 'Unarchive' : 'Archive', c.archived ? Lucide.archiveRestore : Lucide.archive, () => _try(() => Sms.instance.archive(c.id, !c.archived))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scope = DeskScope.of(context);
    final shown = _shown;
    final archivedCount = _archivedCount;
    final gutter = t.space(4);

    Widget list;
    if (_all == null) {
      list = Center(
        child: _error == null
            ? const GhostSpinner(size: 26, label: 'Reading your conversations from the phone…')
            : Padding(
                padding: EdgeInsets.all(t.space(6)),
                child: SettingsEmpty(
                  icon: AppIcon(Lucide.smartphone, size: 28, color: t.color('app-ink-3')),
                  title: 'Waiting for your phone',
                  body: const Text('Your conversations appear when the phone is reached. Texts are not kept on this Mac, so there is nothing to show until then.'),
                  action: SettingsEmptyAction('Look again', () {
                    scope.link.look();
                    _load();
                  }),
                ),
              ),
      );
    } else if (shown.isEmpty) {
      list = Padding(
        padding: EdgeInsets.all(t.space(6)),
        child: SettingsEmpty(
          icon: AppIcon(Lucide.ghost, size: 28, color: t.color('app-ink-3')),
          title: _query.isNotEmpty ? 'Nothing found' : (_archived ? 'Nothing archived' : 'No conversations yet'),
          body: Text(_query.isNotEmpty ? 'No name, number or message matches "$_query".' : 'Conversations on the phone appear here.'),
        ),
      );
    } else {
      list = ListView.builder(
        // Its last card clears the navigation bar floating over its end.
        padding: EdgeInsets.only(bottom: NavPill.clearance(t)),
        itemCount: shown.length,
        itemBuilder: (context, i) {
          final c = shown[i];
          // A press with the other button, as a Mac's lists have it, where a phone has a long press.
          return GestureDetector(
            onSecondaryTap: () => _menu(c),
            child: ConversationRow(conversation: c, selected: c.id == _current, onPress: () => _open(c), onLongPress: () => _menu(c)),
          );
        },
      );
    }

    final side = ColoredBox(
      color: t.color('glacier-bg'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: t.lenOf('3.5rem'),
          child: Row(children: [
            SizedBox(width: gutter),
            Expanded(child: Text(_archived ? 'Archived' : 'Messages', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xl'), weight: 'bold', color: t.color('app-ink')))),
            SizedBox(width: gutter),
          ]),
        ),
        // As wide as the cards under it, edge to edge with them (Matt, 2026-11-14: "the search bar at the top is not
        // full width it has too much padding on the left and right").
        Padding(
          padding: EdgeInsets.fromLTRB(t.space(2), 0, t.space(2), t.space(2)),
          child: GlacierSearchField(placeholder: _archived ? 'Search archived' : 'Search messages', size: GlacierFieldSize.md, onValueChange: (v) => setState(() => _query = v)),
        ),
        // How the phone is connected, and what is waiting for it: over the list, since its foot is the bar's.
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, t.space(2)),
          child: ListenableBuilder(listenable: scope.link, builder: (context, _) => LinkStatus(link: scope.link, waiting: scope.calls.waiting)),
        ),
        Expanded(
          child: Stack(children: [
            Positioned.fill(child: list),
            // The navigation bar floats over the list's end (Matt, 2026-11-14: "at the bottom of the desktop
            // sidebar, add a navigation bar floating from glacier UI include the new chat button, messages,
            // settings button and archive").
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: NavPill(
                active: _showing ?? (_archived ? 'archive' : 'messages'),
                onSelect: _go,
                items: [
                  const NavItem(id: 'new', icon: Lucide.messageSquarePlus, label: 'New chat'),
                  const NavItem(id: 'messages', icon: Lucide.messageSquare, label: 'Messages'),
                  // The address book: the phone's contacts, and a press on one opens its conversation.
                  const NavItem(id: 'contacts', icon: Lucide.contactRound, label: 'Contacts'),
                  NavItem(id: 'archive', icon: Lucide.archive, label: 'Archive', count: archivedCount),
                  const NavItem(id: 'settings', icon: Lucide.settings, label: 'Settings'),
                ],
              ),
            ),
          ]),
        ),
      ]),
    );

    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 340, child: side),
        Container(width: 1, color: t.color('app-rule')),
        Expanded(
          // The phone's own update banner, over the pane and under its page's header (lib/ui/update_banner.dart).
          child: UpdateBanner(
          // The phone's screens measure themselves against the screen they are on: here that is the pane.
          child: LayoutBuilder(
            builder: (context, box) => MediaQuery(
              data: MediaQuery.of(context).copyWith(size: Size(box.maxWidth, box.maxHeight)),
              child: Navigator(
                key: _pane,
                onGenerateRoute: (_) => _page(const _Nothing()),
              ),
            ),
          ),
          ),
        ),
      ]),
    );
  }
}

/// The pane before a conversation is chosen.
class _Nothing extends StatelessWidget {
  const _Nothing();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final scope = DeskScope.of(context);
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Center(
        child: ListenableBuilder(
          listenable: scope.link,
          builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(Lucide.ghost, size: 40, color: t.color('app-ink-4')),
            SizedBox(height: t.space(3)),
            Text('Choose a conversation', style: pageText(t, t.fontSize('lg'), weight: 'semibold', color: t.color('app-ink-2'))),
            SizedBox(height: t.space(1)),
            Text(
              scope.link.phone == null ? '' : 'Paired with ${scope.link.phone!.name}. What you send goes through it, sealed between the two.',
              textAlign: TextAlign.center,
              style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')),
            ),
          ]),
        ),
      ),
    );
  }
}
