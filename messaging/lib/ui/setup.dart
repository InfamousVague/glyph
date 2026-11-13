import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../kit/settings_type.dart';
import '../sms.dart';

/// First launch: Android lets only the default SMS app send and keep texts, so the one thing to do is choose Ghost.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool _asking = false;
  bool _declined = false;

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
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.space(6), pad.top + t.space(10), t.space(6), pad.bottom + t.space(6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: t.lenOf('4.5rem'),
            height: t.lenOf('4.5rem'),
            decoration: BoxDecoration(color: t.color('app-ink'), borderRadius: BorderRadius.circular(t.lenOf('1.3rem'))),
            alignment: Alignment.center,
            child: AppIcon(Lucide.ghost, size: 38, color: t.color('app-paper')),
          ),
          SizedBox(height: t.space(6)),
          Text('Ghost Messaging', style: pageText(t, t.fontSize('3xl'), weight: 'bold')),
          SizedBox(height: t.space(3)),
          Text(
            'Your texts and picture messages, in Glacier. To send and receive them, Android needs Ghost to be your default SMS app.',
            style: pageText(t, t.fontSize('md'), color: t.color('app-ink-2'), height: 1.45),
          ),
          SizedBox(height: t.space(5)),
          _Point(icon: Lucide.messageSquare, text: 'Every conversation you already have is here: messages live in Android, not in an app.'),
          _Point(icon: Lucide.users, text: 'Contacts give names and photos; notifications let you reply without opening the app.'),
          _Point(icon: Lucide.rotateCcw, text: 'Change your mind any time in Android\'s Settings › Apps › Default apps.'),
          const Spacer(),
          if (_declined)
            Padding(
              padding: EdgeInsets.only(bottom: t.space(3)),
              child: Text('Ghost isn\'t the default yet. Android only lets the default app send texts.', style: pageText(t, t.fontSize('sm'), color: t.colorOf('#dd3a30'))),
            ),
          GlacierPressable(
            onPressed: _asking ? null : _go,
            builder: (context, state) => AnimatedScale(
              scale: state.pressed ? 0.97 : 1,
              duration: const Duration(milliseconds: 120),
              child: Container(
                height: t.lenOf('3.25rem'),
                decoration: BoxDecoration(color: t.color('app-ink'), borderRadius: BorderRadius.circular(t.radius('lg'))),
                alignment: Alignment.center,
                child: Text(_asking ? 'Waiting for Android…' : 'Set as default SMS app', style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-paper'))),
              ),
            ),
          ),
        ]),
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
