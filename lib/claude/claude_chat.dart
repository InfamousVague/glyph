/// Talking to Claude: a chat (docs/CLAUDE_APP.md, "The chat"). Matt: "Make the ask Claude and other agents open a
/// chat when we go to talk to them".
///
/// Opened from Claude on the home page's dock, the command bar's Ask Claude, the bar over a note Claude writes in,
/// and an AI's row on an organization's page (Chat). Over the whole window on a phone, a panel down the right on a
/// wide one; the back gesture closes it.
///
/// Top to bottom: a head (Claude's mark, who this is with and what it is doing, New chat, close); the agent the chat
/// was opened for, when it is online through the connector, with what it is doing, Follow and Open (the top bar's
/// chip's menu, moved here with the chip); the conversation, the person's words on the right and Claude's on the
/// left arriving as Claude writes them, what each tool did as a quiet line that opens its note; and the field to
/// write in, kept over the keyboard.
///
/// Who answers: the app's own Claude, with the person's key (lib/claude/claude_runner.dart). An agent working
/// through the connector cannot be reached from the app while it works (it is a tool call away, in Claude's own app);
/// without a key, what is written here goes to the "Ask Claude" note ([ClaudeChat.onInbox]), the list the
/// connector's agents and the Mac's routine work through.
///
/// When Claude starts writing in a note, the root puts the chat away and opens the note (lib/root/root_claude.dart),
/// and the bar over it carries on from here.
library;

import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart' show AppIcon, Lucide;
import '../core/back.dart';
import '../live/follow.dart';
import '../live/presence.dart' show AiOnline;
import '../sheet/css.dart';
import '../sheet/kit.dart' show SheetField;
import 'claude_mark.dart';
import 'claude_run.dart';
import 'claude_runner.dart';
import 'claude_settings.dart';

class ClaudeChat extends StatefulWidget {
  const ClaudeChat({
    super.key,
    required this.runner,
    this.follow,
    this.agent,
    required this.onClose,
    required this.onOpenNote,
    required this.onSettings,
    this.onOpenAi,
    this.onInbox,
    this.initial,
  });

  final ClaudeRunner runner;

  /// The connector's AIs online, where the build has an account.
  final FollowAi? follow;

  /// The agent the chat was opened to talk to, by name (an organization's AI row), or null for Claude in the app.
  final String? agent;
  final VoidCallback onClose;
  final void Function(String noteId) onOpenNote;

  /// Settings › Ask Claude, where the key is added.
  final VoidCallback onSettings;

  /// The chip's Open: the note an AI is on, at its caret.
  final void Function(AiOnline ai)? onOpenAi;

  /// Without a key: a request written into the "Ask Claude" note, for the connector's agents.
  final Future<void> Function(String request)? onInbox;

  /// Words the field starts with.
  final String? initial;

  @override
  State<ClaudeChat> createState() => _ClaudeChatState();
}

class _ClaudeChatState extends State<ClaudeChat> {
  late final TextEditingController _field = TextEditingController(text: widget.initial ?? '');
  final FocusNode _focus = FocusNode(debugLabel: 'Claude chat');
  String? _problem;

