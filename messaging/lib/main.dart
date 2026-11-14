import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'app_state.dart';
import 'backgrounds.dart';
import 'desktop/main.dart';
import 'emoji_sets.dart';
import 'kit/settings_css.dart';
import 'friends/friends.dart';
import 'friends/groups.dart';
import 'net/net.dart';
import 'sms.dart';
import 'ui/computers.dart';
import 'ui/setup.dart';
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
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final state = AppState();
  // The stylesheets, the person's choices and the wallpaper's colours (for a chat background and bubbles that follow
  // the phone) are asked for together: none waits on another.
  final loaded = await Future.wait<Object?>([
    loadTokenSheet(more: const ['assets/css/ink.css', 'assets/css/app.css']),
    state.load(),
    PhonePalette.load(),
  ]);
  final sheet = loaded[0]! as TokenSheet;
  installSettingsStyles(sheet);
  Sms.instance.listen();
  _logErrors();
  _watchFrames();
  Sms.instance.prefsChanged.stream.listen((_) => state.reload());
  runApp(GhostMessagingApp(sheet: sheet, state: state));
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
  const GhostMessagingApp({super.key, required this.sheet, required this.state});
  final TokenSheet sheet;
  final AppState state;

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
            sheet: sheet,
            attrs: {'platform': 'mobile', if (state.theme != 'system') 'theme': state.theme},
            typography: ghostTypography(state.emoji),
            child: HapticsProvider(
              enabled: true,
              child: InkOverrides(child: _SystemBars(child: GlacierToastProvider(child: UpdateBanner(child: child!)))),
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
    setState(() => _isDefault = s.isDefault);
    if (first && s.isDefault) {
      // The app's own updates: a look at most twice a day, as it opens.
      Sms.instance.updateBackground();
      // The app's routes to other phones with it (lib/net/net.dart): set up once, as the app opens.
      // And friends, who are reached by them (lib/friends/friends.dart).
      final app = AppState.of(context);
      Net.instance.start(app).then((_) => Friends.instance.start(app)).then((_) => Groups.instance.start());
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
    if (req.pairing != null) {
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
    if (!_isDefault!) return SetupScreen(onDone: () => _check(first: true));
    // The list, and what is opened from it beside it where the screen is wide enough (a folding phone opened out).
    return AppShell(key: _shell, paneObservers: _paneWatch);
  }
}

/// Ghost.md's ink.css on the kit's parts no token reaches (as Ghost Keyboard's main.dart does).
class InkOverrides extends StatelessWidget {
  const InkOverrides({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => GlacierOverrides(switchThumbColor: _paper, segmentedSelectedLabelColor: _paper, segmentedThumbShadow: _none, child: child);

  static Color _paper(Tokens t) => t.color('app-paper');
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
