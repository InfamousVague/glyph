import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../me/me.dart';
import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_type.dart';
import '../sms.dart';
import 'common.dart';
import 'compose.dart';
import 'contacts.dart';
import 'conversations.dart';
import 'nav_bar.dart';
import 'settings.dart';
import 'settings_panes.dart' show settingsGroupLabel, settingsSections;
import 'thread.dart';

/// The app's one frame, on the phone and on a computer alike (Matt, 2026-11-14: "Unify the UI experience to match on
/// desktop and mac as well the desktop app should get all featues its missing from mobile and thr mobile app should
/// gain the nav from desktop").
///
/// The list of conversations (lib/ui/conversations.dart) and, beside it, a pane for what is opened from it: a
/// conversation, a new message, Settings. In a window [wideAt] wide or wider (a computer's, a tablet's, a folding
/// phone opened out) both are on the screen, the list down the side as the Mac's first had it; the conversation
/// open is marked in the list and draws no way back, since there is nowhere to go back to. In a narrower one (a
/// phone, a folding phone's cover) the list is the screen and what is opened slides over it, with its way back.
///
/// It is the same list and the same pane either way, each kept where it is as the window changes: a conversation
/// open on a folding phone's cover, a message half written in it, is still open and half written when the phone is
/// opened out, with the list now beside it.
///
/// Both are navigators. What a page in the pane opens (a contact's page, a picture, a sheet) opens over it in the
/// pane; the Archived list opens over the list in the list's place. Android's back closes what is in the pane
/// first, then goes back in the list, then leaves the app.
///
/// The way round is the pill floating at the list's foot (lib/ui/nav_bar.dart), the one the Mac's sidebar has: a
/// new chat, the messages, the contacts, the archive with how many are in it, Settings. A new chat and the contacts
/// open in the pane; Messages, Archive and Settings are the list's place itself: the conversations, the archived
/// ones, or Settings' sections, with the page of the section chosen in the pane.
///
/// On a wide phone (a folding phone opened out, a tablet) the pill is not at the list's foot: it stands up at the
/// foot of a strip of its own down the window's right, as Ghost.md's dock does there (Matt, 2026-11-14: "on wider
/// phones like my fold 8 make the navbar render vertically condensed on the right of the screen like we do in ghost
/// markdown"). Ghost.md's floats over its page; here it is given the strip, [NavPill.railWidth] wide, and the pane
/// ends where the strip begins, because a conversation's Send button and its newest messages are in the very corner
/// a floating one would cover. A computer keeps the pill along its sidebar's foot, as Matt asked for there.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.status, this.nothing, this.paneObservers = const []});

  /// Kept under the list's search field: on a computer, how the phone is connected.
  final Widget? status;

  /// What the pane says while nothing is open in it and the window is wide. "Choose a conversation" where not given.
  final WidgetBuilder? nothing;

  /// Told of the pages that open in the pane: the look for a newer version (lib/ui/update_banner.dart).
  final List<NavigatorObserver> paneObservers;

  /// How wide a window is, in logical pixels, before the list and the pane stand side by side. A phone held
  /// upright is 360 to 430; a folding phone opened out is 700 or more.
  static const wideAt = 640.0;

  /// How much of a wide window the list takes: as the Mac's has it, less where the window is only just wide.
  static double sideWidth(double width) => (width * 0.4).clamp(280.0, 340.0);

  /// The shell this page is in, to open things with; null on a page shown with none (a test of one screen).
  static AppShellState? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<_ShellScope>()?.shell;

  /// Whether the list and the pane are side by side. The page asking is built again when that changes.
  static bool wideOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ShellScope>()?.wide ?? false;

  /// Whether the pill stands up at the window's right, not along the list's foot: a wide phone's window, tall
  /// enough for it. The page asking is built again when that changes.
  static bool railOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ShellScope>()?.rail ?? false;

  /// How much of its end a list in the list's place leaves clear for the pill: the pill's own height and room
  /// where it floats there, a step where it stands at the window's right instead.
  static double pillRoom(BuildContext context) => railOf(context) ? context.tokens.space(4) : NavPill.clearance(context.tokens);

  /// The conversation open in the pane, or null. The page asking is built again when that changes.
  static int? threadOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_ShellScope>()?.thread;

  /// What is kept under the list's search field ([status]), or null.
  static Widget? statusOf(BuildContext context) => context.getInheritedWidgetOfExactType<_ShellScope>()?.shell.widget.status;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  final _pane = GlobalKey<NavigatorState>();
  final _side = GlobalKey<NavigatorState>();

  /// The page open in the pane, and the conversation it is where it is one. Null: nothing is open.
  PageRouteBuilder<void>? _open;
  int? _thread;

  /// Which of the pill's rings the pane's page is, where it is one: 'new', 'contacts' or 'settings'.
  String? _showing;

  /// The Archived list, while it is open in the list's place.
  Route<void>? _archive;
  bool get _archivedOpen => _archive != null;

  /// Settings' list of sections, while it is open in the list's place (Matt, 2026-11-14: "when the settings is open
  /// on desktop replace the normal sidebar so it's only a two pane layout not a three pane"): the page of the
  /// section chosen is the pane's, beside it in a wide window and over it on a phone.
  Route<void>? _settings;

  /// Whether Settings is open in the list's place.
  bool get settingsOpen => _settings != null;

  /// The section of Settings whose page is in the pane, or null: the row Settings' list marks.
  final settingsSection = ValueNotifier<String?>(null);

  /// How many conversations are archived, as the list last counted them: the number on the pill's Archive.
  final archived = ValueNotifier<int>(0);

  bool _wide = false;

  /// Whether Android's back has something to close in the pane, and something to go back from in the list.
  bool _paneBack = false;
  bool _sideBack = false;

  /// Told each time the pane's page closes or gives way to another: the list reads its conversations again, as it
  /// did on a phone whenever a conversation was come back from.
  final closed = ValueNotifier<int>(0);

  /// The conversation open in the pane, or null.
  int? get thread => _thread;

  /// Whether the list and the pane are side by side.
  bool get wide => _wide;

  @override
  void dispose() {
    closed.dispose();
    archived.dispose();
    settingsSection.dispose();
    super.dispose();
  }

  PageRouteBuilder<void> _route(Widget page) => PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, _, _) => _PanePage(child: page),
        transitionsBuilder: _arrive,
      );

  /// How a page arrives. Beside the list a page takes the place of the last one, so it fades in; over the list it
  /// slides across it, as a phone's pages do.
  static Widget _arrive(BuildContext context, Animation<double> a, Animation<double> _, Widget child) => AppShell.wideOf(context)
      ? FadeTransition(opacity: CurvedAnimation(parent: a, curve: const Interval(0, 0.55)), child: child)
      : SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
          child: child,
        );

  /// Opens [page] in the pane, in place of whatever was there. [thread] is the conversation it is, for the list to
  /// mark; [showing] is the pill's ring it is ('new', 'contacts', 'settings'), for the pill to fill; [section] is
  /// the section of Settings it is, for Settings' list to mark.
  void show(Widget page, {int? thread, String? showing, String? section}) {
    final nav = _pane.currentState;
    if (nav == null) {
      // Asked for before the first frame (a notification that opened the app): once there is a pane.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pane.currentState != null) show(page, thread: thread, showing: showing, section: section);
      });
      return;
    }
    final route = _route(page);
    final had = _open != null;
    setState(() {
      _open = route;
      _thread = thread;
      _showing = showing;
    });
    settingsSection.value = section;
    // Anything but a page of Settings puts Settings' list away: a conversation, a new chat and the contacts are
    // kept with the conversations.
    if (showing != 'settings' && settingsOpen) home();
    nav.pushAndRemoveUntil(route, (r) => r.isFirst);
    // The list under a page that covers it is not drawn, and is drawn again as the page starts to leave.
    route.animation?.addStatusListener((_) {
      if (mounted && _open == route) setState(() {});
    });
    route.popped.then((_) {
      if (!mounted || _open != route) return;
      setState(() {
        _open = null;
        _thread = null;
        _showing = null;
      });
      settingsSection.value = null;
      closed.value++;
    });
    if (had) closed.value++;
  }

  /// Opens a conversation. One already open is left as it is, with whatever is half written in it.
  void openThread(int thread, List<Person> people, {String? draft}) {
    if (_thread == thread && _open != null && _open!.isCurrent && draft == null) return;
    show(ThreadScreen(key: ValueKey('thread-$thread-${draft == null ? '' : draft.hashCode}'), thread: thread, people: people, draft: draft), thread: thread);
  }

  /// Opens the new-message page, [body] already written where another app sent some words to text.
  void compose({String? body}) => show(ComposeScreen(key: UniqueKey(), body: body), showing: 'new');

  /// Opens Settings, or the one [section] of it ([seek]: a setting on that section's page to scroll to). Settings'
  /// list of sections takes the list's place, and the section's page is the pane's: beside the list in a wide
  /// window, where the first section is opened if none is named, and over it on a phone.
  void settings([String? section, String? seek]) {
    final side = _side.currentState;
    if (side == null) {
      // Asked for before the first frame: once there is a list.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _side.currentState != null) settings(section, seek);
      });
      return;
    }
    if (!settingsOpen) {
      final route = PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, _, _) => const SettingsScreen(key: ValueKey('settings')),
        transitionsBuilder: _arrive,
      );
      setState(() => _settings = route);
      side.push(route);
      route.popped.then((_) {
        if (!mounted || _settings != route) return;
        setState(() => _settings = null);
        // Its page goes with it.
        if (_showing == 'settings') close();
      });
    }
    // Beside the list there is always a section's page: the first, where none is named and none is open.
    if (section == null && _wide && settingsSection.value == null) section = settingsSections.where((s) => s.when == null).firstOrNull?.id;
    if (section != null) {
      show(SettingsSectionScreen(section, key: ValueKey('settings-$section-${seek ?? ''}'), seek: seek), showing: 'settings', section: section);
    } else if (!_wide && _showing == 'settings') {
      // On a phone, Settings asked for from one of its pages is its list.
      close();
    }
  }

  /// The section in the pane is no longer one of Settings' (a plugin's page, and the plugin was switched off): the
  /// page goes, and beside the list the first section takes its place (Settings' list sees to that).
  void settingsGone() {
    if (_showing == 'settings') close();
  }

  /// Opens the address book: a press on someone in it opens the conversation with them.
  void contacts() => show(const ContactsScreen(key: ValueKey('contacts')), showing: 'contacts');

  /// One of the pill's rings is pressed. A new chat and the contacts open in the pane; Settings takes the list's
  /// place with its page in the pane; Messages and Archive are the list itself, and put away whatever was open.
  void go(String id, {bool selectAll = false}) {
    switch (id) {
      case 'new':
        compose();
      case 'contacts':
        contacts();
      case 'settings':
        settings();
      default:
        if (_showing != null) close();
        final side = _side.currentState;
        if (side == null) return;
        // The Archived list as it stands, unless Settings is over it or it is asked for with everything chosen.
        if (id == 'archive' && _archivedOpen && !settingsOpen && !selectAll) return;
        side.popUntil((r) => r.isFirst);
        if (id != 'archive') return;
        final route = PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 160),
          reverseTransitionDuration: const Duration(milliseconds: 120),
          pageBuilder: (context, _, _) => ConversationsScreen(archived: true, selectAll: selectAll),
          transitionsBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
        );
        setState(() => _archive = route);
        side.push(route);
        route.popped.then((_) {
          if (mounted && _archive == route) setState(() => _archive = null);
        });
    }
  }

  // The rings' own menus (Matt, 2026-11-14: "add a right click context menu to archive as well and settings to
  // quick jump to settings sections"): a press with the other button on a ring, or a long press where there is no
  // other button, hangs a small list over it (lib/ui/nav_bar.dart `NavItem.menu`). They were a sheet across the
  // window's foot, as the list's tabs' menus are, which for Settings' many sections Matt found "too large and way
  // too wide".

  /// The Archive ring's menu: the tabs' own two choices, for the conversations put away.
  List<Widget> _archiveRows(BuildContext context) {
    final n = archived.value;
    return [
      GlacierMenuLabel(child: Text(n == 0 ? 'Archive · nothing archived' : 'Archive · $n ${n == 1 ? 'conversation' : 'conversations'}')),
      GlacierMenuItem(icon: const AppIcon(Lucide.checkCheck, size: 16), onSelect: _archiveRead, child: const Text('Mark all as read')),
      // Every archived conversation chosen at once, for the bar at the top to take back out or delete.
      if (n > 0) GlacierMenuItem(icon: const AppIcon(Lucide.listChecks, size: 16), onSelect: () => go('archive', selectAll: true), child: const Text('Select all')),
    ];
  }

  /// The Settings ring's menu: Settings' sections by name, in their groups, each opening Settings there. They are
  /// the sections as they stand for this device and these choices (a plugin's own, while it is on). A group of
  /// several is under its name; one section alone needs none.
  List<Widget> _settingsRows(BuildContext context) {
    final model = SettingsModel(AppState.of(this.context));
    final groups = <String, List<SettingsSection>>{};
    for (final s in settingsSections) {
      if (s.when?.call(model) ?? true) groups.putIfAbsent(s.group, () => []).add(s);
    }
    model.dispose();
    final rows = <Widget>[];
    for (final group in groups.entries) {
      if (rows.isNotEmpty) rows.add(const GlacierMenuSeparator());
      if (group.value.length > 1) rows.add(GlacierMenuLabel(child: Text(settingsGroupLabel(group.key))));
      for (final s in group.value) {
        final icon = s.icon;
        rows.add(GlacierMenuItem(icon: icon is AppIcon ? AppIcon(icon.icon, size: 16) : icon, onSelect: () => settings(s.id), child: Text(s.label)));
      }
    }
    return rows;
  }

  /// Marks every archived conversation that is unread as read, from the Archive ring's menu: where they are, with
  /// the archive left closed.
  Future<void> _archiveRead() async {
    final List<Conversation> unread;
    try {
      unread = (await Sms.instance.conversationsPage(archived: true)).items.where((c) => c.unread).toList();
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t read the archive: $e', tone: GlacierToastTone.danger);
      return;
    }
    if (!mounted) return;
    if (unread.isEmpty) return toast(context, 'Nothing is unread in the archive');
    var failed = 0;
    for (final c in unread) {
      try {
        await Sms.instance.markRead(c.id);
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    // The lists read their conversations again.
    closed.value++;
    final n = unread.length - failed;
    toast(
      context,
      failed == 0 ? '$n ${n == 1 ? 'conversation' : 'conversations'} marked as read' : '$n marked as read; $failed could not be',
      tone: failed == 0 ? GlacierToastTone.neutral : GlacierToastTone.danger,
    );
  }

  /// Closes what is open in the pane.
  void close() => _pane.currentState?.popUntil((r) => r.isFirst);

  /// Takes the list back to the conversations, from Archived or from Settings.
  void home() => _side.currentState?.popUntil((r) => r.isFirst);

  /// Says that [child] stands in a column of the window [width] wide, where it does: the list beside a pane.
  /// Always there, so the list keeps its place in the tree as the window changes: a width without end says the
  /// list is the whole window.
  Widget _column(bool beside, double width, Widget child) => HeaderColumn(left: 0, width: beside ? width : double.infinity, child: child);

  /// The way round: a new chat, the messages, the contacts, the archive with how many are in it, Settings with how
  /// many watched for have joined (Settings › Friends joining).
  Widget _pill({required bool upright}) => ValueListenableBuilder<int>(
        valueListenable: archived,
        builder: (context, count, _) => ListenableBuilder(
          listenable: Me.instance,
          builder: (context, _) => NavPill(
            upright: upright,
            active: _showing ?? (settingsOpen ? 'settings' : (_archivedOpen ? 'archive' : 'messages')),
            onSelect: go,
            items: [
              const NavItem(id: 'new', icon: Lucide.messageSquarePlus, label: 'New chat'),
              const NavItem(id: 'messages', icon: Lucide.messageSquare, label: 'Messages'),
              const NavItem(id: 'contacts', icon: Lucide.contactRound, label: 'Contacts'),
              NavItem(id: 'archive', icon: Lucide.archive, label: 'Archive', count: count, menu: _archiveRows),
              NavItem(id: 'settings', icon: Lucide.settings, label: 'Settings', count: Me.instance.unseen, menu: _settingsRows),
            ],
          ),
        ),
      );

  /// How many rings the pill has: what a window must be tall enough for, to have it stood up.
  static const _rings = 5;

  Widget _sized(Widget child) => LayoutBuilder(
        // The screens measure themselves against the screen they are on: here that is their share of the window.
        builder: (context, box) => MediaQuery(data: MediaQuery.of(context).copyWith(size: Size(box.maxWidth, box.maxHeight)), child: child),
      );

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= AppShell.wideAt;
      _wide = wide;
      final side = wide ? AppShell.sideWidth(box.maxWidth) : box.maxWidth;
      // A wide phone has the pill stood up at its right, where the window is tall enough for it (not a small phone
      // on its side). The strip is as wide as the pill and its room, and clear of anything cut into the screen's edge.
      final edges = MediaQuery.paddingOf(context);
      final rail = wide && !Sms.remote && box.maxHeight - edges.vertical >= NavPill.railHeight(t, _rings);
      final strip = rail ? NavPill.railWidth(t) + edges.right : 0.0;
      // A page that has finished sliding over the list covers all of it.
      final covered = !wide && _open != null && _open!.animation?.status == AnimationStatus.completed;
      return _ShellScope(
        shell: this,
        wide: wide,
        rail: rail,
        thread: _open == null ? null : _thread,
        child: PopScope(
          canPop: !(_paneBack || _sideBack),
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            // Beside Settings' list its page is all there is to go back from: back leaves Settings whole.
            if (wide && settingsOpen && _showing == 'settings' && (_open?.isCurrent ?? false)) return go('messages');
            // What is open closes first; then the list goes back from Archived or Settings, or stops choosing.
            (_paneBack ? _pane : _side).currentState?.maybePop();
          },
          child: ColoredBox(
            color: t.color('glacier-bg'),
            child: Stack(children: [
              Positioned(
                key: const ValueKey('shell-side'),
                left: 0,
                top: 0,
                bottom: 0,
                width: side,
                child: Offstage(
                  offstage: covered,
                  child: TickerMode(
                    enabled: !covered,
                    child: HeaderCover(
                      covered: !wide && _open != null,
                      // Beside a pane the list is a column of the window: what hangs under its header (the update
                      // banner) is as wide as the list, not laid across list and pane both.
                      child: _column(wide, side, _sized(Stack(children: [
                        Positioned.fill(
                          child: NotificationListener<NavigationNotification>(
                            onNotification: (n) {
                              if (n.canHandlePop != _sideBack) setState(() => _sideBack = n.canHandlePop);
                              return false;
                            },
                            child: Navigator(
                              key: _side,
                              onGenerateRoute: (_) => PageRouteBuilder<void>(pageBuilder: (context, _, _) => const ConversationsScreen()),
                            ),
                          ),
                        ),
                        // The way round floats over the list's end, clear of the bar at the foot of a phone's
                        // screen; the list leaves it room (AppShell.pillRoom). Not on a wide phone, where it
                        // stands at the window's right.
                        // On a phone Settings is a page over the list, with its own way back and no bar under it.
                        if (!rail)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: edges.bottom,
                            child: IgnorePointer(
                              ignoring: !wide && settingsOpen,
                              child: AnimatedOpacity(
                                opacity: !wide && settingsOpen ? 0 : 1,
                                duration: const Duration(milliseconds: 160),
                                child: _pill(upright: false),
                              ),
                            ),
                          ),
                      ]))),
                    ),
                  ),
                ),
              ),
              if (wide) Positioned(key: const ValueKey('shell-rule'), left: side, top: 0, bottom: 0, width: 1, child: ColoredBox(color: t.color('app-rule'))),
              Positioned(
                key: const ValueKey('shell-pane'),
                left: wide ? side + 1 : 0,
                top: 0,
                bottom: 0,
                right: rail ? strip + 1 : 0,
                // With nothing open on a narrow screen the pane is empty air over the list: touches go through.
                child: IgnorePointer(
                  ignoring: !wide && _open == null,
                  // Beside the strip the pane does not reach the screen's right edge: what is cut into that edge
                  // is the strip's to stand clear of.
                  child: MediaQuery.removePadding(
                   context: context,
                   removeRight: rail,
                   child: _sized(NotificationListener<NavigationNotification>(
                    onNotification: (n) {
                      if (n.canHandlePop != _paneBack) setState(() => _paneBack = n.canHandlePop);
                      return false;
                    },
                    child: Navigator(
                      key: _pane,
                      observers: widget.paneObservers,
                      onGenerateRoute: (_) => PageRouteBuilder<void>(opaque: false, pageBuilder: (context, _, _) => const _Base()),
                    ),
                   )),
                  ),
                ),
              ),
              // A wide phone's way round: the pill stood up at the foot of its own strip, ruled off from the pane as
              // the pane is from the list.
              if (rail) ...[
                Positioned(key: const ValueKey('shell-rail-rule'), right: strip, top: 0, bottom: 0, width: 1, child: ColoredBox(color: t.color('app-rule'))),
                Positioned(
                  key: const ValueKey('shell-rail'),
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: strip,
                  child: Padding(
                    padding: EdgeInsets.only(top: edges.top, right: edges.right, bottom: edges.bottom),
                    child: Align(alignment: Alignment.bottomCenter, child: _pill(upright: true)),
                  ),
                ),
              ],
            ]),
          ),
        ),
      );
    });
  }
}

