import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'me/me.dart';
import 'accent.dart';
import 'summaries.dart';
import 'app_state.dart';
import 'kept_lists.dart';
import 'backgrounds.dart';
import 'desktop/main.dart';
import 'desktop/store.dart' show DeskStore;
import 'standalone/overlay.dart';
import 'standalone/standalone.dart';
import 'standalone/welcome.dart';
import 'emoji_sets.dart';
import 'kit/settings_css.dart';
import 'friends/buddies.dart';
import 'friends/friends.dart';
import 'friends/groups.dart';
import 'net/net.dart';
import 'voice/channels.dart';
import 'sms.dart';
import 'ui/computers.dart';
import 'onboarding/onboarding.dart';
import 'inbox/alerts.dart';
import 'inbox/inbox.dart';
import 'inbox/telegram.dart';
import 'ui/inbox_ui.dart';
import 'ui/shell.dart';
import 'ui/update_banner.dart';

/// Ghost Messaging: an SMS/MMS app drawn with Glacier and Ghost.md's stylesheets, as Ghost Keyboard's settings are.
/// The messages themselves are Android's (android/.../Store.kt); this is the screen over them.
/// What goes wrong on the screens' side goes in the app's own log (Settings › Developer; Matt, 2026-11-13: "a
/// developer setting with copying errors and reporting"): what it was and where, never what a message said.
void _logErrors() {
  String where(StackTrace? stack) {
    final all = (stack?.toString() ?? '').split('\n').where((l) => l.trim().isNotEmpty).toList();
    // The app's own lines where the error passed through any; else wherever it was thrown, so the report still
    // says where (Matt's report, 2026-11-14, held "Null check operator used on a null value" and nothing more).
    final ours = all.where((l) => l.contains('package:ghost_messaging')).take(2).toList();
    final lines = (ours.isNotEmpty ? ours : all.take(3)).map((l) => l.replaceAll(RegExp(r'^#\d+\s+'), '').replaceAll(RegExp(r'\s+'), ' ').trim());
    return lines.isEmpty ? '' : ' at ${lines.join(' < ')}';
  }

  final shown = FlutterError.onError;
  FlutterError.onError = (details) {
    Sms.instance.devLog('dart', '${details.exceptionAsString().split('\n').first}${where(details.stack)}');
    shown?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    Sms.instance.devLog('dart', '${error.runtimeType}: ${'$error'.split('\n').first}${where(stack)}');
    return false;
  };
}

Future<void> main() async {
  // On a computer this is the companion to the phone's app (lib/desktop): the same screens, asking the phone.
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) return desktopMain();
  WidgetsFlutterBinding.ensureInitialized();
  // An iPhone has no texts for an app to read (Apple allows it only in the EU, to the default messaging app), so it is
  // Ghost Messaging of its own: friends by username, groups and calls over the internet (lib/standalone; Matt,
  // 2026-11-15: "roll a version of the app that works without sms"). One already paired with an Android phone as a
  // computer is (lib/desktop) stays that phone's companion.
  if (Platform.isIOS) {
    if (File('${DeskStore.defaultDir().path}/pairing.json').existsSync()) return desktopMain();
    await standaloneSetup();
  } else {
    // The phone's friends by username are kept in Dart, beside its texts (lib/standalone/overlay.dart): an iPhone
    // writes to them by username (Matt, 2026-11-15: "Yes, Android next").
    await overlaySetup();
  }
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final state = AppState();
  KeptLists.instance.app = state;
  // The stylesheets, the person's choices and the wallpaper's colours (for a chat background and bubbles that follow
  // the phone) are asked for together: none waits on another.
  final loaded = await Future.wait<Object?>([
    AccentSheets.load(),
    state.load(),
    PhonePalette.load(),
  ]);
  final accents = loaded[0]! as AccentSheets;
  final sheet = accents.base;
  installSettingsStyles(sheet);
  Sms.instance.listen();
  _logErrors();
  _watchFrames();
  Sms.instance.prefsChanged.stream.listen((_) => state.reload());
  runApp(GhostMessagingApp(sheet: sheet, state: state, accents: accents));
}

final _navigator = GlobalKey<NavigatorState>();

/// With `adb shell setprop log.tag.GhostPerf VERBOSE` set before the app starts, how long frames take is written to
/// Android's log every two seconds there are any: how many, and the slowest and the middle one's build and raster
/// times in milliseconds. Nothing is measured otherwise. (The Android side logs each of its calls the same way.)
Future<void> _watchFrames() async {
  try {
    if (!await Sms.instance.perfOn()) return;
  } catch (_) {
    return;
  }
  final build = <int>[];
  final raster = <int>[];
  Timer.periodic(const Duration(seconds: 2), (_) {
    if (build.isEmpty) return;
    build.sort();
    raster.sort();
    double ms(int micros) => micros / 1000;
    final slow = build.where((b) => b > 16000).length;
    // ignore: avoid_print
    print('GhostPerf frames=${build.length} build mid=${ms(build[build.length ~/ 2]).toStringAsFixed(1)} max=${ms(build.last).toStringAsFixed(1)} over16ms=$slow raster mid=${ms(raster[raster.length ~/ 2]).toStringAsFixed(1)} max=${ms(raster.last).toStringAsFixed(1)}');
    build.clear();
    raster.clear();
  });
  WidgetsBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      build.add(t.buildDuration.inMicroseconds);
      raster.add(t.rasterDuration.inMicroseconds);
    }
  });
}

