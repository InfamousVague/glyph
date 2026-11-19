import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../account/account.dart';
import '../art/lucide.g.dart';
import '../art/app_icon.dart';
import '../friends/buddies.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../me/me.dart';
import '../ui/account_screens.dart';
import '../ui/common.dart' show push;
import '../ui/computers.dart' show PairButton;
import '../ui/sign_up_from.dart';
import '../kit/semantic_colors.dart';

/// The first thing an iPhone of its own shows (lib/standalone; Matt, 2026-11-15: "roll a version of the app that works
/// without sms"; "the iOS onboarding [shouldn't] ask to have another phone scan the iPhone, it's unlikely the user
/// will ever have two phones"): a username, which is how anyone reaches someone here, and the name friends see. It
/// is claimed on the relay server's directory, which keeps only the username's hash and this iPhone's public key.
class StandaloneWelcome extends StatefulWidget {
  const StandaloneWelcome({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<StandaloneWelcome> createState() => _StandaloneWelcomeState();
}

class _StandaloneWelcomeState extends State<StandaloneWelcome> {
  final _username = TextEditingController();
  final _name = TextEditingController();
  String? _problem;
  bool _busy = false;

  /// What an account the person has gave (lib/ui/sign_up_from.dart): the form filled from it, the picture and status
  /// kept until Continue.
  SignUpProfile? _from;

  void _fill(SignUpProfile p) {
    setState(() {
      _from = p;
      if (p.username.isNotEmpty) _username.text = p.username;
      if (p.name.isNotEmpty) _name.text = p.name;
    });
  }

  @override
  void initState() {
    super.initState();
    // The directory is the relay server's: dialled now, so it is answering by the time a username is typed.
    Me.instance.wake();
  }

  @override
  void dispose() {
    _username.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final want = tidyHandle(_username.text);
    if (!Me.goodUsername(want)) {
      setState(() => _problem = 'A username is 3 to 20 letters, numbers, dots or underscores.');
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await Me.instance.claimUsername(want);
      final name = _name.text.trim();
      final from = _from;
      if (name.isNotEmpty || from != null) {
        Me.instance.setProfile(
          displayName: name.isNotEmpty ? name : null,
          bio: from != null && from.bio.isNotEmpty && Me.instance.bio.isEmpty ? from.bio : Me.instance.bio,
          picture: from?.picture,
          status: from != null && from.status.isNotEmpty ? from.status : null,
        );
        Buddies.instance.shareProfile();
      }
      // An account made a moment ago, before there was a username: its backup carries the username from now.
      if (Account.instance.signedIn) unawaited(Account.instance.refresh(force: true).catchError((_) => false));
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _problem = e is MeError ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final me = Me.instance;
    final pad = MediaQuery.paddingOf(context);
    Widget field(TextEditingController c, String placeholder, String label, {TextCapitalization caps = TextCapitalization.words, ValueChanged<String>? onSubmitted}) => SettingRowBox(
          child: GlacierInput(controller: c, placeholder: placeholder, ariaLabel: label, autoCorrect: false, autoCapitalize: caps, size: GlacierFieldSize.md, onSubmitted: onSubmitted),
        );
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
              SizedBox(height: t.space(3)),
              Text(
                // A computer with no phone linked starts here too (lib/desktop/main.dart): its texts are a later, optional step.
                Platform.isIOS
                    ? 'Message and call your friends by username, sealed so only the two of you can read it. An iPhone keeps texts to Apple\'s Messages, so here it is friends, groups and calls over the internet.'
                    : 'Message and call your friends by username, join circles, and bring in Telegram and Signal, sealed so only you and the people you talk to can read it. No phone needed: texts from an Android phone can be linked next, or any time in Settings.',
                style: pageText(t, t.fontSize('md'), color: t.color('app-ink-2'), height: 1.45),
              ),
              // Signing in first, where it is seen before the username (Matt, 2026-11-18: "there doesn't seem to be a way to
              // login on desktop just to claim a username"): someone with an account becomes it here, username and all.
              if (!Account.instance.signedIn) ...[
                SizedBox(height: t.space(6)),
                PaneSection(children: [
                  SettingRow(
                    key: const ValueKey('welcome-sign-in'),
                    icon: AppIcon(Lucide.keyRound, size: 18),
                    label: 'I have a Ghost account',
                    hint: const Text('Sign in with your username and password, or your recovery words'),
                    onPress: () => push(context, (_) => const SignInScreen()),
                  ),
                ]),
              ],
              // From an account they have (Matt, 2026-11-19: "add a sign up with discord sign up with telegram or
              // signal option"): the form filled in for them.
              SizedBox(height: t.space(6)),
              if (_from == null)
                SignUpFromSection(onFilled: _fill)
              else
                SignUpFilled(profile: _from!, onClear: () => setState(() => _from = null)),
              SizedBox(height: t.space(8)),
              PaneSection(
                title: 'Your username',
                description: const Text('How people find you. Nobody sees your number; you don\'t need one.'),
                footer: _problem == null ? null : Text(_problem!, style: TextStyle(color: t.danger)),
                children: [field(_username, 'username', 'Username', caps: TextCapitalization.none, onSubmitted: (_) => _go())],
              ),
              SizedBox(height: t.space(6)),
              PaneSection(
                title: 'Your name',
                description: const Text('What your friends see. Sent to them only, never to the relay server.'),
                children: [field(_name, 'Your name', 'Name', onSubmitted: (_) => _go())],
              ),
              SizedBox(height: t.space(8)),
              PairButton(label: _busy ? 'Checking…' : me.ready ? 'Continue' : 'Connecting to the relay server…', icon: Lucide.arrowRight, onPressed: _busy || !me.ready ? null : _go),
              // Someone who already has an account (Matt, 2026-11-17: "We need to have a way to login to existing
              // accounts"): signed in here instead of starting as someone new; or an account made before the username.
              if (!Account.instance.signedIn) ...[
                SizedBox(height: t.space(8)),
                PaneSection(children: [
                  SettingRow(icon: AppIcon(Lucide.userPlus, size: 18), label: 'Create an account', hint: const Text('So you can sign in on another device'), onPress: () => push(context, (_) => const CreateAccountScreen())),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
