/// The Figma plugin's page in Settings (Matt, 2026-11-02: "Also add a figma plugin"): the person's personal access
/// token, checked before it is kept (`GET /v1/me`, which changes nothing), whose it is once kept, Check, and
/// Disconnect, which asks twice and forgets what the cards learnt. Shaped as ElevenLabs' page
/// (lib/plugins/elevenlabs/elevenlabs_pane.dart), with no setup flow of its own: the page is the setup, the steps in
/// its words, so there is no voiced setup to make clips for.
///
/// The token is kept in the device's secure store (manifest.dart) and follows the account sealed
/// (lib/sync/connections.dart); the page draws again when the plugin's storage or secrets change, so a token that
/// arrives from another device shows as soon as it is read. In Simple (`Preferences.simple`) the token is all of it:
/// what a card shows and what goes to Figma wait behind More.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../claude/claude_settings.dart' show maskKey;
import '../../core/preferences.dart' show preferences;
import '../../settings/kit/settings_kit.dart';
import '../../settings/panes/pane_parts.dart' show armedFor;
import '../../settings/settings_search.dart' show SettingsFindable;
import '../github/plain_field.dart';
import '../host.dart' show onPluginStorage;
import '../types.dart' show PluginHost;
import 'client.dart';
import 'frames.dart';
import 'manifest.dart';

/// What Settings' search finds on the page.
const List<SettingsFindable> figmaFindable = [
  SettingsFindable('Figma token', 'personal access token figd frames previews connect disconnect'),
  SettingsFindable('What a card shows', 'frame picture file thumbnail node-id link'),
];

/// Figma's own settings, where its personal access tokens are made (unverified).
const String figmaTokensUrl = 'https://www.figma.com/settings';

/// What is wrong with the shape of a pasted token, or null where it looks like one. Figma's start `figd_`; older ones
/// did not, so the shape is only no spaces and long enough.
String? figmaTokenShape(String text) {
  if (RegExp(r'\s').hasMatch(text)) return 'Paste the token alone: it has no spaces in it.';
  if (text.length < 20) return 'That token looks cut short. Copy all of it from Figma.';
  return null;
}

/// The token kept, or null.
String? figmaToken({PluginHost? via}) {
  final token = (via ?? host).secrets.held(tokenSecret)?.trim() ?? '';
  return token.isEmpty ? null : token;
}

/// What the check says of [wrong] (null: the token works), in a sentence for the page.
String figmaCheckWords(FigmaFailure? wrong, [FigmaAccount? account]) {
  if (wrong == null) return account == null || account.words.isEmpty ? 'The token works.' : 'The token works. It is ${account.words}’s.';
  if (wrong.scope) return 'Kept. This token may not say whose it is (it needs Current user read for that); frames still show if it may read File content.';
  return wrong.message;
}

class FigmaPane extends StatefulWidget {
  const FigmaPane({super.key, this.frames, this.client});

  /// What the cards learnt, forgotten as the token is ([figmaFrames] where null).
  final FigmaFrames? frames;

  /// The Figma a token is checked with: a test's own.
  final FigmaClient Function(String token)? client;

  @override
  State<FigmaPane> createState() => _FigmaPaneState();
}

class _FigmaPaneState extends State<FigmaPane> {
  final TextEditingController _token = TextEditingController();
  late final VoidCallback _stop;
  bool _checking = false;
  String? _problem;
  String? _said;
  bool _armed = false;
  bool _more = false;
  Timer? _timer;
  FigmaAccount? _account;

  /// The token the account was last asked with, so a token arriving from another device is asked once.
  String? _askedWith;

  FigmaFrames get _frames => widget.frames ?? figmaFrames;

  FigmaClient _client(String token) => (widget.client ?? (token) => FigmaClient(token: token))(token);

  @override
  void initState() {
    super.initState();
    _token.addListener(_redraw);
    _stop = onPluginStorage(_storageMoved);
    unawaited(host.secrets.warm().then((_) => _askAccount()));
  }

  @override
  void dispose() {
    _stop();
    _token.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _storageMoved() {
    _redraw();
    if (figmaToken() != _askedWith) unawaited(_askAccount());
  }

  /// Whose the kept token is: asked as the page opens and as a token is kept. Quiet where it cannot be read.
  Future<void> _askAccount() async {
    final token = figmaToken();
    _askedWith = token;
    if (token == null) {
      if (mounted && _account != null) setState(() => _account = null);
      return;
    }
    try {
      final account = await _client(token).me();
      if (mounted && _askedWith == token) setState(() => _account = account);
    } on FigmaFailure {
      // A token that may not say whose it is still reads files.
    }
  }

  Future<void> _keep() async {
    final token = _token.text.trim();
    if (token.isEmpty || _checking) return;
    final shape = figmaTokenShape(token);
    if (shape != null) return setState(() => _problem = shape);
    setState(() {
      _checking = true;
      _problem = null;
      _said = null;
    });
    FigmaFailure? wrong;
    FigmaAccount? account;
    try {
      account = await _client(token).me();
    } on FigmaFailure catch (failure) {
      wrong = failure;
    }
    if (!mounted) return;
    if (wrong != null && wrong.badToken) {
      setState(() {
        _checking = false;
        _problem = 'Figma didn’t accept that token. Make a new one in Figma › Settings › Security › Personal access tokens, and copy all of it.';
      });
      return;
    }
    await host.secrets.write(tokenSecret, token);
    _frames.forgetFailures();
    if (!mounted) return;
    _token.clear();
    setState(() {
      _checking = false;
      _askedWith = token;
      _account = account;
      // Kept even when it could not be checked (no connection, or a token that may not say whose it is): a card
      // that Figma will not draw is Rich embeds' as before.
      _said = wrong == null || wrong.scope ? figmaCheckWords(wrong, account) : 'Kept. It could not be checked just now: ${wrong.message}';
    });
  }

  Future<void> _check() async {
    final token = figmaToken();
    if (token == null || _checking) return;
    setState(() {
      _checking = true;
      _problem = null;
      _said = null;
    });
    FigmaFailure? wrong;
    FigmaAccount? account;
    try {
      account = await _client(token).me();
    } on FigmaFailure catch (failure) {
      wrong = failure;
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (account != null) _account = account;
      if (wrong == null || wrong.scope) {
        _said = figmaCheckWords(wrong, account);
      } else {
        _problem = wrong.badToken ? 'Figma no longer accepts this token: it may have run out. Disconnect, then make a new one in Figma and paste it here.' : wrong.message;
      }
    });
  }

