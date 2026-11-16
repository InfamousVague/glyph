import 'package:flutter/services.dart' show TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/lucide.g.dart';
import '../friends/buddies.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../me/me.dart';
import '../ui/computers.dart' show PairButton;
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
      if (name.isNotEmpty) {
        Me.instance.setProfile(displayName: name, bio: Me.instance.bio);
        Buddies.instance.shareProfile();
      }
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
                'Message and call your friends by username, sealed so only the two of you can read it. An iPhone keeps texts to Apple\'s Messages, so here it is friends, groups and calls over the internet.',
                style: pageText(t, t.fontSize('md'), color: t.color('app-ink-2'), height: 1.45),
              ),
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
            ],
          ),
        ),
      ),
    );
  }
}
