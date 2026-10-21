/// The sheet an ask said aloud is shown in (lib/claude/claude_voice.dart, which says what each stage is). Over the
/// whole window, under the bars and over everything else, as the chat is.
///
/// - **Listening**: a card at the foot, Claude's orange mic in its middle with the recorder's own rings going out
///   from it, sent by the voice (capture/ui/voice_waves.dart [VoiceWaves], in Claude's orange here), and the words
///   heard under it as they come. A tap anywhere, or on the mic, is "done"; the close is "never mind".
/// - **Thinking**: the same card, the words asked at its head, Claude's thinking under them as it comes, the end of
///   it in view, and a line for each thing a tool did.
/// - **Following**: the card makes way, down to a strip at the head of the window, so the note Claude opened is
///   watched as it types: what Claude is doing, Stop, the chat, close. Nothing else of the window is covered.
/// - **Answered**, **Sent**, **Failed**: Claude's last words, or where the words went, or why not, with the chat and
///   Done. A strip stays a strip, and goes by itself a few seconds after (unless pressed).
///
/// The back gesture closes it, as the close does. With reduced motion the rings stand still, as the recorder's do.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart' show AppIcon, Lucide;
import '../capture/ui/voice_waves.dart';
import '../core/back.dart' show OnBack;
import '../home/home_icons.dart';
import '../sheet/css.dart';
import 'claude_mark.dart';
import 'claude_run.dart';
import 'claude_voice.dart';

class ClaudeVoiceSheet extends StatefulWidget {
  const ClaudeVoiceSheet({super.key, required this.voice, required this.onChat, this.onSettings, this.onOpenNote});

  final ClaudeVoice voice;

  /// The chat with Claude, where the conversation goes on (the sheet closes first).
  final VoidCallback onChat;

  /// The Claude plugin's page, where a key is added.
  final VoidCallback? onSettings;

  /// A note a tool touched, opened.
  final void Function(String noteId)? onOpenNote;

  @override
  State<ClaudeVoiceSheet> createState() => _ClaudeVoiceSheetState();
}

class _ClaudeVoiceSheetState extends State<ClaudeVoiceSheet> {
  final GlobalKey _mic = GlobalKey(debugLabel: 'Claude voice mic');

  ClaudeVoice get _voice => widget.voice;

  @override
  Widget build(BuildContext context) {
    return OnBack(
      onBack: _voice.cancel,
      child: ListenableBuilder(
        listenable: _voice,
        // Found by `claude-voice` either way; each its own below it, so neither is made from the other.
        builder: (context, _) => KeyedSubtree(key: const ValueKey('claude-voice'), child: _voice.madeWay ? _strip(context) : _sheet(context)),
      ),
    );
  }

  // ---- the card -----------------------------------------------------------------------------------------------------

