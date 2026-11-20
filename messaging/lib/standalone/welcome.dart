import 'dart:async';

import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../account/account.dart';
import '../art/lucide.g.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../me/me.dart';
import '../ui/account_screens.dart';
import '../ui/common.dart' show push;
import '../ui/computers.dart' show PairButton;
import '../kit/semantic_colors.dart';

/// The first thing a device of its own shows (lib/standalone; Matt, 2026-11-15: "roll a version of the app that works
/// without sms"). Since 2026-11-20 it asks for two things only (Matt: "rework the onboarding flow to be very simple and
/// just ask for a username and password"): the username, which is how anyone reaches someone here, claimed on the
/// relay server's directory (it keeps only the username's hash and this device's public key), and a password, which
/// makes the Ghost account at the same moment (lib/account), so the username can be signed in to on another device.
/// The recovery words come after, to write down and check, and the check can be skipped.
///
/// The username is claimed first, then the account is made with this install's own identity ("bound"): made the
/// other way round, a fresh install would take the words' identity and have to start again before it had a username.
class StandaloneWelcome extends StatefulWidget {
  const StandaloneWelcome({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<StandaloneWelcome> createState() => _StandaloneWelcomeState();
}

class _StandaloneWelcomeState extends State<StandaloneWelcome> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _problem;
  String? _busy;

  @override
  void initState() {
    super.initState();
    // The directory is the relay server's: dialled now, so it is answering by the time a username is typed.
    Me.instance.wake();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final want = tidyHandle(_username.text);
    final password = _password.text;
    if (!Me.goodUsername(want)) return setState(() => _problem = 'A username is 3 to 20 letters, numbers, dots or underscores.');
    if (password.length < minPassword) return setState(() => _problem = 'A password is at least $minPassword characters.');
    setState(() {
      _busy = 'Checking…';
      _problem = null;
    });
    // Pushed from here, the words stay over whatever comes next once the username is in (the gate moves on by itself).
    final navigator = Navigator.of(context);
    try {
      await Me.instance.claimUsername(want);
    } catch (e) {
      if (mounted) setState(() => _problem = e is MeError ? e.message : '$e');
      if (mounted) setState(() => _busy = null);
      return;
    }
    try {
      if (mounted) setState(() => _busy = 'Creating your account…');
      final draft = Account.instance.draft();
      await Account.instance.create(draft, password);
      unawaited(navigator.push(PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, _, _) => CreateAccountScreen(step: CreateStep.words, draft: draft, made: true),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      )));
    } catch (_) {
      // The username is this device's already; the account can be made again from Settings › Me.
    }
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final me = Me.instance;
    final pad = MediaQuery.paddingOf(context);
    final busy = _busy;
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: SettingsPaneScope(
        finder: SettingsFinder(),
        child: ListenableBuilder(
          listenable: me,
          builder: (context, _) => ListView(
            padding: EdgeInsets.fromLTRB(t.space(6), pad.top + t.space(8), t.space(6), pad.bottom + t.space(8)),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              // The ghost on black, as the computer's first page has it (lib/desktop/ui/wizard.dart).
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: t.lenOf('4rem'),
                  height: t.lenOf('4rem'),
                  decoration: BoxDecoration(color: const Color(0xFF000000), borderRadius: BorderRadius.circular(t.lenOf('1rem')), border: Border.all(color: t.color('app-rule'))),
                  alignment: Alignment.center,
                  child: Image.asset('assets/art/ghost-mark.png', width: t.lenOf('2.3rem'), height: t.lenOf('2.3rem')),
                ),
              ),
              SizedBox(height: t.space(6)),
              Text('Ghost Messaging', style: pageText(t, t.fontSize('2xl'), weight: 'bold', color: t.color('app-ink'), height: 1.2)),
              SizedBox(height: t.space(2)),
              Text('Pick a username and a password.', style: pageText(t, t.fontSize('md'), color: t.color('app-ink-2'), height: 1.45)),
              SizedBox(height: t.space(6)),
              PaneSection(
                footer: _problem == null ? null : Text(_problem!, style: TextStyle(color: t.danger)),
                children: [
                  SettingRowBox(
                    child: GlacierInput(
                      key: const ValueKey('welcome-username'),
                      controller: _username,
                      placeholder: 'Username',
                      ariaLabel: 'Username',
                      autoCorrect: false,
                      autoCapitalize: TextCapitalization.none,
                      autoComplete: 'username',
                      size: GlacierFieldSize.md,
                      onSubmitted: (_) => _go(),
                    ),
                  ),
                  SettingRowBox(
                    child: GlacierInput(
                      key: const ValueKey('welcome-password'),
                      controller: _password,
                      placeholder: 'Password',
                      ariaLabel: 'Password',
                      type: GlacierInputType.password,
                      autoCorrect: false,
                      autoCapitalize: TextCapitalization.none,
                      autoComplete: 'new-password',
                      size: GlacierFieldSize.md,
                      onSubmitted: (_) => _go(),
                    ),
                  ),
                ],
              ),
              SizedBox(height: t.space(6)),
              PairButton(
                key: const ValueKey('welcome-continue'),
                label: busy ?? (me.ready ? 'Continue' : 'Connecting…'),
                icon: Lucide.arrowRight,
                onPressed: busy != null || !me.ready ? null : _go,
              ),
              // Someone with an account becomes it instead (Matt, 2026-11-17: "We need to have a way to login to
              // existing accounts").
              if (!Account.instance.signedIn) ...[
                SizedBox(height: t.space(4)),
                Center(
                  child: GlacierPressable(
                    key: const ValueKey('welcome-sign-in'),
                    onPressed: () => push(context, (_) => const SignInScreen()),
                    semanticLabel: 'I already have an account',
                    builder: (context, state) => Padding(
                      padding: EdgeInsets.all(t.space(2)),
                      child: Text('I already have an account', style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color(state.hovered || state.pressed ? 'app-ink' : 'app-ink-2'))),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