/// The page's faces, with the emoji set chosen first among their fallbacks: Inter draws no emoji, so every one is
/// the set's. The phone's own set adds no fallback, and Android's emoji font is what is left.
GlacierTypography ghostTypography(String emoji) {
  final family = emojiSet(emoji).family;
  return GlacierTypography(
    features: const [FontFeature('cv11'), FontFeature('ss01')],
    fallbacks: family == null ? const {} : {'Inter Variable': [family], 'JetBrains Mono Variable': [family]},
  );
}

class GhostMessagingApp extends StatelessWidget {
  const GhostMessagingApp({super.key, required this.sheet, required this.state, this.accents});
  final TokenSheet sheet;
  final AppState state;

  /// The stylesheets with the bubble colour chosen everywhere as the accent (lib/accent.dart); [sheet] alone where
  /// not given.
  final AccentSheets? accents;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => WidgetsApp(
          title: 'Ghost Messaging',
          navigatorKey: _navigator,
          // Each page that opens asks for a look for a newer version (lib/ui/update_banner.dart).
          navigatorObservers: [UpdateWatch()],
          color: const Color(0xFF4F5BD5),
          debugShowCheckedModeBanner: false,
          pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
              PageRouteBuilder<T>(settings: settings, pageBuilder: (context, _, _) => builder(context)),
          builder: (context, child) => GlacierTheme(
            sheet: accents?.of(state) ?? sheet,
            attrs: {'platform': 'mobile', if (state.theme != 'system') 'theme': state.theme},
            typography: ghostTypography(state.emoji),
            child: HapticsProvider(
              enabled: true,
              child: InkOverrides(child: _SystemBars(child: GlacierToastProvider(child: child!))),
            ),
          ),
          home: const _Home(),
        ),
      ),
    );
  }
}

/// Setup until Ghost is the default SMS app, then the conversations. A notification or another app's "text this
/// number" opens what it asks for over them.
class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> with WidgetsBindingObserver {
  final _shell = GlobalKey<AppShellState>();

  /// Each page that opens in the pane asks for a look for a newer version, as each page of the app does.
  final _paneWatch = <NavigatorObserver>[UpdateWatch()];
  /// The walkthrough is open (it opened because Ghost could not send texts), until it is finished.
  bool _walking = false;

