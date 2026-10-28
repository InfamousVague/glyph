/// What is waiting on the person, shown where they land (the home page) and in the sidebar: an update, an invitation
/// to an organization, the Academy's invitation, and the voice model while it is not ready yet. A port of
/// `src/app/notes/Notices.tsx` with Notices.module.css.
///
/// Each says nothing at all when there is nothing to say (a `SizedBox.shrink()`), which the sidebar relies on to
/// hide its notices' room.
///
/// What differs from the web:
/// - **Each is fed plain data.** The page's components read the app themselves: `core/ota.ts`'s `Updates`
///   ([AppUpdates], with [ApkUpdate] for its `apk`), `capture/useVoiceModel.ts`'s state ([VoiceModel]),
///   `capture/refine.ts`'s download ([RefiningNotice]'s two numbers), and the notifications' feed with the account's
///   organizations for the invitation. Here whoever has those hands them in.
/// - **[InviteNotice] is given its sentence and its buttons.** The page found the newest pending invitation itself
///   and drew `settings/InviteActions.tsx` beside it; neither the choosing nor those buttons are ported, so the
///   sentence (`sentenceOf`, lib/core/notifications.dart) and an [InviteNotice.actions] widget are the caller's.
/// - The foil on the update card drifts as the page's does (`@keyframes holo`, 11s), drawn by a painter where the
///   page moved two background layers.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../home/home_parts.dart';
import '../home/home_text.dart';

/// A download's size as its line says it: whole megabytes (`megabytes`, core/ai.ts).
int megabytes(num bytes) => (bytes / 1e6).round();

// ---- the update ---------------------------------------------------------------------------------------------------

/// Where a new version of the app itself is (`ApkState`, core/ota.ts), with the version it is of.
sealed class ApkUpdate {
  const ApkUpdate();
}

/// Nothing newer (`{ kind: 'none' }`), or nothing this notice says anything about.
class ApkNone extends ApkUpdate {
  const ApkNone();
}

/// A new version is out, to install (`'available'`).
class ApkAvailable extends ApkUpdate {
  const ApkAvailable(this.version);
  final String version;
}

/// It did not install, and why (`'failed'`).
class ApkFailed extends ApkUpdate {
  const ApkFailed(this.version, this.message);
  final String version;
  final String message;
}

/// The phone has not let the app install apps yet (`'needs-permission'`).
class ApkNeedsPermission extends ApkUpdate {
  const ApkNeedsPermission();
}

/// It is coming down (`'downloading'`): how many bytes of how many.
class ApkDownloading extends ApkUpdate {
  const ApkDownloading(this.version, {required this.received, required this.total});
  final String version;
  final int received;
  final int total;
}

/// Android's own dialog is on top, or was dismissed (`'installing'`).
class ApkInstalling extends ApkUpdate {
  const ApkInstalling(this.version);
  final String version;
}

/// The Mac's: the new version is downloaded, checked and in place, and a restart swaps it in (core/updates.dart
/// `ApkPhaseReady`).
class ApkReady extends ApkUpdate {
  const ApkReady(this.version);
  final String version;
}

/// The Mac's: the app is quitting to open again as the new version (`ApkPhaseRestarting`).
class ApkRestarting extends ApkUpdate {
  const ApkRestarting(this.version);
  final String version;
}

/// What the update card is told (`Updates`, core/ota.ts, the part the card reads).
@immutable
class AppUpdates {
  const AppUpdates({this.ready = false, this.apk = const ApkNone(), this.onInstall, this.onReload, this.onRestart});

  /// A new version of the page is downloaded and waiting for a reload (`ready`).
  final bool ready;
  final ApkUpdate apk;

  /// Installs the new version, or asks again (`installApk`).
  final VoidCallback? onInstall;

  /// Starts the app again on the version already downloaded (`reload`).
  final VoidCallback? onReload;