  /// Requests sent to the inbox from this chat, shown as said.
  final List<String> _sent = [];
  VoidCallback? _stopBack;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Once: built again for the keyboard or a turn, it would otherwise go back on top of what opened after it.
    if (_stopBack != null) return;
    _stopBack = BackScope.of(context).onBack(() {
      widget.onClose();
      return true;
    });
  }

  @override
  void dispose() {
    _stopBack?.call();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final words = _field.text.trim();
    if (words.isEmpty) return;
    setState(() => _problem = null);
    _field.clear();
    final runner = widget.runner;
    if (!runner.settings.hasKey) {
      final inbox = widget.onInbox;
      if (inbox == null) return;
      try {
        await inbox(words);
        if (mounted) setState(() => _sent.add(words));
      } catch (error) {
        if (mounted) setState(() => _problem = '$error');
      }
      return;
    }
    try {
      await runner.ask(words);
    } catch (error) {
      if (mounted) setState(() => _problem = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final listen = Listenable.merge([widget.runner, if (widget.follow != null) widget.follow!]);
    final panel = Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      label: 'Chat with ${widget.agent ?? 'Claude'}',
      child: Container(
        key: const ValueKey('claude-chat'),
        decoration: BoxDecoration(
          color: t.color('app-paper'),
          border: wide ? Border(left: BorderSide(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline'))) : null,
          boxShadow: wide ? [BoxShadow(color: claudeSlate.withValues(alpha: 0.18), blurRadius: 24)] : null,
        ),
        child: SafeArea(
          left: !wide,
          child: Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: ListenableBuilder(
              listenable: listen,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Head(state: this),
                  Expanded(child: _Messages(state: this)),
                  _Composer(state: this),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!wide) return panel;
    return Align(alignment: Alignment.centerRight, child: SizedBox(width: 420, height: double.infinity, child: panel));
  }
}

/// A round button of the head and the composer.
class _Round extends StatelessWidget {
  const _Round({super.key, required this.label, required this.onPressed, required this.child, this.filled = false});

  final String label;
  final VoidCallback? onPressed;
  final Widget child;
  final bool filled;

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
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? (onPressed == null ? claudeOrange.withValues(alpha: 0.4) : claudeOrange)
                : (state.hovered || state.pressed ? t.colorOf('color-mix(in oklch, var(--app-ink) 8%, transparent)') : null),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.state});

  final _ClaudeChatState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chat = state.widget;
    final runner = chat.runner;
    final run = runner.run;
    final at = run?.at;
    final line = run != null && run.working
        ? (at == null ? 'Thinking…' : '${at.doing[0].toUpperCase()}${at.doing.substring(1)} ${at.title.isEmpty ? 'a note' : at.title}')
        : runner.settings.hasKey
            ? claudeModelLabel(runner.settings.model)
            : 'No API key on this device';
    final ink = t.color('app-ink');
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')))),
      child: Row(
        children: [
          _Round(key: const ValueKey('claude-chat-close'), label: 'Close the chat', onPressed: chat.onClose, child: AppIcon(Lucide.chevronLeft, size: 20, color: ink)),
          SizedBox(width: t.space(2)),
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: claudeOrange),
            child: const ClaudeMark(size: 16, color: claudeIvory),
          ),
          SizedBox(width: t.space(2)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(chat.agent ?? 'Claude', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: ink)),
                Text(line, key: const ValueKey('claude-chat-line'), maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('glacier-text-subtle'))),
              ],
            ),
          ),
          if (runner.conversation.isNotEmpty && !runner.working)
            _Round(key: const ValueKey('claude-new'), label: 'New chat', onPressed: runner.newChat, child: AppIcon(Lucide.messageSquarePlus, size: 19, color: ink)),
        ],
      ),
    );
  }
}

/// The conversation, newest at the foot, kept there as words arrive.
class _Messages extends StatelessWidget {
  const _Messages({required this.state});