  void _disconnect() {
    _timer?.cancel();
    if (!_armed) {
      setState(() => _armed = true);
      HapticsProvider.of(context)(HapticKind.warning);
      _timer = Timer(armedFor, () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    setState(() {
      _armed = false;
      _said = null;
      _problem = null;
      _account = null;
    });
    unawaited(host.secrets.write(tokenSecret, null));
    _frames.forgetAll();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: preferences, builder: (context, _) => _page(context));

  Widget _page(BuildContext context) {
    final t = context.tokens;
    final token = figmaToken();
    final prefs = preferences.value;
    if (!_more && settingsSought(context, const ['What a card shows'])) _more = true;
    final full = !prefs.simple || _more;
    final held = prefs.localOnly ? 'Nothing leaves the phone is on, so no Figma card asks Figma for anything.' : (!prefs.linkPreviews ? 'Link previews are off, so a Figma link is a quiet card and Figma is asked nothing.' : null);
    return PaneBody(
      children: [
        if (_problem != null) SettingsCallout(icon: const AppIcon(Lucide.triangleAlert, size: 18), child: Text(_problem!)),
        if (_said != null) SettingsCallout(child: Text(_said!)),
        if (held != null && token != null) SettingsCallout(icon: const AppIcon(Lucide.info, size: 18), child: Text(held)),
        PaneSection(
          title: 'Figma token',
          description: const Text(
            'Ghost.md shows a Figma frame’s own picture where its link is alone on a line, with your own Figma account. In Figma, open Settings › Security › Personal access tokens, make a token with File content read access (and Current user read, so Check can say whose it is), then paste it here.',
          ),
          footer: const Text('The token is kept in this device’s secure storage and follows your account, sealed, to your other devices.'),
          children: [
            if (token == null)
              SettingRow(
                key: const ValueKey('figma-token-new'),
                icon: const AppIcon(Lucide.keyRound, size: 18),
                label: 'Personal access token',
                layout: SettingRowLayout.stacked,
                control: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  spacing: t.space(2),
                  children: [
                    PlainField(key: const ValueKey('figma-token'), label: 'Figma personal access token', controller: _token, placeholder: 'figd_…', secret: true, onSubmitted: _keep),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      spacing: t.space(2),
                      children: [
                        RowAction(onPress: () => unawaited(host.openUrl(figmaTokensUrl).catchError((Object _) {})), child: const Text('Open Figma')),
                        RowAction(onPress: _keep, disabled: _checking || _token.text.trim().isEmpty, child: Text(_checking ? 'Checking…' : 'Connect')),
                      ],
                    ),
                  ],
                ),
              )
            else ...[
              SettingRow(
                key: const ValueKey('figma-token-kept'),
                icon: const AppIcon(Lucide.keyRound, size: 18),
                label: _account == null || _account!.words.isEmpty ? 'Connected' : 'Connected as ${_account!.words}',
                hint: Text(maskKey(token)),
                value: RowAction(onPress: _check, disabled: _checking, child: Text(_checking ? 'Checking…' : 'Check')),
              ),
              SettingRow(
                key: const ValueKey('figma-disconnect'),
                label: 'Disconnect',
                hint: const Text('Forgets the token, and what the cards learnt on this device. Figma links go back to Rich embeds’ cards.'),
                value: RowAction(onPress: _disconnect, child: Text(_armed ? 'Tap again' : 'Disconnect')),
              ),
            ],
          ],
        ),
        if (full) ...[
          PaneSection(
            title: 'What a card shows',
            children: const [
              SettingRow(
                key: ValueKey('figma-shows-frame'),
                icon: AppIcon(Lucide.image, size: 18),
                label: 'A frame’s link',
                hint: Text('With node-id in it, as Figma’s Copy link to selection gives it: the frame itself, its name, and its file’s name. Tap it to look around the frame in Figma’s viewer.'),
              ),
              SettingRow(
                key: ValueKey('figma-shows-file'),
                icon: AppIcon(Lucide.file, size: 18),
                label: 'A file’s link',
                hint: Text('The file’s thumbnail and its name. A frame or file this token can’t open is shown as Rich embeds shows it, or as a plain link.'),
              ),
            ],
          ),
          const SettingsFootnote(
            child: Text('Only a link’s file and frame go to Figma, with your token, and only once Link previews are on: nothing else of your notes. The picture Figma makes is fetched from where Figma says and held in memory while the app runs.'),
          ),
        ] else
          PaneSection(
            children: [
              SettingRow(
                key: const ValueKey('figma-more'),
                label: 'More',
                hint: const Text('What a card shows, and what goes to Figma.'),
                control: RowAction(onPress: () => setState(() => _more = true), child: const Text('Show')),
              ),
            ],
          ),
      ],
    );
  }
}