  /// The Mac's "Restart to update": swaps in the version [ApkReady] stands for and opens it.
  final VoidCallback? onRestart;
}

/// The update's card when there is something newer to run (`UpdateNotice`): white and holographic, the one piece of
/// colour on the home page. Fed [AppUpdates] where the page read `core/ota.ts`.
class UpdateNotice extends StatelessWidget {
  const UpdateNotice({super.key, required this.updates});

  final AppUpdates updates;

  @override
  Widget build(BuildContext context) {
    final apk = updates.apk;
    switch (apk) {
      case ApkAvailable(:final version):
        return _UpdateCard(text: 'Ghost.md $version is out.', action: 'Install', onAction: updates.onInstall, ghost: true);
      case ApkFailed(:final version, :final message):
        return _UpdateCard(text: 'Ghost.md $version didn’t install. $message', action: 'Try again', onAction: updates.onInstall);
      case ApkNeedsPermission():
        return _UpdateCard(text: 'Let Ghost.md install apps, then come back.', action: 'Install', onAction: updates.onInstall);
      case ApkDownloading(:final version, :final received, :final total):
        return _UpdateCard(text: 'Downloading Ghost.md $version, ${megabytes(received)} of ${megabytes(total)} MB.', progress: total > 0 ? received / total : 0, working: true);
      case ApkInstalling(:final version):
        // Android's own dialog is on top now; this is what is left if it is dismissed.
        return _UpdateCard(text: 'Ghost.md $version is waiting on Android.', action: 'Open', onAction: updates.onInstall);
      case ApkReady(:final version):
        return _UpdateCard(text: 'Ghost.md $version is ready.', action: 'Restart to update', onAction: updates.onRestart, ghost: true);
      case ApkRestarting(:final version):
        return _UpdateCard(text: 'Restarting into Ghost.md $version.', working: true, workingLabel: 'Restarting');
      case ApkNone():
        if (updates.ready) return _UpdateCard(text: 'A new version of Ghost.md is ready.', action: 'Reload', onAction: updates.onReload, ghost: true);
        return const SizedBox.shrink();
    }
  }
}

/// `.update`: the update's card: its words, what to do about it, and while it downloads, how far it has got.
class _UpdateCard extends StatefulWidget {
  const _UpdateCard({required this.text, this.action, this.onAction, this.progress, this.working = false, this.workingLabel = 'Downloading', this.ghost = false});

  final String text;
  final String? action;
  final VoidCallback? onAction;
  final double? progress;

  /// The update is coming down now: cogs turn beside the words while it does.
  final bool working;

  /// What the cogs say they are doing, to a screen reader.
  final String workingLabel;

  /// An update is waiting to be taken: the ghost with its parcel beside the words.
  final bool ghost;

  @override
  State<_UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<_UpdateCard> with SingleTickerProviderStateMixin {
  // `animation: holo 11s linear infinite`
  late final AnimationController _holo = AnimationController(vsync: this, duration: const Duration(seconds: 11));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // `@media (prefers-reduced-motion: reduce) { .update { animation: none } }`
    if (!context.tokens.reducedMotion) _holo.repeat();
  }