class _ShellScope extends InheritedWidget {
  const _ShellScope({required this.shell, required this.wide, required this.rail, required this.thread, required super.child});
  final AppShellState shell;
  final bool wide;
  final bool rail;
  final int? thread;

  @override
  bool updateShouldNotify(_ShellScope old) => old.wide != wide || old.rail != rail || old.thread != thread;
}

/// A page open in the pane: it draws its way back only while the list is not beside it.
class _PanePage extends StatelessWidget {
  const _PanePage({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => PaneRoot(isBeside: AppShell.wideOf(context), child: child);
}

/// Under every page in the pane. Beside the list it is what the pane says with nothing open; over the list it is
/// nothing at all, and the list is seen through it.
class _Base extends StatelessWidget {
  const _Base();

  @override
  Widget build(BuildContext context) {
    if (!AppShell.wideOf(context)) return const SizedBox.expand();
    final own = AppShell.maybeOf(context)?.widget.nothing;
    return own != null ? own(context) : const _Nothing();
  }
}

/// The pane before a conversation is chosen.
class _Nothing extends StatelessWidget {
  const _Nothing();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(t.space(6)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            GhostLogo(size: t.lenOf('3.5rem')),
            SizedBox(height: t.space(4)),
            Text('Choose a conversation', textAlign: TextAlign.center, style: pageText(t, t.fontSize('lg'), weight: 'semibold', color: t.color('app-ink-2'))),
            SizedBox(height: t.space(1)),
            Text(AppShell.railOf(context) ? 'Or start a new chat from the bar on the right.' : 'Or start a new chat from the bar under the list.', textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3'))),
          ]),
        ),
      ),
    );
  }
}
