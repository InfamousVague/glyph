import 'dart:io';

import 'package:flutter/services.dart' show Clipboard, ClipboardData, TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../desktop/private_browser.dart';
import '../inbox/account_helper.dart';
import '../inbox/inbox.dart';
import '../kit/semantic_colors.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../sms.dart';
import 'common.dart';

/// Where to get the browser extension that signs these services in across every device automatically.
const _extensionPage = 'https://gogho.st/docs/browser-extension/';

/// The services the Ghost keys extension (messaging/extension) captures — the ones it's worth suggesting on this
/// screen. Google Messages has its own guide; LinkedIn is no longer in the extension.
const _extensionServices = {'messenger', 'instagram'};

Widget _icon(LucideIcon icon) => AppIcon(icon, size: 18);

/// Signing in to Messenger, Instagram or LinkedIn (Matt, 2026-11-20: "Let's do the feasible ones but skip X and google
/// voice"). First the warning ([HelperService.warning]), which has to be agreed to before anything is asked of the
/// service, as WhatsApp's is (lib/ui/inbox_signin_whatsapp.dart). Then the three steps Google Messages' setup has
/// (lib/gm/google_signin_flow.dart): sign in to the service in a private window of a browser, copy a request from its
/// developer tools as cURL, paste it here. The helper signs in with those cookies (sidecar/ACCOUNT_HELPERS.md).
class HelperSignInScreen extends StatefulWidget {
  const HelperSignInScreen({super.key, required this.network, this.onOpenPrivate});
  final AccountHelper network;

  /// Opens the sign-in page in a private window of a browser on this computer; false where none could be. Null: this
  /// device's own way (a computer's browsers; nothing on a phone).
  final Future<bool> Function(String url)? onOpenPrivate;

  @override
  State<HelperSignInScreen> createState() => _HelperSignInScreenState();
}

class _HelperSignInScreenState extends State<HelperSignInScreen> {
  final _pasted = TextEditingController();

  /// The warning agreed to: only then are the steps shown.
  bool _agreed = false;
  bool _opened = false;

  AccountHelper get _n => widget.network;
  HelperService get _s => _n.service;
  bool get _computer => !Platform.isAndroid && !Platform.isIOS;

  @override
  void dispose() {
    _pasted.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final open = widget.onOpenPrivate ?? (_computer ? openPrivately : null);
    final ok = open != null && await open(_s.signInUrl);
    if (!mounted) return;
    setState(() => _opened = true);
    if (!ok) {
      await Clipboard.setData(ClipboardData(text: _s.signInUrl));
      if (mounted) toast(context, 'The link is copied. Open a private window and paste it.');
    }
  }