  @override
  void dispose() {
    _holo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // `--update-ink: oklch(0.18 0.012 260)`: near-black words and a black pill, in both themes.
    final ink = t.colorOf('oklch(0.18 0.012 260)');
    final sm = t.fontSize('sm');
    final leading = t.len('glacier-leading-sm');
    final radius = BorderRadius.circular(t.radius('lg'));
    final action = widget.action, onAction = widget.onAction, progress = widget.progress;
    final settle = t.transition('app-settle');
    final words = pageText(t, sm, weight: 'medium', color: ink, height: leading);
    // The ghost's place, `tiny` (art/ghost.dart: three rems tall), and the card's one height: that, the button's
    // `min-block-size: var(--glacier-space-10)`, or two lines of words, whichever is most.
    final rem = t.lenOf('1rem');
    final leadHeight = 3 * rem, leadWidth = leadHeight * GhostScene.update.ratio;
    final body = math.max(leadHeight, math.max(t.space(10), 2 * sm * leading));
    final card = Container(
      key: const ValueKey('update-notice'),
      // `margin: 0 0 var(--glacier-space-5)`
      margin: EdgeInsets.only(bottom: t.space(5)),
      // `box-shadow: ..., 0 10px 30px rgba(0, 0, 0, 0.22)`
      decoration: BoxDecoration(borderRadius: radius, boxShadow: const [BoxShadow(color: Color(0x38000000), offset: Offset(0, 10), blurRadius: 30)]),
      child: ClipRRect(
        borderRadius: radius,
        child: CustomPaint(
          painter: _Holo(
            drift: _holo,
            spectrum: [for (final stop in const ['0.93 0.085 350', '0.94 0.075 215', '0.96 0.075 135', '0.95 0.09 80', '0.93 0.08 300', '0.93 0.085 350']) t.colorOf('oklch($stop)')],
            radius: t.radius('lg'),
          ),
          child: Stack(
            children: [
              Padding(
                // `padding: var(--glacier-space-3) var(--glacier-space-3) var(--glacier-space-3) var(--glacier-space-4)`
                padding: EdgeInsetsDirectional.fromSTEB(t.space(4), t.space(3), t.space(3), t.space(3)),
                // One size from the first word to the restart (Matt, 2026-10-24: "the ghost update banner shifts when
                // updating pleaase make sure it always takes up the same space"): the card is as tall as the tallest
                // of its states, the ghost, the button and two lines of words, whichever it is in; the ghost's place
                // is always kept, the ghost in it while an update waits or the cogs while it works, and empty when it says why one did
                // not go; and the words take two lines at most.
                child: SizedBox(
                  key: const ValueKey('update-body'),
                  height: body,
                  child: Row(
                    // `display: flex; align-items: center; gap: var(--glacier-space-3)`
                    spacing: t.space(3),
                    children: [
                      SizedBox(
                        key: const ValueKey('update-lead'),
                        width: leadWidth,
                        height: leadHeight,
                        child: Center(
                          child: widget.working
                              ? WorkingGears(label: widget.workingLabel, size: sm * 1.6, color: ink)
                              : widget.ghost
                              ? Ghost(scene: GhostScene.update, size: GhostSize.tiny, color: ink)
                              : null,
                        ),
                      ),
                      Expanded(
                        // `.updateText { flex: 1; font-size: sm; line-height: leading-sm; font-weight: medium }`
                        child: Text(widget.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: words),
                      ),
                      if (action != null && onAction != null) _Action(key: const ValueKey('update-action'), label: action, onPressed: onAction, background: ink, color: const Color(0xFFFFFFFF), ring: ink),
                    ],
                  ),
                ),
              ),
              if (progress != null)
                // `.updateBar { position: absolute; inset: auto 0 0; block-size: 3px; background: rgba(0, 0, 0, 0.12) }`
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 3,
                  child: ExcludeSemantics(
                    child: ColoredBox(
                      color: const Color(0x1F000000),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        // `inline-size: <whole percent>%; transition: inline-size 300ms linear`
                        child: AnimatedFractionallySizedBox(
                          key: const ValueKey('update-progress'),
                          duration: const Duration(milliseconds: 300),
                          widthFactor: (progress.clamp(0.0, 1.0) * 100).round() / 100,
                          heightFactor: 1,
                          child: ColoredBox(color: ink),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    // `animation: update-in var(--app-settle) both`: from a little above, and clear.
    return Semantics(container: true, liveRegion: true, child: _In(duration: settle.duration, curve: settle.curve, child: card));
  }
}

/// `@keyframes update-in { from { opacity: 0; transform: translateY(-6px) } }`, still under reduced motion.
class _In extends StatelessWidget {
  const _In({required this.duration, required this.curve, required this.child});

  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final still = context.tokens.reducedMotion;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? 1 : 0, end: 1),
      duration: duration,
      curve: curve,
      child: child,
      builder: (context, at, child) => Opacity(opacity: at.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, -6 * (1 - at)), child: child)),
    );
  }
}

/// The update card's ground: white, under a faint pastel spectrum drifting one way and a band of light crossing the
/// other, the way a holographic sticker catches a lamp, and the two inset lines of white round it.
class _Holo extends CustomPainter {
  _Holo({required this.drift, required this.spectrum, required this.radius}) : super(repaint: drift);

  final Animation<double> drift;
  final List<Color> spectrum;
  final double radius;

  /// A CSS `linear-gradient(<degrees>deg, ...)` over [rect]: the line through its middle at that angle, as long as
  /// the rectangle is across it.
  static ui.Gradient _linear(Rect rect, double degrees, List<Color> colors, List<double> stops) {
    final a = degrees * math.pi / 180;
    final dx = math.sin(a), dy = -math.cos(a);
    final half = (rect.width * dx.abs() + rect.height * dy.abs()) / 2;
    final c = rect.center;
    return ui.Gradient.linear(c - Offset(dx, dy) * half, c + Offset(dx, dy) * half, colors, stops);
  }

  /// One background layer: its picture [times] the box wide, tiled, and slid as `background-position` slides it from
  /// `0%` to [to] times 100%: by `(box - picture) * position`.
  void _layer(Canvas canvas, Size size, {required double times, required double to, required double degrees, required List<Color> colors, required List<double> stops}) {
    final tile = size.width * times;
    final slide = (size.width - tile) * to * drift.value;
    var x = slide % tile;
    if (x > 0) x -= tile;
    for (; x < size.width; x += tile) {
      final rect = Rect.fromLTWH(x, 0, tile, size.height);
      canvas.drawRect(rect, Paint()..shader = _linear(rect, degrees, colors, stops));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    // `background-color: #fff`
    canvas.drawRect(box, Paint()..color = const Color(0xFFFFFFFF));
    // The spectrum: `linear-gradient(100deg, ...)`, `background-size: 320% 100%`, to `320% 0`.
    _layer(canvas, size, times: 3.2, to: 3.2, degrees: 100, colors: spectrum, stops: const [0, 0.2, 0.4, 0.6, 0.8, 1]);
    // The light: `linear-gradient(115deg, ...)`, `background-size: 260% 100%`, to `-260% 0`.
    const clear = Color(0x00FFFFFF);
    _layer(canvas, size, times: 2.6, to: -2.6, degrees: 115, colors: const [clear, Color(0xD9FFFFFF), clear, clear, Color(0xB3FFFFFF), clear], stops: const [0, 0.18, 0.34, 0.62, 0.78, 1]);
    // `inset 0 0 0 1px rgba(255, 255, 255, 0.85), inset 0 1px 0 rgba(255, 255, 255, 0.95)`
    final edge = RRect.fromRectAndRadius(box.deflate(0.5), Radius.circular(math.max(0, radius - 0.5)));
    canvas.drawRRect(edge, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xD9FFFFFF));
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, radius));
    canvas.drawRRect(edge, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xF2FFFFFF));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Holo old) => old.radius != radius || old.spectrum != spectrum;
}

