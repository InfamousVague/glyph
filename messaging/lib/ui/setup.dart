import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_type.dart';
import '../sms.dart';

/// First launch: Android lets only the default SMS app send and keep texts, so the one thing to do is choose Ghost.
///
/// Before that, what catches people coming from Google Messages or Samsung Messages (android/.../Arriving.kt; Matt,
/// 2026-11-13, of a friend whose chats "didn't load" and whose texts stopped arriving: "can you detect this somehow
/// and then instruct the user how to fix it?"): their RCS chats stay in that app, and while RCS is on there, people
/// who use it go on sending chats that never arrive as texts. The screen names the app being left and leads to its
/// settings to turn RCS chats off first. And where Android refuses the switch to a copy from outside a store, it
/// leads to Android's page for the app, where "Allow restricted settings" is.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with WidgetsBindingObserver {
  bool _asking = false;
  bool _declined = false;
  Arriving _arriving = const Arriving();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _look();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from the old app's settings, or Android's page for this one.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _look();
  }

  Future<void> _look() async {
    try {
      final a = await Sms.instance.arriving();
      if (mounted) setState(() => _arriving = a);
    } catch (_) {}
  }

  Future<void> _go() async {
    setState(() => _asking = true);
    final ok = await Sms.instance.requestDefault();
    if (ok) {
      await Sms.instance.requestPermissions();
      widget.onDone();
    } else if (mounted) {
      setState(() { _asking = false; _declined = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    final a = _arriving;
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // The status bar's room stays clear: what scrolls goes under the page's edge, not under the clock.
        SizedBox(height: pad.top),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(t.space(6), t.space(10), t.space(6), t.space(4)),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: t.lenOf('4.5rem'),
                  height: t.lenOf('4.5rem'),
                  // The app's icon as it is on the home screen: the white ghost on black, in either theme.
                  decoration: BoxDecoration(color: const Color(0xFF000000), borderRadius: BorderRadius.circular(t.lenOf('1.3rem')), border: Border.all(color: t.color('app-rule'))),
                  alignment: Alignment.center,
                  child: Image.asset('assets/art/ghost-mark.png', width: t.lenOf('2.9rem'), height: t.lenOf('2.9rem')),
                ),
              ),
              SizedBox(height: t.space(6)),
              Text('Ghost Messaging', style: pageText(t, t.fontSize('3xl'), weight: 'bold')),
              SizedBox(height: t.space(3)),
              Text(
                'Your texts and picture messages, in Glacier. To send and receive them, Android needs Ghost to be your default SMS app.',
                style: pageText(t, t.fontSize('md'), color: t.color('app-ink-2'), height: 1.45),
              ),
              SizedBox(height: t.space(5)),
              if (a.rcsLikely) ...[
                _Card(
                  icon: Lucide.triangleAlert,
                  title: 'Coming from ${a.app}? Do this first',
                  children: [
                    _Step(number: '1', text: 'Turn off RCS chats in ${a.app}. In its settings, open RCS chats and switch it off. Leave it on, and texts from people who use RCS keep going there and won\'t reach you here.'),
                    _Step(number: '2', text: 'Your RCS chats stay in ${a.app}. Android keeps them where no other app can read them, so they won\'t appear here. They are not deleted: they are there again if you switch back. Texts and picture messages (SMS and MMS) all appear here.'),
                    SizedBox(height: t.space(2)),
                    _Button(label: 'Open ${a.app} settings', onPressed: () => Sms.instance.openOldApp()),
                  ],
                ),
                SizedBox(height: t.space(5)),
              ],
              _Point(icon: Lucide.messageSquare, text: 'Every text conversation you already have is here: texts live in Android, not in an app.'),
              _Point(icon: Lucide.users, text: 'Contacts give names and photos; notifications let you reply without opening the app.'),
              _Point(icon: Lucide.rotateCcw, text: 'Change your mind any time in Android\'s Settings › Apps › Default apps. Nothing is deleted either way.'),
              if (_declined) ...[
                SizedBox(height: t.space(3)),
                _Card(
                  icon: Lucide.circleAlert,
                  danger: true,
                  title: 'Ghost isn\'t the default yet',
                  children: [
                    Text(
                      a.sideloaded
                          ? 'If Android said the setting is restricted or unavailable, that is because this copy didn\'t come from the Play Store. Open Android\'s page for Ghost Messaging, tap ⋮ at the top, choose Allow restricted settings, then come back and try again.'
                          : 'Android only lets the default app send and receive texts. Try again, and choose Ghost Messaging when Android asks.',
                      style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'), height: 1.45),
                    ),
                    if (a.sideloaded) ...[
                      SizedBox(height: t.space(3)),
                      _Button(label: 'Open Android\'s page for Ghost Messaging', onPressed: () => Sms.instance.openAppInfo()),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(t.space(6), t.space(2), t.space(6), pad.bottom + t.space(6)),
          child: GlacierPressable(
            onPressed: _asking ? null : _go,
            builder: (context, state) => AnimatedScale(
              scale: state.pressed ? 0.97 : 1,
              duration: const Duration(milliseconds: 120),
              child: Container(
                height: t.lenOf('3.25rem'),
                decoration: BoxDecoration(color: t.color('app-ink'), borderRadius: BorderRadius.circular(t.radius('lg'))),
                alignment: Alignment.center,
                child: Text(_asking ? 'Waiting for Android…' : (_declined ? 'Try again' : 'Set as default SMS app'), style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-paper'))),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A boxed note with a heading: what to do before switching, or why the switch did not happen.
class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.title, required this.children, this.danger = false});
  final LucideIcon icon;
  final String title;
  final List<Widget> children;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = danger ? t.colorOf('#dd3a30') : t.color('app-ink');
    return Container(
      padding: EdgeInsets.all(t.space(4)),
      decoration: BoxDecoration(
        color: t.color('app-paper-2'),
        borderRadius: BorderRadius.circular(t.radius('lg')),
        border: Border.all(color: danger ? ink : t.color('app-rule')),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: AppIcon(icon, size: 18, color: ink)),
          SizedBox(width: t.space(2)),
          Expanded(child: Text(title, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: ink))),
        ]),
        SizedBox(height: t.space(3)),
        ...children,
      ]),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});
  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(3)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: t.lenOf('1.4rem'),
          height: t.lenOf('1.4rem'),
          decoration: BoxDecoration(shape: BoxShape.circle, color: t.color('app-ink')),
          alignment: Alignment.center,
          child: Text(number, style: pageText(t, t.fontSize('xs'), weight: 'bold', color: t.color('app-paper'))),
        ),
        SizedBox(width: t.space(3)),
        Expanded(child: Text(text, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'), height: 1.45))),
      ]),
    );
  }
}

/// A second-rank button: an outline, where the screen's one filled button is the switch itself.
class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => Container(
        constraints: BoxConstraints(minHeight: t.lenOf('2.75rem')),
        padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(2)),
        decoration: BoxDecoration(
          color: state.pressed ? t.color('app-paper-3') : const Color(0x00000000),
          borderRadius: BorderRadius.circular(t.radius('md')),
          border: Border.all(color: t.color('app-ink-3')),
        ),
        alignment: Alignment.center,
        child: Text(label, textAlign: TextAlign.center, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink'))),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text});
  final LucideIcon icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(3)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: AppIcon(icon, size: 18, color: t.color('app-ink-2'))),
        SizedBox(width: t.space(3)),
        Expanded(child: Text(text, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'), height: 1.45))),
      ]),
    );
  }
}
