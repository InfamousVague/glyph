/// The first-run walkthrough, made as Ghost.md's (its lib/guide) and Ghost Keyboard's (its lib/onboarding) are (Matt,
/// 2026-11-15: "Look at how we do onboarding on Ghost KBD and Ghost Markdown with the optional voice guide through the
/// elevenlabs key and the vibrant colors and iconography for each step, mimick this on the setup of Ghost
/// Messaging"): a page at a time, each with a band of vivid colour and its icons (band.dart), a title, the words a
/// friendly voice says aloud (ElevenLabs, made at build time with the key: narration.dart, tool/onboarding_voice.py),
/// and the step itself where there is one: Ghost as the texting app (or beside Google Messages), and a look.
///
/// Shown on first launch, until Ghost can send and receive texts and the walkthrough is finished; Settings › About
/// replays it. On the texts page Next waits until Ghost can send texts, and Skip appears once it can.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/lucide_more.dart';
import '../backgrounds.dart';
import '../kit/settings_type.dart';
import '../sms.dart';
import '../ui/setup.dart';
import 'band.dart';
import 'narration.dart';

/// How one page looks: its wash, its sign and the tiles round it.
@immutable
class GuideLook {
  const GuideLook(this.hues, this.icon, this.tiles);
  final List<String> hues;
  final LucideIcon icon;
  final List<LucideIcon> tiles;
  Color get hue => guideHues[hues.first]!.$1;
}

/// The pages, in order: an id (narration.dart's, and its voice's file), a title, and a look. Six, about Ghost as one
/// messenger for everyone (Matt, 2026-11-15: "Rework the onboarding to be a bit shorter and have it focus on the fact
/// that ghost is an all in one messenger"); contacts and notifications are asked for as the app opens (lib/main.dart).
const List<(String, String, GuideLook)> guidePages = [
  ('welcome', 'Everyone, in one place', GuideLook(['indigo', 'purple', 'rose'], Lucide.ghost, [Lucide.messageSquare, Lucide.users, LucideMore.headphones, Lucide.lock])),
  ('texts', 'Start with your texts', GuideLook(['green', 'mint', 'cyan'], LucideMore.smartphone, [Lucide.messageSquare, Lucide.shieldCheck, Lucide.link, Lucide.check])),
  ('together', 'Texts and chats, side by side', GuideLook(['blue', 'indigo', 'purple'], Lucide.users, [Lucide.lock, Lucide.sticker, Lucide.atSign, LucideMore.smile])),
  ('calls', 'Drop in, out loud', GuideLook(['rose', 'red', 'orange'], LucideMore.headphones, [Lucide.mic, Lucide.video, Lucide.users, Lucide.link])),
  ('everywhere', 'On every screen', GuideLook(['cyan', 'blue', 'indigo'], Lucide.laptop, [LucideMore.qrCode, LucideMore.smartphone, Lucide.refreshCw, Lucide.messageSquare])),
  ('start', 'You\'re in', GuideLook(['magenta', 'rose', 'orange'], LucideMore.rocket, [Lucide.palette, Lucide.sunMoon, Lucide.sparkles, Lucide.messageSquare])),
];

/// Plays a page's voice, and stops it (android MainActivity's "ghost/guide" channel). Where nothing answers (a
/// computer, a test) the page's words are there all the same.
class GuideVoice {
  const GuideVoice();
  static const _channel = MethodChannel('ghost/guide');

  Future<void> play(String asset) async {
    try {
      await _channel.invokeMethod<bool>('play', {'asset': asset});
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}

/// Opens the walkthrough over the app again (Settings › About).
Future<void> openOnboarding(BuildContext context) => Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (context, _, _) => const Onboarding(replay: true),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );

class Onboarding extends StatefulWidget {
  const Onboarding({super.key, this.onDone, this.replay = false, this.voice = const GuideVoice(), this.initialStatus});

  /// Finished or skipped; on a replay the walkthrough closes itself instead.
  final VoidCallback? onDone;
  final bool replay;
  final GuideVoice voice;