/// `.updateAction`, `.learnAction`: a card's one button, a filled pill.
class _Action extends StatelessWidget {
  const _Action({super.key, required this.label, required this.onPressed, required this.background, required this.color, this.ring});

  final String label;
  final VoidCallback onPressed;
  final Color background;
  final Color color;

  /// The focus ring's colour where the card sets its own (`outline: 2px solid var(--update-ink)`).
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPressed,
      builder: (context, state) => Transform.scale(
        // `:active { transform: scale(0.96) }`
        scale: state.pressed ? 0.96 : 1,
        child: GlacierFocusRing(
          visible: state.focused,
          color: ring,
          child: Container(
            // `min-block-size: var(--glacier-space-10); padding: 0 var(--glacier-space-4); border-radius: full`
            constraints: BoxConstraints(minHeight: t.space(10)),
            padding: EdgeInsets.symmetric(horizontal: t.space(4)),
            decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(t.radius('full'))),
            // `font-size: sm; font-weight: bold`, in the middle of the pill.
            child: Center(widthFactor: 1, heightFactor: 1, child: Text(label, maxLines: 1, softWrap: false, style: pageText(t, t.fontSize('sm'), weight: 'bold', color: color))),
          ),
        ),
      ),
    );
  }
}

// ---- the paper cards ----------------------------------------------------------------------------------------------