  final _ClaudeChatState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chat = state.widget;
    final runner = chat.runner;
    final settings = runner.settings;
    final ais = chat.follow?.ais ?? const <AiOnline>[];
    // The agent this chat is with, online now; else every AI online, as the chip's menu listed them.
    final agentName = chat.agent?.toLowerCase();
    final shown = agentName == null ? ais : ais.where((ai) => ai.name.toLowerCase() == agentName).toList();
    final items = <Widget>[
      if (!settings.hasKey)
        _Card(
          key: const ValueKey('claude-no-key'),
          children: [
            Text(
              chat.onInbox == null
                  ? 'Claude works here with your own Anthropic API key, kept on this device.'
                  : 'Claude answers here, as you watch, with your own Anthropic API key, kept on this device. Without one, what you write goes to your “Ask Claude” note, for Claude to work through from its own app.',
              style: pageText(t, t.fontSize('sm'), color: t.color('app-ink')),
            ),
            SizedBox(height: t.space(2)),
            _Pill(key: const ValueKey('claude-add-key'), words: 'Add an API key', onPressed: chat.onSettings),
          ],
        ),
      for (final ai in shown) _AgentCard(ai: ai, chat: chat),
      if (runner.conversation.isEmpty && state._sent.isEmpty && settings.hasKey)
        Padding(
          padding: EdgeInsets.symmetric(vertical: t.space(6)),
          child: Column(
            children: [
              const ClaudeMark(size: 34),
              SizedBox(height: t.space(3)),
              Text(
                'Ask Claude to write a note, find something, or change a note. The note it writes in opens, and you watch it type.',
                textAlign: TextAlign.center,
                style: pageText(t, t.fontSize('sm'), color: t.color('glacier-text-subtle')),
              ),
            ],
          ),
        ),
      for (final run in runner.conversation) ..._runItems(context, run, chat.onOpenNote),
      for (final sent in state._sent) ...[
        _Bubble(words: sent, mine: true),
        const _Quiet('Added to your “Ask Claude” note.'),
      ],
      if (state._problem != null) _Quiet(state._problem!),
    ];
    return ListView(
      key: const ValueKey('claude-chat-messages'),
      reverse: true,
      padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.space(3)),
      children: items.reversed.toList(),
    );
  }

  static List<Widget> _runItems(BuildContext context, ClaudeRun run, void Function(String) onOpenNote) => [
        for (final step in run.steps)
          switch (step.kind) {
            'asked' => _Bubble(words: step.words, mine: true),
            'said' => _Bubble(words: step.words),
            _ => _Step(step: step, onOpenNote: onOpenNote),
          },
        if (run.saying.trim().isNotEmpty) _Bubble(words: run.saying.trim(), live: true),
        if (run.working && run.saying.isEmpty) _Quiet(run.state == ClaudeState.writing ? 'Writing…' : 'Thinking…'),
        if (run.state == ClaudeState.stopped) const _Quiet('Stopped.'),
        if (run.state == ClaudeState.failed) _Quiet(run.problem ?? 'Something went wrong.'),
      ];
}

/// An agent online through the connector: what it is doing, Follow, Open.
class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.ai, required this.chat});

  final AiOnline ai;
  final ClaudeChat chat;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final follow = chat.follow!;
    final at = ai.at;
    return _Card(
      key: ValueKey('claude-online:${ai.key}'),
      children: [
        Text('${ai.name} is ${ai.words}', style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-ink'))),
        SizedBox(height: t.space(1)),
        Text(
          '${ai.name} is working from Claude’s own app, through Ghost.md’s connector, and cannot read this chat while it works.',
          style: pageText(t, t.fontSize('xs'), color: t.color('glacier-text-subtle')),
        ),
        SizedBox(height: t.space(2)),
        Wrap(
          spacing: t.space(2),
          runSpacing: t.space(2),
          children: [
            if (follow.following?.key == ai.key)
              _Pill(key: ValueKey('ai-menu-stop:${ai.key}'), words: 'Stop following ${ai.name}', onPressed: follow.stop)
            else
              _Pill(
                key: ValueKey('ai-menu-follow:${ai.key}'),
                words: 'Follow ${ai.name}',
                onPressed: () {
                  follow.follow(ai);
                  chat.onClose();
                },
              ),
            if (at != null && chat.onOpenAi != null)
              _Pill(
                key: ValueKey('ai-menu-open:${ai.key}'),
                words: 'Open ${at.title.isEmpty ? (at.kind == 'canvas' ? 'the canvas' : 'the note') : at.title}',
                onPressed: () {
                  chat.onOpenAi!(ai);
                  chat.onClose();
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      margin: EdgeInsets.symmetric(vertical: t.space(2)),
      padding: EdgeInsets.all(t.space(3)),
      decoration: BoxDecoration(
        color: claudeOrange.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(t.radius('lg')),
        border: Border.all(color: claudeOrange.withValues(alpha: 0.25), width: t.len('glacier-hairline')),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
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

/// A message: the person's on the right in Claude's wash, Claude's on the left on the paper.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.words, this.mine = false, this.live = false});

  final String words;
  final bool mine;

  /// Still arriving.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final width = MediaQuery.sizeOf(context).width;
    final text = Text(words, style: pageText(t, t.fontSize('sm'), color: t.color('app-ink')));
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: (width < 420 ? width : 420) * 0.82),
        child: Container(
          margin: EdgeInsets.symmetric(vertical: t.space(1)),
          padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
          decoration: BoxDecoration(
            color: mine ? claudeOrange.withValues(alpha: 0.14) : t.colorOf('color-mix(in oklch, var(--app-ink) 5%, transparent)'),
            borderRadius: BorderRadius.circular(t.radius('lg')),
          ),
          child: Semantics(liveRegion: live, child: text),
        ),
      ),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.words);

  final String words;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.space(1)),
      child: Text(words, style: pageText(t, t.fontSize('xs'), color: t.color('glacier-text-subtle'))),
    );
  }
}

/// What a tool did: a quiet line, a press opening its note.
class _Step extends StatelessWidget {
  const _Step({required this.step, required this.onOpenNote});

  final ClaudeStep step;
  final void Function(String noteId) onOpenNote;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final noteId = step.noteId;
    final line = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Container(width: 5, height: 5, margin: EdgeInsets.only(right: t.space(2)), decoration: const BoxDecoration(shape: BoxShape.circle, color: claudeOrange)),
        Flexible(
          child: Text(
            step.words,
            style: pageText(t, t.fontSize('xs'), weight: 'medium', color: noteId == null ? t.color('glacier-text-subtle') : claudeOrange),
          ),
        ),
      ]),
    );
    if (noteId == null) return line;
    return GlacierPressable(onPressed: () => onOpenNote(noteId), semanticLabel: '${step.words}. Open it.', builder: (context, state) => line);
  }
}