  Future<void> _signIn() async {
    if (_n.signingIn) return;
    final ok = await _n.signIn(_pasted.text);
    if (!mounted || !ok) return;
    _pasted.clear();
    toast(context, 'Signed in to ${_s.name}${_n.account == null ? '' : ' as ${_n.account}'}');
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListenableBuilder(
      listenable: _n,
      builder: (context, _) {
        final pad = EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom);
        return GhostPage(
          title: 'Sign in to ${_s.name}',
          body: SettingsPaneScope(
            finder: SettingsFinder(),
            child: ListView(
              padding: pad,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: _agreed ? _steps(t) : _warning(t),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _warning(Tokens t) => [
        PaneSection(
          title: '${_s.name} doesn\'t support this',
          description: const Text('Read this before signing in.'),
          children: [
            SettingRowBox(
              child: Padding(
                padding: EdgeInsets.all(t.space(3)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AppIcon(Lucide.triangleAlert, size: 20, color: t.danger),
                  SizedBox(width: t.space(3)),
                  Expanded(child: Text(_s.warning, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink'), height: 1.45))),
                ]),
              ),
            ),
            SettingRow(key: const ValueKey('helper-agree'), icon: _icon(Lucide.shieldCheck), label: 'I understand, sign in to ${_s.name}', onPress: () => setState(() => _agreed = true)),
            SettingRow(icon: _icon(Lucide.arrowLeft), label: 'Not now', onPress: () => Navigator.of(context).maybePop()),
          ],
        ),
      ];

  List<Widget> _steps(Tokens t) {
    Widget card(int n, String title, List<Widget> body, {bool current = false}) => Container(
          margin: EdgeInsets.only(bottom: t.space(3)),
          padding: EdgeInsets.all(t.space(4)),
          decoration: BoxDecoration(
            color: t.color('app-paper-2'),
            borderRadius: BorderRadius.circular(t.radius('lg')),
            border: Border.all(color: current ? t.color('app-ink') : t.color('app-rule'), width: current ? 1.5 : 1),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: t.lenOf('1.6rem'),
              height: t.lenOf('1.6rem'),
              margin: EdgeInsets.only(right: t.space(3)),
              decoration: BoxDecoration(shape: BoxShape.circle, color: current ? t.color('app-ink') : t.color('app-paper-3')),
              alignment: Alignment.center,
              child: Text('$n', style: pageText(t, t.fontSize('xs'), weight: 'bold', color: current ? t.color('app-paper') : t.color('app-ink-3'))),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink'))),
                SizedBox(height: t.space(1)),
                ...body,
              ]),
            ),
          ]),
        );
    Widget text(String s, {bool small = false}) => Padding(
          padding: EdgeInsets.only(bottom: t.space(2)),
          child: Text(s, style: pageText(t, small ? t.fontSize('xs') : t.fontSize('sm'), color: small ? t.color('app-ink-3') : t.color('app-ink-2'), height: 1.45)),
        );
    Widget button(String label, VoidCallback? onPressed, {bool filled = false, Key? key}) => GlacierPressable(
          key: key,
          onPressed: onPressed,
          semanticLabel: label,
          builder: (context, state) => Container(
            padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
            decoration: BoxDecoration(
              color: filled ? t.color('app-ink').withValues(alpha: onPressed == null ? 0.4 : (state.pressed ? 0.85 : 1)) : (state.pressed ? t.color('app-paper-3') : const Color(0x00000000)),
              borderRadius: BorderRadius.circular(t.radius('full')),
              border: filled ? null : Border.all(color: t.color('app-ink-3')),
            ),
            child: Text(label, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: filled ? t.color('app-paper') : t.color('app-ink'))),
          ),
        );

    Widget extensionSuggestion() => Container(
          margin: EdgeInsets.only(bottom: t.space(4)),
          padding: EdgeInsets.all(t.space(4)),
          decoration: BoxDecoration(
            color: t.color('app-paper-2'),
            borderRadius: BorderRadius.circular(t.radius('lg')),
            border: Border.all(color: t.color('app-ink'), width: 1.5),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              AppIcon(Lucide.puzzle, size: 20, color: t.color('app-ink')),
              SizedBox(width: t.space(2)),
              Expanded(child: Text('Easier: the Ghost keys extension', style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink')))),
            ]),
            SizedBox(height: t.space(2)),
            Text(
              'Add our browser extension (Chrome and Edge) and ${_s.name} links itself: sign in once in your browser and every device on your Ghost account is signed in too — no copying a request. The steps below still work if you\'d rather not.',
              style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'), height: 1.45),
            ),
            SizedBox(height: t.space(3)),
            button('Get the extension', () => Sms.instance.openLink(_extensionPage), filled: true, key: const ValueKey('helper-extension')),
          ]),
        );

    final pasting = _opened || _pasted.text.isNotEmpty;
    final busy = _n.signingIn;
    final error = _n.state == InboxState.ready ? null : _n.error;
    return [
      if (_extensionServices.contains(_s.id)) extensionSuggestion(),
      if (!_computer)
        text('This needs a computer\'s browser (its developer tools). Do steps 1 and 2 on a computer, then get the copied text to this phone (a note or an email to yourself) and paste it in step 3. Or sign in to ${_s.name} from Ghost on the computer itself.'),
      card(1, 'Sign in to ${_s.name} in a private window', [
        text('Open ${_s.name} in a private (incognito) window and sign in to your account there. A private window keeps the browser from changing the sign-in afterwards.'),
        Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [
          if (_computer) button('Open in a private window', _open, filled: !pasting),
          button('Copy the link', () async {
            await Clipboard.setData(ClipboardData(text: _s.signInUrl));
            if (!mounted) return;
            toast(context, 'Copied. Paste it in a private window.');
            setState(() => _opened = true);
          }, filled: !_computer && !pasting),
        ]),
        SizedBox(height: t.space(2)),
        text('Firefox: Ctrl+Shift+P (Shift+Cmd+P on a Mac). Chrome and Edge: Ctrl+Shift+N (Shift+Cmd+N). Safari: File › New Private Window.', small: true),
      ], current: !pasting),
      card(2, 'Copy the sign-in', [
        text('Once you\'re signed in and see your messages: open the developer tools (F12, or Option+Cmd+I on a Mac), choose Network, and reload the page. Right-click ${_s.copyFrom}, then Copy › Copy as cURL (on Windows, "Copy as cURL (bash)").'),
        text('Safari: turn on Settings › Advanced › Show features for web developers first, then Develop › Show Web Inspector › Network.', small: true),
      ], current: pasting && _pasted.text.isEmpty),
      card(3, 'Paste it here', [
        GlacierInput(
          key: const ValueKey('helper-pasted'),
          controller: _pasted,
          placeholder: "curl '${_s.signInUrl}' …",
          ariaLabel: 'The copied request',
          autoCorrect: false,
          autoCapitalize: TextCapitalization.none,
          size: GlacierFieldSize.md,
          onChange: (_) => setState(() {}),
          onSubmitted: (_) => _signIn(),
        ),
        SizedBox(height: t.space(3)),
        Row(children: [
          button(busy ? 'Asking ${_s.name}…' : 'Sign in', busy || _pasted.text.trim().isEmpty ? null : _signIn, filled: true, key: const ValueKey('helper-sign-in')),
          SizedBox(width: t.space(3)),
          Expanded(child: Text('Then close the private window. Don\'t sign out in it: that would sign Ghost out too.', style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3')))),
        ]),
        if (error != null)
          Padding(
            padding: EdgeInsets.only(top: t.space(3)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: EdgeInsets.only(right: t.space(2), top: 2), child: AppIcon(Lucide.triangleAlert, size: 16, color: t.danger)),
              Expanded(child: Text(error, style: pageText(t, t.fontSize('sm'), color: t.danger, height: 1.4))),
            ]),
          ),
      ], current: _pasted.text.isNotEmpty),
      SizedBox(height: t.space(2)),
      SettingsFootnote(child: Text('${_s.warning} What you paste is your sign-in: Ghost gives it to the ${_s.name} helper on this device and nowhere else. Your messages go between this device and ${_s.name} only, never through Ghost\'s servers.')),
    ];
  }
}
