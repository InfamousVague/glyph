import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../kit/settings_css.dart';
import '../main.dart' show InkOverrides, ghostTypography;
import '../sms.dart';
import '../ui/settings_panes.dart' show appVersion;
import 'desk.dart';
import 'link/link.dart';
import 'platform.dart';
import 'remote.dart';
import 'store.dart';
import 'ui/shell.dart';
import '../ui/update_banner.dart';
import 'ui/wizard.dart';
import 'updates.dart';

/// Ghost Messaging on a computer (Matt, 2026-11-13: "a companion desktop app that can proxy messages encrypted from
/// my phone to my desktop and then send back to the phone to send again"; docs/desktop.md). The phone's screens,
/// with the link to the phone where the phone has Android: paired by a QR code, sealed between the two, over the
/// local network first and a relay when that fails.
///
/// Started with `GHOST_DESK_PEERS=host:port[,host:port]` it tries those addresses for the phone before any it finds
/// (an emulator's forwarded port; a network that hides the two from each other), `GHOST_DESK_DIR` keeps what it
/// keeps in another folder, and `GHOST_DESK_BONJOUR=off` leaves the local network unsearched.
///
/// [peers], [folder] and [bonjour] are the same three, for a test that starts the app itself
/// (integration_test/desk_live_test.dart). The app looks for a newer version of itself (updates.dart) unless
/// `GHOST_DESK_UPDATES=off` or [updates] is false, as it is for a test.
Future<void> desktopMain({List<Peer>? peers, String? folder, bool? bonjour, bool updates = true}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final env = Platform.environment;
  final dir = folder ?? env['GHOST_DESK_DIR'];
  // The Keychain holds the key in a release build. A build signed to run on this Mac alone loses its Keychain
  // items' trust each time it is rebuilt, so those keep the key in the app's own folder.
  final store = DeskStore(dir == null || dir.isEmpty ? DeskStore.defaultDir() : Directory(dir), keychain: const bool.fromEnvironment('GHOST_DESK_KEYCHAIN', defaultValue: kReleaseMode));
  final envPeers = peers ?? [for (final p in (env['GHOST_DESK_PEERS'] ?? '').split(',')) ?Peer.parse(p)];
  final prefs = await store.prefs();
  final link = PhoneLink(
    store: store,
    name: await MacPlatform.computerName(),
    app: appVersion,
    finder: !(bonjour ?? env['GHOST_DESK_BONJOUR'] != 'off') ? null : BonjourFinder(),
    given: [...envPeers, ?Peer.parse(prefs['peer'] ?? '')],
  );
  final calls = LinkCalls(link, store);
  await calls.init();
  // Where a voice message the Mac is playing has got to, told to the screens as the phone tells its own.
  MacPlatform.listenToVoice((m) => Sms.instance.voice.add(VoicePlayback.from(m)));
  Sms.calls = calls;
  final state = AppState();
  final loaded = await Future.wait<Object?>([loadTokenSheet(more: const ['assets/css/ink.css', 'assets/css/app.css']), state.load()]);
  final sheet = loaded[0]! as TokenSheet;
  installSettingsStyles(sheet);
  await link.start();
  // The app's own updates: asked of the Mac's half, looked for now and every few hours. Never awaited: the app
  // opens whether or not the site answers.
  final macUpdates = updates ? MacUpdates.fromEnvironment(env) : null;
  if (macUpdates != null) {
    // Told to the phone's screens too, so its banner and its words are the computer's (remote.dart).
    calls.attachUpdates(macUpdates);
    unawaited(macUpdates.start());
  }
  runApp(DesktopApp(sheet: sheet, state: state, link: link, calls: calls, store: store, envPeers: envPeers, updates: macUpdates));
}

class DesktopApp extends StatelessWidget {
  const DesktopApp({super.key, required this.sheet, required this.state, required this.link, required this.calls, required this.store, this.envPeers = const [], this.updates});
  final TokenSheet sheet;
  final AppState state;
  final PhoneLink link;
  final LinkCalls calls;
  final DeskStore store;
  final List<Peer> envPeers;
  final MacUpdates? updates;

  @override
  Widget build(BuildContext context) {
    return DeskScope(
      link: link,
      calls: calls,
      store: store,
      envPeers: envPeers,
      updates: updates,
      child: AppScope(
        state: state,
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => WidgetsApp(
            title: 'Ghost Messaging',
            color: const Color(0xFF4F5BD5),
            debugShowCheckedModeBanner: false,
            pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) => PageRouteBuilder<T>(settings: settings, pageBuilder: (context, _, _) => builder(context)),
            // Each page that opens asks for a look for a newer version, as on the phone.
            navigatorObservers: [UpdateWatch()],
            builder: (context, child) => GlacierTheme(
              sheet: sheet,
              attrs: {'platform': 'desktop', if (state.theme != 'system') 'theme': state.theme},
              typography: ghostTypography(state.emoji),
              child: InkOverrides(child: GlacierToastProvider(child: child!)),
            ),
            home: const DeskHome(),
          ),
        ),
      ),
    );
  }
}

/// The wizard until a phone is paired, then the conversations.
class DeskHome extends StatelessWidget {
  const DeskHome({super.key});

  @override
  Widget build(BuildContext context) {
    final link = DeskScope.of(context).link;
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        final a = link.attempt;
        // Paired a moment ago: the wizard's last step is the conversations themselves.
        if (a != null && a.phase == 'done') WidgetsBinding.instance.addPostFrameCallback((_) => link.pairingShown());
        // A newer version says so with the banner the phone has (lib/ui/update_banner.dart; Matt, 2026-11-14:
        // "bring the same update banner we have on mobile to the desktop app"): over the wizard here, and over the
        // pane beside the list once a phone is paired (shell.dart), so it never lies across the sidebar.
        if (link.phone != null && (a == null || a.phase == 'done')) return DeskShell(key: ValueKey(link.phone!.id));
        return const UpdateBanner(child: PairWizard());
      },
    );
  }
}