  /// For a picture: how things stand, so nothing is asked of Android.
  @visibleForTesting
  final SmsStatus? initialStatus;

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> with WidgetsBindingObserver {
  final PageController _pager = PageController();
  int _page = 0;
  SmsStatus? _status;

  /// The voice, on unless switched off; kept, as Ghost.md keeps its own.
  bool get _voiceOn => AppState.of(context).flag('guide_voice');

  /// Ghost can send and receive texts: the default, or beside Google Messages.
  bool get _usable => widget.replay || (_status?.usable ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _status = widget.initialStatus;
    if (widget.initialStatus == null) _look();
    WidgetsBinding.instance.addPostFrameCallback((_) => _say());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.voice.stop();
    _pager.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _look();
    } else if (state == AppLifecycleState.paused) {
      widget.voice.stop();
    }
  }

  Future<void> _look() async {
    try {
      final s = await Sms.instance.status();
      if (mounted) setState(() => _status = s);
    } catch (_) {}
  }

  Future<void> _say() async {
    if (!mounted || !_voiceOn) return;
    await widget.voice.play(narrationAsset(guidePages[_page].$1));
  }

  void _go(int page) {
    if (page < 0 || page >= guidePages.length) return;
    _pager.animateToPage(page, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  /// Next waits on the texts page until Ghost can send texts.
  bool get _canGoOn => guidePages[_page].$1 != 'texts' || _usable;

  void _next() {
    if (!_canGoOn) return;
    _page == guidePages.length - 1 ? _finish() : _go(_page + 1);
  }

  void _finish() {
    widget.voice.stop();
    AppState.of(context).setFlag('onboarded', true);
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    final look = guidePages[_page].$3;
    final last = _page == guidePages.length - 1;
    final voice = _voiceOn;
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Padding(
        padding: EdgeInsets.only(top: pad.top, bottom: pad.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The voice on or off, and the way out.
            Padding(
              padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), 0),
              child: Row(children: [
                GuideButton(
                  key: const ValueKey('guide-voice'),
                  label: voice ? 'Voice on' : 'Voice off',
                  icon: voice ? Lucide.volume2 : Lucide.minus,
                  look: GuideButtonLook.ring,
                  onPress: () {
                    AppState.of(context).setFlag('guide_voice', !voice);
                    voice ? widget.voice.stop() : WidgetsBinding.instance.addPostFrameCallback((_) => _say());
                  },
                ),
                const Spacer(),
                // Once Ghost can send texts there is nothing left that must be done.
                if (_usable) GuideButton(key: const ValueKey('guide-skip'), label: widget.replay ? 'Close' : 'Skip', look: GuideButtonLook.word, onPress: _finish),
              ]),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                itemCount: guidePages.length,
                // Swiped past the texts page only once it is done.
                physics: _canGoOn ? const PageScrollPhysics() : const NeverScrollableScrollPhysics(),
                onPageChanged: (page) {
                  setState(() => _page = page);
                  widget.voice.stop().then((_) => _say());
                },
                itemBuilder: (context, i) => _pageAt(context, i),
              ),
            ),
            // The dots, and back and next.
            Padding(
              padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(4)),
              child: Row(children: [
                for (var i = 0; i < guidePages.length; i++)
                  AnimatedContainer(
                    duration: t.reducedMotion ? Duration.zero : const Duration(milliseconds: 220),
                    margin: EdgeInsets.only(right: t.space(1)),
                    width: i == _page ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(color: i == _page ? look.hue : t.color('app-rule'), borderRadius: BorderRadius.circular(4)),
                  ),
                const Spacer(),
                if (_page > 0) ...[GuideButton(label: 'Back', look: GuideButtonLook.ring, onPress: () => _go(_page - 1)), SizedBox(width: t.space(2))],
                GuideButton(
                  key: const ValueKey('guide-next'),
                  label: last ? 'Say hi' : 'Next',
                  icon: last ? Lucide.check : Lucide.arrowRight,
                  look: GuideButtonLook.filled,
                  color: look.hue,
                  large: true,
                  onPress: _canGoOn ? _next : null,
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageAt(BuildContext context, int i) {
    final t = context.tokens;
    final (id, title, look) = guidePages[i];
    final screen = MediaQuery.sizeOf(context);
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(3)),
      children: [
        HueBand(
          key: ValueKey('band-$id'),
          colours: hueColours(look.hues),
          height: (screen.height * 0.32).clamp(180.0, 320.0).toDouble(),
          sign: (h, w) => bandDisc(look.icon, height: h, width: w),
          tiles: [for (final icon in look.tiles) bandIcon(icon)],
        ),
        SizedBox(height: t.space(5)),
        Semantics(header: true, child: Text(title, style: pageText(t, t.fontSize('3xl'), weight: 'bold', height: 1.1, color: t.color('app-ink')))),
        SizedBox(height: t.space(3)),
        Text(narration[id]!, style: pageText(t, t.fontSize('md'), height: 1.5, color: t.color('app-ink-2'))),
        SizedBox(height: t.space(5)),
        ..._step(context, id, look),
      ],
    );
  }

  /// The page's own step, where it has one.
  List<Widget> _step(BuildContext context, String id, GuideLook look) {
    final t = context.tokens;
    final app = AppState.of(context);
    Widget done(String words) => Row(children: [
          AppIcon(Lucide.circleCheck, size: 20, color: look.hue),
          SizedBox(width: t.space(2)),
          Expanded(child: Text(words, style: pageText(t, t.fontSize('md'), weight: 'medium', color: t.color('app-ink')))),
        ]);
    Widget hint(String words) => Text(words, style: pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('app-ink-3')));
    switch (id) {
      case 'texts':
        if (widget.replay) return [done('Ghost can send and receive your texts.')];
        if (widget.initialStatus != null && _usable) return [done(_status!.isDefault ? 'Ghost is your texting app.' : 'Ghost is working beside Google Messages.')];
        return [TextsStep(hue: look.hue, onDone: _look)];
      case 'everywhere':
        return [hint('Get it at gogho.st, then pair it in Settings › Computers. You can do this any time.')];
      case 'start':
        return [
          GlacierSegmentedControl(
            options: const [
              GlacierSegmentedOption(value: 'system', label: Text('System')),
              GlacierSegmentedOption(value: 'light', label: Text('Light')),
              GlacierSegmentedOption(value: 'dark', label: Text('Dark')),
            ],
            value: app.theme,
            onValueChange: app.setTheme,
            fullWidth: true,
            ariaLabel: 'Light or dark',
          ),
          SizedBox(height: t.space(4)),
          Text('Your bubbles', style: pageText(t, t.fontSize('md'), weight: 'medium', color: t.color('app-ink'))),
          SizedBox(height: t.space(2)),
          BubbleSwatches(chosen: app.bubble == 'wallpaper' ? 'white' : app.bubble, onPick: app.setBubble),
        ];
      default:
        return const [];
    }
  }
}

/// How a capsule is drawn: filled in the page's colour, a ring, or a word alone.
enum GuideButtonLook { filled, ring, word }

/// A capsule button, as Ghost Keyboard's walkthrough has them (its MarketButton): [color] fills a filled one, with
/// white words on it.
class GuideButton extends StatelessWidget {
  const GuideButton({super.key, required this.label, required this.onPress, this.look = GuideButtonLook.ring, this.color, this.icon, this.large = false});

  final String label;
  final VoidCallback? onPress;
  final GuideButtonLook look;
  final Color? color;
  final LucideIcon? icon;

  /// A thumb's height, for the page's one main button.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final off = onPress == null;
    final height = large ? t.lenOf('2.6rem') : t.lenOf('1.9rem');
    return GlacierPressable(
      onPressed: onPress,
      semanticLabel: label,
      builder: (context, state) {
        final (Color ground, Color ink, Color? ring) = switch (look) {
          GuideButtonLook.filled => (color ?? t.color('app-ink'), const Color(0xFFFFFFFF), null),
          GuideButtonLook.ring => (const Color(0x00000000), t.color('app-ink'), t.color('app-rule')),
          GuideButtonLook.word => (const Color(0x00000000), t.color('app-ink-2'), null),
        };
        return GlacierFocusRing(
          visible: state.focused,
          radius: height / 2,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: off ? 0.45 : (state.pressed ? 0.8 : 1),
            child: Container(
              height: height,
              padding: EdgeInsets.symmetric(horizontal: large ? t.space(5) : t.space(3)),
              decoration: ShapeDecoration(
                color: ground,
                shape: StadiumBorder(side: ring == null ? BorderSide.none : BorderSide(color: ring, width: t.len('glacier-hairline'))),
              ),
              child: ExcludeSemantics(
                child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (icon != null) ...[AppIcon(icon!, size: large ? 16 : 14, strokeWidth: 2.3, color: ink, wash: false), SizedBox(width: t.space(1))],
                  Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, large ? t.fontSize('md') : t.fontSize('sm'), weight: 'semibold', color: ink))),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