  /// The default SMS app, or beside Google Messages (SmsStatus.usable); null until asked.
  bool? _isDefault;
  StreamSubscription<OpenRequest>? _opens;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check(first: true);
    _opens = Sms.instance.opens.stream.listen(_open);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _opens?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _check();
    // The wallpaper may have changed while the app was away: what is drawn from its palette is drawn again.
    PhonePalette.load().then((changed) {
      if (changed && mounted) AppState.of(context).changed();
    });
  }

  Future<void> _check({bool first = false}) async {
    final s = await Sms.instance.status();
    if (!mounted) return;
    setState(() => _isDefault = s.usable);
    if (first && s.usable) {
      // The app's own updates: a look at most twice a day, as it opens.
      Sms.instance.updateBackground();
      // The app's routes to other phones with it (lib/net/net.dart): set up once, as the app opens.
      // And friends, who are reached by them (lib/friends/friends.dart).
      final app = AppState.of(context);
      Net.instance.start(app).then((_) => Friends.instance.start(app)).then((_) => Groups.instance.start()).then((_) => Voice.instance.start(app));
      // Telegram's and Bluesky's chats (lib/inbox), each started where it was signed in before, and their Settings.
      addInboxSettings();
      Inbox.instance.start(app);
      // Their new messages notified, and the phone kept connected to them while Ghost is out of sight
      // (lib/inbox/alerts.dart).
      InboxAlerts.instance ??= InboxAlerts(
        notify: (a) => Sms.instance.notifyInbox(a.key, network: a.network, title: a.title, body: a.body, group: a.group),
        cancel: Sms.instance.cancelInbox,
        keepAlive: Sms.instance.keepNetworks,
        inFront: () => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      )..watch(Inbox.instance);
      // The accounts linked and the handles watched for (Settings › Me): spoken of to the relay server only once
      // one has been.
      Me.instance.start(AppMeStore(app), Net.instance, () => Net.instance.hub, needHub: (yes) => Net.instance.want('me', yes));
      // Friends by username (lib/friends/buddies.dart): heard over the hub, so it is dialled while any are kept.
      Buddies.instance.start().then((_) {
        if (Buddies.instance.all.isNotEmpty) Net.instance.want('buddies', true);
      });
      // Summaries of unread conversations by the phone's own model (lib/summaries.dart): where it stands, and asked
      // for where it can be had.
      Summaries.instance.start(app);
      // And the number's verification, done here for a paired computer that asks (Sms.me on the computer).
      Sms.answer('me', Me.instance.forComputer);
      // A paired computer's voice channels are the phone's (lib/voice/channels.dart).
      Sms.answer('voice', Voice.instance.answerDesk);
      // And its Telegram approves a paired computer's sign-in (lib/inbox/telegram.dart).
      Sms.answer('telegram', (args) async {
        final tg = Inbox.instance.named('telegram');
        if (tg is! Telegram) throw StateError('Telegram isn\'t in this build of the app.');
        return tg.answerComputer(args);
      });
      if (!s.contacts || !s.notifications) await Sms.instance.requestPermissions();
      final req = await Sms.instance.openRequest();
      if (req != null) _open(req);
    }
  }

  Future<void> _open(OpenRequest req) async {
    final nav = _navigator.currentState;
    if (nav == null || _isDefault != true) return;
    nav.popUntil((r) => r.isFirst);
    // What is asked for opens in the frame's pane (lib/ui/shell.dart): over the list on a narrow screen, beside it
    // on a wide one. The frame is on the screen a frame after the app is found to be the default.
    if (_shell.currentState == null) await WidgetsBinding.instance.endOfFrame;
    final shell = _shell.currentState;
    if (shell == null) return;
    shell.home();
    if (req.inbox != null) {
      // A Signal or Telegram message's notification: its chat.
      final at = req.inbox!.indexOf(':');
      final network = at < 0 ? null : Inbox.instance.named(req.inbox!.substring(0, at));
      if (network != null) {
        final id = req.inbox!.substring(at + 1);
        final chat = network.chats.where((c) => c.id == id).firstOrNull;
        shell.show(InboxChatScreen(network: network, chatId: id, fallback: chat), showing: 'inbox:${network.id}:$id');
      }
    } else if (req.pairing != null) {
      // A computer's pairing link, opened by the camera: the pairing page, which asks first.
      shell.show(PairComputerScreen(offered: req.pairing));
    } else if (req.computers) {
      // The "Paired with …" notification.
      shell.settings('computers');
    } else if (req.thread != null) {
      final people = await Sms.instance.people(req.thread!);
      shell.openThread(req.thread!, people);
    } else if (req.addresses.isNotEmpty) {
      final thread = await Sms.instance.threadFor(req.addresses);
      final people = <Person>[for (final a in req.addresses) await Sms.instance.contact(a)];
      shell.openThread(thread, people, draft: req.body);
    } else {
      shell.compose(body: req.body);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDefault == null) return ColoredBox(color: context.tokens.color('glacier-bg'));
    // The walkthrough (lib/onboarding): from first launch, while Ghost cannot send texts, and on until it is
    // finished, though the texts page makes it able to part way through.
    if (!_isDefault! || _walking) {
      _walking = true;
      return Onboarding(onDone: () {
        setState(() => _walking = false);
        _check(first: true);
      });
    }
    // An iPhone of its own starts with a username (lib/standalone/welcome.dart); it is never asked to be the
    // default for texts, so the walkthrough above is not shown on one.
    if (Sms.standalone && Me.instance.username == null) return StandaloneWelcome(onDone: () => setState(() {}));
    // The list, and what is opened from it beside it where the screen is wide enough (a folding phone opened out).
    return AppShell(key: _shell, paneObservers: _paneWatch);
  }
}

/// Ghost.md's ink.css on the kit's parts no token reaches (as Ghost Keyboard's main.dart does).
class InkOverrides extends StatelessWidget {
  const InkOverrides({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => GlacierOverrides(switchThumbColor: _paper, segmentedSelectedLabelColor: _onAccent, segmentedThumbShadow: _none, child: child);

  static Color _paper(Tokens t) => t.color('app-paper');

  /// The words on a toggle's chosen tab, which wears the accent (lib/accent.dart).
  static Color _onAccent(Tokens t) => t.color('app-on-accent');
  static List<BoxShadow> _none(Tokens t) => const [];
}

/// The status and navigation bars' icons, dark on the light theme and light on the dark.
class _SystemBars extends StatelessWidget {
  const _SystemBars({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = context.tokens.isDark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
        statusBarColor: const Color(0x00000000),
        systemNavigationBarColor: const Color(0x00000000),
      ),
      child: child,
    );
  }
}
