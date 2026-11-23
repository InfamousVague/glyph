import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../accent.dart';
import '../account/account.dart';
import '../app_state.dart';
import '../emoji_sets.dart';
import '../keys.dart';
import '../kit/settings_css.dart';
import '../looks.dart';
import '../main.dart' show InkOverrides, ghostTypography;
import '../me/me.dart';
import '../net/net.dart';
import '../people.dart';
import '../plugins/pack/pack.dart' show InstalledPlugins;
import '../plugins/registry.dart' show PluginRegistry, logPluginError;
import '../sms.dart';
import '../standalone/standalone.dart';
import '../standalone/welcome.dart';
import '../ui/settings.dart' show SettingsSources;
import '../ui/shell.dart';
import '../voice/space_groups.dart';
import 'browser.dart';
import 'emoji.dart';
import 'settings.dart';
import 'store.dart';

/// Ghost Messaging in a web page (Matt: "the full web client"; docs/OPEN_NETWORK.md, part 6): one more device of an
/// account, running as a computer with no phone linked does ([Sms.standalone], lib/standalone), on the same calls
/// ([StandaloneCalls]) with the browser's own store under them (store.dart).
///
/// Only what a browser can do is set up. A computer's start (lib/desktop/main.dart) also makes the link to a phone,
/// Google Messages' helper, Files spaces' store, the other networks' chats, plugins and the Marketplace, the local
/// API and the app's own updates: each of those needs a folder, a helper program or a socket a page hasn't got, so
/// none is made here, and the screens leave out what would lead to them. What is shared with a computer's start is
/// the standalone calls and [startPeople]: the routes, friends, groups, spaces and circles.
///
/// One tab at a time ([Browser.holdTab]): two tabs of one browser are the same device to the hub, and each would
/// take the other's place there for ever, and both would write the one store.
Future<void> webMain({Browser? browser}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final b = browser ?? Browser.instance;
  final unfit = b.unfit;
  if (unfit != null) return runApp(WebNotice(words: unfit));
  final hold = await b.holdTab(onAsked: _letGo);
  if (hold == null) {
    // Open in another tab already: said, with the way to have it here instead.
    return runApp(WebNotice(
      words: 'Ghost Messaging is open in another tab.',
      more: 'It runs in one tab at a time, so each message arrives once.',
      action: 'Use it here',
      onAction: () async {
        await b.takeTab(onAsked: _letGo);
        await _start(b);
      },
    ));
  }
  await _start(b);
}

/// Another tab is taking over: everything asked to be kept is written before this one lets go.
Future<void> _letGo() async {
  final calls = Sms.calls;
  await Sms.instance.prefsWritten();
  if (calls is StandaloneCalls) await calls.flushed();
}

/// Where the hub is for a page at [address]: beside the app's own folder, `/hub` where the page is `/app/`. A page
/// may speak only to where it came from, so this is the one relay a browser can use.
String hubFor(Uri address) {
  final path = address.path;
  final at = path.lastIndexOf('/app/');
  final before = at >= 0 ? path.substring(0, at) : (path.endsWith('/app') ? path.substring(0, path.length - 4) : '');
  return Uri(scheme: address.scheme == 'https' ? 'wss' : 'ws', host: address.host, port: address.hasPort ? address.port : null, path: '$before/hub').toString();
}

Future<void> _start(Browser b) async {
  final BrowserStore kept;
  try {
    kept = await b.openStore();
  } catch (_) {
    return runApp(const WebNotice(
      words: 'This browser won\'t keep anything for this page.',
      more: 'Ghost Messaging keeps who you are and your conversations in the browser. A private window, or a browser set to keep nothing, has nowhere for them.',
    ));
  }
  final calls = StandaloneCalls.on(WebStandaloneStore(kept));
  // Starting again is the page loaded again, once what was asked to be kept is written; a link opens beside the page.
  calls.restart = () async {
    await calls.flushed();
    b.reload();
    return true;
  };
  calls.openLink = (url) async => b.openTab(url);
  await calls.load();
  Sms.calls = calls;
  Sms.standalone = true;
  Sms.browser = true;
  Sms.browserName = b.name;
  Net.homeHub = hubFor(b.address);
  // What a page can't run is never made. Plugins: none of the app's own (they sort texts, draw cards for links
  // fetched from other sites, and add to calls: nothing a page has), and none from the Marketplace, which need a
  // folder to keep them in. The other networks' chats need helper programs, and are none in a browser
  // (lib/inbox/inbox.dart).
  PluginRegistry.instance = PluginRegistry(const [], onError: logPluginError);
  InstalledPlugins.instance = InstalledPlugins(storeAllowed: false, devAllowed: false);

  final state = AppState();
  final loaded = await Future.wait<Object?>([AccentSheets.load(), state.load()]);
  final accents = loaded[0]! as AccentSheets;
  installSettingsStyles(accents.base);
  // The emoji set in use is fetched now, and another when it is chosen (emoji.dart). Waited for a moment, so a
  // connection that is quick enough never shows a face as an empty box; a slow one starts the app without it.
  ensureEmojiFont = loadEmojiFont;
  String? family() => emojiFamilyOf(state.emoji);
  await loadEmojiFont(family()!).timeout(const Duration(seconds: 3), onTimeout: () {});
  state.addListener(() => loadEmojiFont(family()!));
  // The keyboard's commands (lib/keys.dart), and the app's own network: the routes, friends, groups, spaces and
  // circles, as a computer of its own runs them (lib/people.dart).
  Keys.instance.start(state);
  // Settings › About, the page's own (settings.dart): a phone's and a computer's are theirs.
  SettingsSources.add(browserSettings);
  startPeople(state);
  SpaceGroups.instance.start(state);
  runApp(WebApp(state: state, accents: accents));
}