  Widget _sheet(BuildContext context) {
    final t = context.tokens;
    final voice = _voice;
    final listening = voice.stage == ClaudeVoiceStage.listening;
    final width = MediaQuery.sizeOf(context).width;
    final card = Container(
      key: ValueKey('claude-voice-${voice.stage.name}'),
      constraints: BoxConstraints(maxWidth: width < 560 ? width : 520),
      margin: EdgeInsets.fromLTRB(t.space(3), 0, t.space(3), t.space(3)),
      padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(4), t.space(4)),
      decoration: BoxDecoration(
        color: t.color('app-paper'),
        borderRadius: BorderRadius.circular(t.radius('xl')),
        border: Border.all(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')),
        boxShadow: [BoxShadow(color: claudeSlate.withValues(alpha: 0.18), blurRadius: 28, offset: const Offset(0, 6))],
      ),
      child: GestureDetector(
        // A tap on the card is its own, not the scrim's.
        onTap: listening ? () => voice.done() : () {},
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _head(context),
            SizedBox(height: t.space(3)),
            ..._body(context),
          ],
        ),
      ),
    );
    return Semantics(
      key: const ValueKey('claude-voice-sheet'),
      scopesRoute: true,
      explicitChildNodes: true,
      label: 'Talk to Claude',
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The scrim: a tap while listening is "done", after it the sheet goes.
          GestureDetector(
            key: const ValueKey('claude-voice-scrim'),
            behavior: HitTestBehavior.opaque,
            onTap: listening ? () => voice.done() : voice.cancel,
            child: ColoredBox(color: claudeSlate.withValues(alpha: 0.28)),
          ),
          if (listening) Positioned.fill(child: VoiceWaves(anchor: _mic, color: claudeOrange)),
          SafeArea(top: false, child: Align(alignment: Alignment.bottomCenter, child: card)),
        ],
      ),
    );
  }

  Widget _head(BuildContext context) {
    final t = context.tokens;
    final voice = _voice;
    final title = switch (voice.stage) {
      ClaudeVoiceStage.listening => 'Listening',
      ClaudeVoiceStage.sending => voice.fromWatch ? 'From your watch' : 'Listening',
      ClaudeVoiceStage.thinking || ClaudeVoiceStage.following => voice.run?.state == ClaudeState.writing ? 'Claude is writing' : 'Claude is thinking',
      ClaudeVoiceStage.answered => 'Claude',
      ClaudeVoiceStage.sent => 'Sent',
      ClaudeVoiceStage.failed => 'Claude',
    };
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(shape: BoxShape.circle, color: claudeOrange),
          child: const ClaudeMark(size: 14, color: claudeIvory),
        ),
        SizedBox(width: t.space(2)),
        Expanded(child: Text(title, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink')))),
        _Round(key: const ValueKey('claude-voice-close'), label: voice.stage == ClaudeVoiceStage.listening ? 'Never mind' : 'Close', onPressed: voice.cancel, child: AppIcon(Lucide.x, size: 18, color: t.color('app-ink'))),
      ],
    );
  }

  List<Widget> _body(BuildContext context) {
    final t = context.tokens;
    final voice = _voice;
    final quiet = t.color('glacier-text-subtle');
    final ink = t.color('app-ink');
    switch (voice.stage) {
      case ClaudeVoiceStage.listening:
      case ClaudeVoiceStage.sending:
        final download = voice.download;
        final words = voice.words.trim();
        return [
          Center(
            child: GlacierPressable(
              key: const ValueKey('claude-voice-mic'),
              onPressed: voice.stage == ClaudeVoiceStage.listening ? () => voice.done() : null,
              semanticLabel: 'Done talking',
              builder: (context, state) => AnimatedScale(
                scale: state.pressed ? 0.94 : 1,
                duration: t.duration('glacier-duration-fast'),
                child: Container(
                  key: _mic,
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: claudeOrange),
                  child: const HomeIcon(HomeGlyph.mic, size: 28, strokeWidth: 2.2, color: claudeIvory),
                ),
              ),
            ),
          ),
          SizedBox(height: t.space(3)),
          Semantics(
            liveRegion: true,
            child: Text(
              words.isEmpty ? 'Say what you would like Claude to do.' : words,
              key: const ValueKey('claude-voice-words'),
              textAlign: TextAlign.center,
              style: pageText(t, t.fontSize(words.isEmpty ? 'sm' : 'md'), color: words.isEmpty ? quiet : ink),
            ),
          ),
          SizedBox(height: t.space(2)),
          Text(
            download != null && download.total > 0
                ? 'Getting the voice model, ${(100 * download.received / download.total).round()}%. Keep talking: you are heard meanwhile.'
                : voice.stage == ClaudeVoiceStage.sending
                    ? (voice.fromWatch ? 'Said on your watch. Sending to Claude…' : 'Sending…')
                    : 'Tap when you are done. It stops by itself when you pause.',
            textAlign: TextAlign.center,
            style: pageText(t, t.fontSize('xs'), color: quiet),
          ),
        ];
      case ClaudeVoiceStage.thinking:
      case ClaudeVoiceStage.following:
        final run = voice.run;
        final thought = voice.thought;
        final steps = [for (final step in run?.steps ?? const <ClaudeStep>[]) if (step.kind == 'tool') step];
        final saying = run?.saying.trim() ?? '';
        return [
          Text(voice.words, maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: ink)),
          SizedBox(height: t.space(2)),
          Container(
            key: const ValueKey('claude-voice-thought'),
            padding: EdgeInsets.only(left: t.space(2)),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: claudeOrange.withValues(alpha: 0.5), width: 2))),
            child: Semantics(
              liveRegion: true,
              child: Text(thought.isEmpty ? 'Thinking…' : thought, maxLines: 6, overflow: TextOverflow.fade, style: pageText(t, t.fontSize('xs'), color: quiet)),
            ),
          ),
          for (final step in steps.length > 3 ? steps.sublist(steps.length - 3) : steps) _StepLine(step: step, onOpenNote: widget.onOpenNote),
          if (saying.isNotEmpty) ...[
            SizedBox(height: t.space(2)),
            Text(saying, maxLines: 3, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), color: ink)),
          ],
          SizedBox(height: t.space(3)),
          Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [
            _Pill(key: const ValueKey('claude-voice-stop'), words: 'Stop', onPressed: voice.stop),
            _Pill(key: const ValueKey('claude-voice-chat'), words: 'Open the chat', onPressed: widget.onChat),
          ]),
        ];
      case ClaudeVoiceStage.answered:
        final answer = voice.run?.answer.trim() ?? '';
        return [
          Text(voice.words, maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: quiet)),
          SizedBox(height: t.space(2)),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.35),
            child: SingleChildScrollView(
              child: Text(answer.isEmpty ? (voice.run?.state == ClaudeState.stopped ? 'Stopped.' : 'Done.') : answer, key: const ValueKey('claude-voice-answer'), style: pageText(t, t.fontSize('sm'), color: ink)),
            ),
          ),
          SizedBox(height: t.space(3)),
          Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [
            _Pill(key: const ValueKey('claude-voice-chat'), words: 'Continue in the chat', onPressed: widget.onChat),
            _Pill(key: const ValueKey('claude-voice-done'), words: 'Done', onPressed: voice.cancel),
          ]),
        ];
      case ClaudeVoiceStage.sent:
        return [
          Text(voice.words, maxLines: 2, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: ink)),
          SizedBox(height: t.space(2)),
          Text('Added to your “Ask Claude” note, for Claude to work through from its own app.', style: pageText(t, t.fontSize('sm'), color: quiet)),
          SizedBox(height: t.space(3)),
          Wrap(children: [_Pill(key: const ValueKey('claude-voice-done'), words: 'Done', onPressed: voice.cancel)]),
        ];
      case ClaudeVoiceStage.failed:
        return [
          Text(voice.problem ?? 'Something went wrong.', key: const ValueKey('claude-voice-problem'), style: pageText(t, t.fontSize('sm'), color: ink)),
          SizedBox(height: t.space(3)),
          Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [
            if (voice.wantsKey && widget.onSettings != null) _Pill(key: const ValueKey('claude-voice-key'), words: 'Add an API key', onPressed: widget.onSettings!),
            _Pill(key: const ValueKey('claude-voice-done'), words: 'Done', onPressed: voice.cancel),
          ]),
        ];
    }
  }

  // ---- the strip ----------------------------------------------------------------------------------------------------

  /// The sheet made way: a strip at the head of the window, under the bars, the rest of the window left alone.
  Widget _strip(BuildContext context) {
    final t = context.tokens;
    final voice = _voice;
    final working = !voice.over;
    final width = MediaQuery.sizeOf(context).width;
    final strip = Container(
      key: const ValueKey('claude-voice-following'),
      constraints: BoxConstraints(maxWidth: width < 560 ? width : 520),
      margin: EdgeInsets.symmetric(horizontal: t.space(3)),
      padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(1), t.space(2)),
      decoration: BoxDecoration(
        color: t.color('app-paper'),
        borderRadius: BorderRadius.circular(t.radius('full')),
        border: Border.all(color: claudeOrange.withValues(alpha: 0.45), width: t.len('glacier-hairline')),
        boxShadow: [BoxShadow(color: claudeSlate.withValues(alpha: 0.16), blurRadius: 18, offset: const Offset(0, 4))],
      ),
      child: Listener(
        // A press anywhere on it keeps it, rather than letting it go by itself.
        onPointerDown: (_) => voice.stay(),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: claudeOrange),
              child: const ClaudeMark(size: 13, color: claudeIvory),
            ),
            SizedBox(width: t.space(2)),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(voice.line, key: const ValueKey('claude-voice-line'), maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-ink'))),
              ),
            ),
            if (working) _Round(key: const ValueKey('claude-voice-stop'), label: voice.run != null ? 'Stop Claude' : 'Stop following', onPressed: voice.stop, child: const AppIcon(Lucide.square, size: 12, color: claudeOrange)),
            if (voice.run != null) _Round(key: const ValueKey('claude-voice-chat'), label: 'Open the chat', onPressed: widget.onChat, child: AppIcon(Lucide.messageSquare, size: 16, color: t.color('app-ink'))),
            _Round(key: const ValueKey('claude-voice-close'), label: 'Close', onPressed: voice.cancel, child: AppIcon(Lucide.x, size: 16, color: t.color('app-ink'))),
          ],
        ),
      ),
    );
    return Semantics(
      key: const ValueKey('claude-voice-strip'),
      container: true,
      explicitChildNodes: true,
      label: 'Talk to Claude',
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.only(top: t.len('app-bar-ring') + t.space(4)),
          child: Align(alignment: Alignment.topCenter, child: strip),
        ),
      ),
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine({required this.step, this.onOpenNote});

  final ClaudeStep step;
  final void Function(String noteId)? onOpenNote;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final noteId = step.noteId;
    final line = Padding(
      padding: EdgeInsets.only(top: t.space(1)),
      child: Row(children: [
        Container(width: 5, height: 5, margin: EdgeInsets.only(right: t.space(2)), decoration: const BoxDecoration(shape: BoxShape.circle, color: claudeOrange)),
        Flexible(child: Text(step.words, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: 'medium', color: noteId == null ? t.color('glacier-text-subtle') : claudeOrange))),
      ]),
    );
    final open = onOpenNote;
    if (noteId == null || open == null) return line;
    return GlacierPressable(onPressed: () => open(noteId), semanticLabel: '${step.words}. Open it.', builder: (context, state) => line);
  }
}

class _Round extends StatelessWidget {
  const _Round({super.key, required this.label, required this.onPressed, required this.child});

  final String label;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = t.len('app-bar-ring');
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('full'),
        child: Container(
          width: side,
          height: side,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: state.hovered || state.pressed ? t.colorOf('color-mix(in oklch, var(--app-ink) 8%, transparent)') : null),
          child: child,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.words, required this.onPressed});

  final String words;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: words,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('full'),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 0.3 * sm, horizontal: 0.9 * sm),
          decoration: ShapeDecoration(
            color: state.hovered || state.pressed ? claudeOrange.withValues(alpha: 0.14) : null,
            shape: StadiumBorder(side: BorderSide(color: claudeOrange, width: t.len('glacier-hairline'))),
          ),
          child: ExcludeSemantics(child: Text(words, style: pageText(t, sm, weight: 'medium', color: claudeOrange))),
        ),
      ),
    );
  }
}