/// `.learn`: the Academy's card and an invitation's: the update card's shape and place, in the app's own ink and
/// paper. Its words take the room there is, and what there is to do keeps to the end, dropping under the words where
/// the card is narrow (the docked sidebar's list) rather than squeezing them to a word a line.
class _Paper extends StatelessWidget {
  const _Paper({super.key, required this.icon, required this.lead, required this.line, required this.actions, this.status = false});

  final LucideIcon icon;
  final String lead;
  final String line;
  final Widget actions;
  final bool status;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final md = t.fontSize('md'), sm = t.fontSize('sm');
    final muted = t.color('glacier-text-muted');
    final settle = t.transition('app-settle');
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // `.learnLead { display: flex; align-items: center; gap: var(--glacier-space-2); font-size: md;
        //   line-height: 1.25; font-weight: semibold }`
        Row(
          spacing: t.space(2),
          children: [
            // `.learnMark { flex: none; color: var(--glacier-text-muted) }`, `size={17} strokeWidth={1.9}`
            AppIcon(icon, size: 17, strokeWidth: 1.9, color: muted),
            Expanded(child: CssLines(lineHeight: 1.25 * md, child: Text(lead, style: pageText(t, md, weight: 'semibold', color: t.color('glacier-text'), height: 1.25)))),
          ],
        ),
        // `.learnLine { margin: 2px 0 0; font-size: sm; line-height: leading-sm; color: var(--glacier-text-muted) }`
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: CssLines(lineHeight: t.len('glacier-leading-sm') * sm, child: Text(line, style: pageText(t, sm, color: muted, height: t.len('glacier-leading-sm')))),
        ),
      ],
    );
    final card = Container(
      // `margin: 0 0 var(--glacier-space-5)`
      margin: EdgeInsets.only(bottom: t.space(5)),
      // `padding: var(--glacier-space-3) var(--glacier-space-3) var(--glacier-space-3) var(--glacier-space-4)`
      padding: EdgeInsetsDirectional.fromSTEB(t.space(4), t.space(3), t.space(3), t.space(3)),
      decoration: BoxDecoration(
        // `border: var(--glacier-hairline) solid var(--glacier-border-subtle); background: var(--app-paper-2)`
        color: t.color('app-paper-2'),
        border: Border.all(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')),
        borderRadius: BorderRadius.circular(t.radius('lg')),
      ),
      // `display: flex; align-items: center; flex-wrap: wrap; gap: var(--glacier-space-2) var(--glacier-space-3)`;
      // `.learnWords { flex: 1 1 9rem }`, `.learnDo { flex: none; margin-inline-start: auto }`.
      child: _WordsAndDo(columnGap: t.space(3), rowGap: t.space(2), basis: t.lenOf('9rem'), children: [words, actions]),
    );
    return Semantics(container: true, liveRegion: status, child: _In(duration: settle.duration, curve: settle.curve, child: card));
  }
}

/// Simple or advanced, asked once of an install from before there was a choice (GHST-103; Matt, 2026-10-18: new
/// installs choose in the walkthrough, "existing users see it on the card one time"). The same paper as the update
/// card, with the two modes as its actions; either puts the card away for good, and Settings has the choice from
/// then on, as Appearance's first card (Matt, 2026-10-24: "move the simple or advanced toggle under appearance"),
/// which the line names. Nothing to port: the choice is new with the Flutter app.
class ExperienceCard extends StatelessWidget {
  const ExperienceCard({super.key, required this.onPick});