/// The app in the page: the one frame every device has (lib/ui/shell.dart), which puts the list and what is open side
/// by side in a wide window and one over the other in a narrow one. A wide window is read at a computer's sizes and a
/// narrow one at a phone's ([Sms.browserWide]).
class WebApp extends StatelessWidget {
  const WebApp({super.key, required this.state, required this.accents});
  final AppState state;
  final AccentSheets accents;

  @override
  Widget build(BuildContext context) => AppScope(
        state: state,
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => WidgetsApp(
            title: 'Ghost Messaging',
            color: const Color(0xFF4F5BD5),
            debugShowCheckedModeBanner: false,
            pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) => PageRouteBuilder<T>(settings: settings, pageBuilder: (context, _, _) => builder(context)),
            builder: (context, child) {
              final wide = MediaQuery.sizeOf(context).width >= AppShell.wideAt;
              Sms.browserWide = wide;
              return GlacierTheme(
                sheet: accents.of(state),
                attrs: ghostAttrs(state, wide ? 'desktop' : 'mobile'),
                typography: ghostTypography(state.emoji),
                child: InkOverrides(child: GlacierToastProvider(child: child!)),
              );
            },
            home: const WebHome(),
          ),
        ),
      );
}

/// What the page opens on: a username and a password first (lib/standalone/welcome.dart), then the conversations.
class WebHome extends StatefulWidget {
  const WebHome({super.key});

  @override
  State<WebHome> createState() => _WebHomeState();
}

class _WebHomeState extends State<WebHome> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([Me.instance, Account.instance]),
        builder: (context, _) {
          // The username is how anyone reaches someone here.
          if (Me.instance.username == null) return StandaloneWelcome(onDone: () => setState(() {}));
          return const AppShell(key: ValueKey('browser'));
        },
      );
}

/// A page that says one thing in place of the app: that it is open in another tab, or can't run here. Drawn with no
/// stylesheet, since it stands before anything is loaded.
class WebNotice extends StatefulWidget {
  const WebNotice({super.key, required this.words, this.more, this.action, this.onAction});
  final String words;
  final String? more;

  /// A button under the words, and what it does; while that runs the button says so and can't be pressed again.
  final String? action;
  final Future<void> Function()? onAction;

  @override
  State<WebNotice> createState() => _WebNoticeState();
}

class _WebNoticeState extends State<WebNotice> {
  bool _busy = false;

  Future<void> _go() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onAction!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFFFFFFFF), soft = Color(0xFFB8B8B8);
    const face = TextStyle(fontFamily: 'Inter Variable', decoration: TextDecoration.none, color: ink);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Image(image: AssetImage('assets/art/ghost-mark.png'), width: 72, height: 72, excludeFromSemantics: true),
                  const SizedBox(height: 24),
                  Text(widget.words, textAlign: TextAlign.center, style: face.copyWith(fontSize: 20, height: 1.35, fontWeight: FontWeight.w600)),
                  if (widget.more != null) ...[
                    const SizedBox(height: 10),
                    Text(widget.more!, textAlign: TextAlign.center, style: face.copyWith(fontSize: 15, height: 1.45, color: soft)),
                  ],
                  if (widget.action != null) ...[
                    const SizedBox(height: 28),
                    Semantics(
                      button: true,
                      enabled: !_busy,
                      label: widget.action,
                      excludeSemantics: true,
                      child: GestureDetector(
                        key: const ValueKey('web-notice-action'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _busy ? null : _go,
                        child: MouseRegion(
                          cursor: _busy ? SystemMouseCursors.basic : SystemMouseCursors.click,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: _busy ? const Color(0xFF3A3A3A) : ink, borderRadius: BorderRadius.circular(999)),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                              child: Text(_busy ? 'Opening…' : widget.action!, style: face.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: _busy ? soft : const Color(0xFF000000))),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
