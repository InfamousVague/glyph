import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../accent.dart';
import '../app_state.dart';
import '../kit/settings_css.dart';
import '../looks.dart';
import '../main.dart' show InkOverrides, ghostTypography;
import '../sounds.dart';
import '../sms.dart';
import '../ui/settings_panes.dart' show appVersion;
import 'desk.dart';
import 'link/link.dart';
import 'platform.dart';
import 'remote.dart';
import '../voice/channels.dart';
import '../voice/discord.dart';
import '../voice/space_groups.dart';
import 'store.dart';
import 'ui/shell.dart';
import '../ui/update_banner.dart';
import 'ui/wizard.dart';
import '../inbox/inbox.dart';
import '../ui/inbox_ui.dart';
import 'gm_web.dart';
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
    // Bonjour is the Mac's and the iPhone's (DeskChannels.swift); on Windows the phone is found by its address or the relay.
    finder: !(bonjour ?? (env['GHOST_DESK_BONJOUR'] != 'off' && (Platform.isMacOS || Platform.isIOS))) ? null : BonjourFinder(),
    given: [...envPeers, ?Peer.parse(prefs['peer'] ?? '')],
  );
  final calls = LinkCalls(link, store);
  await calls.init();
  // Where a voice message the Mac is playing has got to, told to the screens as the phone tells its own.
  MacPlatform.listenToVoice((m) => Sms.instance.voice.add(VoicePlayback.from(m)));
  Sms.calls = calls;
  // Google Messages on this computer (gm_web.dart): its helper started where this copy carries it, and what changes
  // there told to the screens as the phone's changes are.
  GmWeb.instance.changed.stream.listen(Sms.instance.changes.add);
  unawaited(GmWeb.instance.start(store.dir));
  final state = AppState();
  final loaded = await Future.wait<Object?>([AccentSheets.load(), state.load()]);
  final accents = loaded[0]! as AccentSheets;
  final sheet = accents.base;
  installSettingsStyles(sheet);
  await link.start();
  // Voice channels (lib/voice): the computer's own connection to the hub, made once it has a channel.
  // The interface sounds (lib/sounds.dart) read the person's choices from here.
  Sounds.instance.start(state);
  unawaited(Voice.instance.start(state));
  SpaceGroups.instance.start(state);
  DiscordServers.instance.start(state);
  // Telegram's and Bluesky's chats (lib/inbox): the computer signs in to them itself, as their own apps do.
  addInboxSettings();
  unawaited(Inbox.instance.start(state));
  // The app's own updates: asked of the Mac's half, looked for now and every few hours. Never awaited: the app
  // opens whether or not the site answers.
  // A Mac swaps in the Mac's zip; Windows runs the new installer from gogho.st, silently, on Restart to update.
  final macUpdates = updates && (Platform.isMacOS || Platform.isWindows) ? MacUpdates.fromEnvironment(env, windows: Platform.isWindows) : null;
  if (macUpdates != null) {
    // Told to the phone's screens too, so its banner and its words are the computer's (remote.dart).
    calls.attachUpdates(macUpdates);
    unawaited(macUpdates.start());
  }
  runApp(DesktopApp(sheet: sheet, state: state, link: link, calls: calls, store: store, envPeers: envPeers, updates: macUpdates, accents: accents));
}

class DesktopApp extends StatelessWidget {
  const DesktopApp({super.key, required this.sheet, required this.state, required this.link, required this.calls, required this.store, this.envPeers = const [], this.updates, this.accents});
  final TokenSheet sheet;

  /// The stylesheets with the bubble colour chosen everywhere as the accent (lib/accent.dart); [sheet] alone where
  /// not given.
  final AccentSheets? accents;
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
              sheet: accents?.of(state) ?? sheet,
              attrs: ghostAttrs(state, 'desktop'),
              typography: ghostTypography(state.emoji),
              // A newer version says so with the card the phone has, at the top of the list (lib/ui/update_banner.dart).
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
        if (link.phone != null && (a == null || a.phase == 'done')) return DeskShell(key: ValueKey(link.phone!.id));
        return const PairWizard();
      },
    );
  }
}