  /// `simple` or `advanced` (lib/core/preferences.dart `experienceIds`).
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _Paper(
      key: const ValueKey('experience-card'),
      icon: Lucide.feather,
      lead: 'Simple or advanced?',
      line: 'Simple keeps notes, lists and to-dos in front and the rest behind More. Change it any time in Settings › Appearance.',
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: t.space(2),
        children: [
          _Action(label: 'Simple', onPressed: () => onPick('simple'), background: t.color('glacier-text'), color: t.color('glacier-bg')),
          _Action(label: 'Advanced', onPressed: () => onPick('advanced'), background: t.color('glacier-surface-raised'), color: t.color('glacier-text')),
        ],
      ),
    );
  }
}

/// The Academy, offered on the home screen (`AcademyCard`; Matt: "I'd like the academy page to show up on the home
/// screen kinda like the update banner for new users as a call to action banner"). Like the update card in shape and
/// place, unlike it in voice: this is an invitation, and is the paper it sits on. Nothing differs from the page.
class AcademyCard extends StatelessWidget {
  const AcademyCard({super.key, required this.onOpen, this.onHide});

  final VoidCallback onOpen;

  /// Puts the card away for good; without it there is no cross.
  final VoidCallback? onHide;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hide = onHide;
    return _Paper(
      key: const ValueKey('academy-card'),
      icon: Lucide.graduationCap,
      lead: 'Ghost Academy',
      line: 'Learn the marks, one at a time.',
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        // `.learnDo { display: flex; align-items: center; gap: var(--glacier-space-2) }`
        spacing: t.space(2),
        children: [
          // `.learnAction { background: var(--glacier-text); color: var(--glacier-bg) }`
          _Action(label: 'Start', onPressed: onOpen, background: t.color('glacier-text'), color: t.color('glacier-bg')),
          if (hide != null)
            GlacierPressable(
              onPressed: hide,
              semanticLabel: 'Not now',
              builder: (context, state) => GlacierFocusRing(
                visible: state.focused,
                child: SizedBox.square(
                  // `.learnHide { inline-size: var(--glacier-space-8); block-size: var(--glacier-space-8) }`
                  dimension: t.space(8),
                  // `color: var(--glacier-text-muted)`; hovered or pressed, `--glacier-text`.
                  child: Center(child: AppIcon(Lucide.x, size: 16, strokeWidth: 2.2, color: state.hovered || state.pressed ? t.color('glacier-text') : t.color('glacier-text-muted'))),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// An invitation to an organization, waiting (`InviteNotice`; Matt: "adding a team member should show them an
/// invite"). The Academy's card in shape and place. Differs from the page in being handed the invitation's
/// [sentence] and its [actions] (Accept and Decline), which the page found and drew itself; see the library doc.
class InviteNotice extends StatelessWidget {
  const InviteNotice({super.key, required this.sentence, required this.actions});

  /// "Sam invited you to Acme" (`sentenceOf`).
  final String sentence;

  /// Accept and Decline (`settings/InviteActions.tsx`).
  final Widget actions;

  @override
  Widget build(BuildContext context) =>
      _Paper(key: const ValueKey('invite-notice'), icon: Lucide.mail, lead: sentence, line: 'Accept to join; its workspace is made for you.', actions: actions, status: true);
}

// ---- the voice model ----------------------------------------------------------------------------------------------

/// Where the voice model is (`VoiceModelState`, capture/useVoiceModel.ts).
sealed class VoiceModel {
  const VoiceModel();
}

/// Ready, not asked for on this device, or still being looked for: nothing to say.
class VoiceModelQuiet extends VoiceModel {
  const VoiceModelQuiet();
}

class VoiceModelDownloading extends VoiceModel {
  const VoiceModelDownloading({required this.received, required this.total});
  final int received;
  final int total;
}

class VoiceModelFailed extends VoiceModel {
  const VoiceModelFailed([this.message = '']);
  final String message;
}

/// `.notice`: one quiet line above the notes.
class _Line extends StatelessWidget {
  const _Line({super.key, required this.children});

  final List<InlineSpan> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        // `margin: 0 0 var(--glacier-space-4)`
        padding: EdgeInsets.only(bottom: t.space(4)),
        child: CssLines(
          lineHeight: t.len('glacier-leading-sm') * sm,
          // `font-size: sm; line-height: leading-sm; color: var(--glacier-text-muted)`
          child: Text.rich(TextSpan(children: children), style: pageText(t, sm, color: t.color('glacier-text-muted'), height: t.len('glacier-leading-sm'))),
        ),
      ),
    );
  }
}

/// One line on the home page while voice notes cannot work yet, and nothing at all once they can
/// (`VoiceModelStatus`). Fed [VoiceModel] where the page read the recorder's hook.
class VoiceModelStatus extends StatelessWidget {
  const VoiceModelStatus({super.key, required this.state, required this.onRetry});

  final VoiceModel state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = this.state;
    switch (state) {
      case VoiceModelQuiet():
        return const SizedBox.shrink();
      case VoiceModelDownloading(:final received, :final total):
        return _Line(key: const ValueKey('voice-model-notice'), children: [TextSpan(text: 'Downloading the voice model, ${megabytes(received)} of ${megabytes(total)} MB. Keep Ghost.md open.')]);
      case VoiceModelFailed():
        final sm = t.fontSize('sm');
        return _Line(
          key: const ValueKey('voice-model-notice'),
          children: [
            const TextSpan(text: 'The voice model didn’t download. '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GlacierPressable(
                onPressed: onRetry,
                // `.app-word` with `.noticeAction { min-block-size: 0; padding: 0; font-size: inherit;
                //   color: var(--glacier-accent-text) }`; pressed, `--glacier-text`.
                builder: (context, state) => Text('Try again', style: pageText(t, sm, weight: 'medium', color: state.pressed ? t.color('glacier-text') : t.color('glacier-accent-text'), height: t.len('glacier-leading-sm'))),
              ),
            ),
          ],
        );
    }
  }
}

/// The better voice model coming down in the background, while it does (`RefiningNotice`); nothing with no download.
/// Fed the download's two numbers where the page read `capture/refine.ts`.
class RefiningNotice extends StatelessWidget {
  const RefiningNotice({super.key, this.received, this.total});

  final int? received;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final received = this.received, total = this.total;
    if (received == null || total == null) return const SizedBox.shrink();
    return _Line(key: const ValueKey('refining-notice'), children: [TextSpan(text: 'Getting the better voice model, ${megabytes(received)} of ${megabytes(total)} MB.')]);
  }
}

// ---- a job of the app's own ---------------------------------------------------------------------------------------

/// A job the app is doing by itself, while it does, as one quiet line above the notes and in the sidebar, with the
/// one word that stops it (Matt, 2026-10-26: "Make the header generation async and a background task that runs while
/// the app is generating the images"): "Making header images · 12 of 100   Stop" (lib/plugins/lovart/banner_run.dart).
/// And, where it stopped for a reason the person has to act on, that reason, with Hide. The same in simple and
/// advanced: a line, never a card. Fed its words and its word's press by whoever has the job.
class JobNotice extends StatelessWidget {
  const JobNotice({super.key, required this.words, this.action, this.onAction});