/// The field to write in, with Send (or Stop while Claude works).
class _Composer extends StatelessWidget {
  const _Composer({required this.state});

  final _ClaudeChatState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chat = state.widget;
    final runner = chat.runner;
    final run = runner.run;
    final hasKey = runner.settings.hasKey;
    if (!hasKey && chat.onInbox == null) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(3)),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (run != null && run.working && run.at != null)
            Padding(
              padding: EdgeInsets.only(bottom: t.space(2)),
              child: Wrap(spacing: t.space(2), children: [
                _Pill(
                  key: const ValueKey('claude-watch'),
                  words: run.following ? 'Watch Claude in ${run.at!.title.isEmpty ? 'the note' : run.at!.title}' : 'Watch again',
                  // The note opened (the chat makes way), Claude's caret shown where it last typed, scrolled to.
                  onPressed: run.follow,
                ),
              ]),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: t.space(3)),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(t.radius('lg')),
                    border: Border.all(color: t.color('glacier-border-strong'), width: t.len('glacier-hairline')),
                  ),
                  child: SheetField(
                    key: const ValueKey('claude-ask'),
                    label: hasKey ? 'Message Claude' : 'A request for your Ask Claude note',
                    controller: state._field,
                    focusNode: state._focus,
                    placeholder: !hasKey
                        ? 'A request for the Ask Claude note…'
                        : runner.conversation.isEmpty
                            ? 'Message Claude'
                            : 'Reply to Claude',
                    autoFocus: runner.conversation.isEmpty,
                    enterKeyHint: TextInputAction.send,
                    onSubmitted: (_) => state._send(),
                  ),
                ),
              ),
              SizedBox(width: t.space(2)),
              if (runner.working)
                _Round(key: const ValueKey('claude-stop'), label: 'Stop Claude', onPressed: runner.stop, filled: true, child: const AppIcon(Lucide.square, size: 15, color: claudeIvory))
              else
                _Round(key: const ValueKey('claude-send'), label: 'Send', onPressed: state._send, filled: true, child: const AppIcon(Lucide.arrowUp, size: 18, color: claudeIvory)),
            ],
          ),
        ],
      ),
    );
  }
}
