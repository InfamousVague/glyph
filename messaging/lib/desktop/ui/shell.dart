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
import '../../ui/thread.dart';
import '../desk.dart';
import 'desk_settings.dart';
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
  int? _current;
  StreamSubscription<int>? _changes;
  Timer? _debounce;
  int _reads = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _changes = Sms.instance.changes.stream.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 200), _load);
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final read = ++_reads;
    try {
      final all = await Sms.instance.conversations();
      if (!mounted || read != _reads) return;
      setState(() {
        _all = all;
        _error = null;
      });
    } catch (e) {
      if (!mounted || read != _reads) return;
      setState(() => _error = '$e');
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
  void _show(Widget page, {int? thread}) {
    setState(() => _current = thread);
    _pane.currentState?.pushAndRemoveUntil(_page(page), (r) => r.isFirst);
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
    final archivedCount = (_all ?? const <Conversation>[]).where((c) => c.archived).length;
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
      final tail = !_archived && archivedCount > 0 && _query.isEmpty;
      list = ListView.builder(
        padding: EdgeInsets.only(bottom: t.space(4)),
        itemCount: shown.length + (tail ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == shown.length) {
            return GlacierPressable(
              onPressed: () => setState(() => _archived = true),
              builder: (context, state) => Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter, vertical: t.space(4)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  AppIcon(Lucide.archive, size: 16, color: t.color('app-ink-3')),
                  SizedBox(width: t.space(2)),
                  Text('Archived ($archivedCount)', style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-ink-3'))),
                ]),
              ),
            );
          }
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
            if (_archived) IconTap(icon: Lucide.arrowLeft, label: 'Back to Messages', size: 20, onPressed: () => setState(() => _archived = false)),
            Expanded(child: Text(_archived ? 'Archived' : 'Messages', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xl'), weight: 'bold', color: t.color('app-ink')))),
            IconTap(icon: Lucide.messageSquarePlus, label: 'New message', onPressed: () => _show(const ComposeScreen(key: ValueKey('compose')))),
            IconTap(icon: Lucide.settings, label: 'Settings', onPressed: () => _show(const DeskSettingsScreen(key: ValueKey('settings')))),
            SizedBox(width: t.space(2)),
          ]),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, t.space(2)),
          child: GlacierSearchField(placeholder: _archived ? 'Search archived' : 'Search messages', size: GlacierFieldSize.md, onValueChange: (v) => setState(() => _query = v)),
        ),
        Expanded(child: list),
        // How the phone is connected, and what is waiting for it.
        DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: t.color('app-rule')))),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: gutter, vertical: t.space(3)),
            child: ListenableBuilder(listenable: scope.link, builder: (context, _) => LinkStatus(link: scope.link, waiting: scope.calls.waiting)),
          ),
        ),
      ]),
    );

    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 340, child: side),
        Container(width: 1, color: t.color('app-rule')),
        Expanded(
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