  final String words;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final action = this.action, onAction = this.onAction;
    return _Line(
      key: const ValueKey('job-notice'),
      children: [
        TextSpan(text: words),
        if (action != null && onAction != null) ...[
          const TextSpan(text: '   '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GlacierPressable(
              key: const ValueKey('job-notice-action'),
              onPressed: onAction,
              // The voice model's Try again, as a word in the line.
              builder: (context, state) => Text(action, style: pageText(t, sm, weight: 'medium', color: state.pressed ? t.color('glacier-text') : t.color('glacier-accent-text'), height: t.len('glacier-leading-sm'))),
            ),
          ),
        ],
      ],
    );
  }
}

// ---- layout -------------------------------------------------------------------------------------------------------

/// Two children on a wrapping line: the first `flex: 1 1 <basis>`, the second `flex: none` and kept to the end
/// (`margin-inline-start: auto`). Side by side, centred on each other, while the first has its basis; otherwise the
/// second takes a line of its own under the first, at its end.
class _WordsAndDo extends MultiChildRenderObjectWidget {
  const _WordsAndDo({required this.columnGap, required this.rowGap, required this.basis, super.children});

  final double columnGap;
  final double rowGap;
  final double basis;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderWordsAndDo(columnGap, rowGap, basis);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderWordsAndDo)
      ..columnGap = columnGap
      ..rowGap = rowGap
      ..basis = basis;
  }
}

class _PairData extends ContainerBoxParentData<RenderBox> {}

class _RenderWordsAndDo extends RenderBox with ContainerRenderObjectMixin<RenderBox, _PairData>, RenderBoxContainerDefaultsMixin<RenderBox, _PairData> {
  _RenderWordsAndDo(this._columnGap, this._rowGap, this._basis);

  double _columnGap;
  set columnGap(double value) {
    if (value == _columnGap) return;
    _columnGap = value;
    markNeedsLayout();
  }

  double _rowGap;
  set rowGap(double value) {
    if (value == _rowGap) return;
    _rowGap = value;
    markNeedsLayout();
  }

  double _basis;
  set basis(double value) {
    if (value == _basis) return;
    _basis = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PairData) child.parentData = _PairData();
  }

  bool _beside(double width, double doing) => _basis + _columnGap + doing <= width + 0.01;

  @override
  double computeMinIntrinsicWidth(double height) => math.max(_basis, lastChild?.getMaxIntrinsicWidth(double.infinity) ?? 0);

  @override
  double computeMaxIntrinsicWidth(double height) => (firstChild?.getMaxIntrinsicWidth(double.infinity) ?? 0) + _columnGap + (lastChild?.getMaxIntrinsicWidth(double.infinity) ?? 0);

  @override
  double computeMinIntrinsicHeight(double width) => _heightAt(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _heightAt(width);

  double _heightAt(double width) {
    final words = firstChild, doing = lastChild;
    if (words == null || doing == null) return 0;
    final doWidth = doing.getMaxIntrinsicWidth(double.infinity);
    final doHeight = doing.getMaxIntrinsicHeight(doWidth);
    if (_beside(width, doWidth)) return math.max(words.getMaxIntrinsicHeight(width - _columnGap - doWidth), doHeight);
    return words.getMaxIntrinsicHeight(width) + _rowGap + doHeight;
  }

  @override
  void performLayout() {
    final words = firstChild!, doing = lastChild!;
    final width = constraints.maxWidth;
    doing.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    if (_beside(width, doing.size.width)) {
      words.layout(BoxConstraints.tightFor(width: width - _columnGap - doing.size.width), parentUsesSize: true);
      final tall = math.max(words.size.height, doing.size.height);
      (words.parentData! as _PairData).offset = Offset(0, (tall - words.size.height) / 2);
      (doing.parentData! as _PairData).offset = Offset(width - doing.size.width, (tall - doing.size.height) / 2);
      size = constraints.constrain(Size(width, tall));
    } else {
      words.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      (words.parentData! as _PairData).offset = Offset.zero;
      (doing.parentData! as _PairData).offset = Offset(width - doing.size.width, words.size.height + _rowGap);
      size = constraints.constrain(Size(width, words.size.height + _rowGap + doing.size.height));
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}
