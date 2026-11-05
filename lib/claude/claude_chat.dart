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
///
/// Opened from a page's dock (lib/shell/page_dock.dart), the page says what it is about: a note's `[[Title]]` is put
/// in the field ready to ask about ([ClaudeChat.initial]); the chat holds no subject of its own. Down the right of a
/// wide window it says how much of the window's end it covers ([windowEndCover]), so the page's dock stands clear of
/// it.
///
/// **Pictures** (lib/claude/chat_images.dart; Matt, 2026-11-05: "Add the ability to upload images to Claude in app"):
/// the round + picture button before the field opens the device's chooser ([ClaudeChat.pictures]); on a Mac a picture
/// pasted into the field or dropped on the window is attached too. Up to [chatImageLimit] wait above the field as
/// thumbnails, each with its ×, with chips to send ("Make a note of this", "Add these appointments", …) while nothing
/// is written; "Keep pictures in notes", off unless switched on, lets the AI put the picture itself into a note. Where
/// the model asked cannot see pictures the button is drawn faded and, pressed, says so and where to pick one that can.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/services.dart' show Clipboard, ClipboardData, HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey, TextInputAction, TextSelection, Uint8List;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart' show AppIcon, Lucide;
import '../core/back.dart';
import '../ai/support/failure.dart' show failureText;
import '../live/follow.dart';
import '../live/presence.dart' show AiOnline;
import '../sheet/css.dart';
import '../shell/page_dock.dart' show windowEndCover;
import 'chat_images.dart';
import 'claude_mark.dart';
import 'claude_run.dart';
import 'claude_runner.dart';
import 'claude_settings.dart';

/// The chat's width as a panel down the right of a wide window.
const double claudeChatPanelWidth = 420;

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
    this.onShareLink,
    this.initial,
    this.pictures,
  });

  final ClaudeRunner runner;

  /// The connector's AIs online, where the build has an account.
  final FollowAi? follow;

  /// The agent the chat was opened to talk to, by name (an organization's AI row), or null for Claude in the app.
  final String? agent;
  final VoidCallback onClose;
  final void Function(String noteId) onOpenNote;

  /// The Claude plugin's page (Settings › Claude), where the key is added.
  final VoidCallback onSettings;

  /// The chip's Open: the note an AI is on, at its caret.
  final void Function(AiOnline ai)? onOpenAi;

  /// Without a key: a request written into the "Ask Claude" note, for the connector's agents.
  final Future<void> Function(String request)? onInbox;

  /// A note's share link, made or found again, for the Copy link on the card of the notes a run wrote; null where
  /// the build has no share (signed out, a test).
  final Future<String> Function(String noteId)? onShareLink;

  /// Words the field starts with: what the page it was opened from is about. Another given while the chat is up
  /// (a wide window's dock pressed on another note) takes the field's place, where nothing has been written in it.
  final String? initial;

  /// Where pictures come from (see the header); none, and nothing can be attached.
  final ChatPictureSource? pictures;

  @override
  State<ClaudeChat> createState() => _ClaudeChatState();
}

class _ClaudeChatState extends State<ClaudeChat> {
  late final TextEditingController _field = TextEditingController(text: widget.initial ?? '');
  final FocusNode _focus = FocusNode(debugLabel: 'Claude chat');
  String? _problem;

  /// Requests sent to the inbox from this chat, shown as said.
  final List<String> _sent = [];

  /// Whether the model and effort pickers are open under the head.
  bool _choosing = false;
  void _toggleChoosing() => setState(() => _choosing = !_choosing);
  VoidCallback? _stopBack;

  /// The pictures waiting to go with the next message.
  final List<ChatImage> _images = [];

  /// How many pictures are being made ready.
  int _readying = 0;

  /// What the pictures' row says: why one was not added, or that the model cannot see them.
  String? _imageNote;

  /// "Keep pictures in notes": off until switched on, for this chat.
  bool _keepPictures = false;
  StreamSubscription<Uint8List>? _drops;

  @override
  void initState() {
    super.initState();
    _drops = widget.pictures?.dropped?.listen(_add);
  }

  /// How many more pictures the next message may take: its own limit, and the conversation's.
  int get _room {
    final left = widget.runner.picturesLeft - _images.length - _readying;
    final own = chatImageLimit - _images.length - _readying;
    return left < own ? left : own;
  }

  /// Why a picture cannot be added now, or null.
  String? get _cannotAttach {
    final runner = widget.runner;
    if (!runner.ready) return 'Pictures go to the AI you set up. Add one in Settings › AI.';
    if (!runner.seesImages) return '${runner.speaker} can’t see pictures with ${runner.claudeAnswers ? claudeModelLabel(runner.model) : runner.model}. $chatImageHint';
    if (widget.runner.picturesLeft - _images.length - _readying <= 0) return 'This chat holds $chatConversationImageLimit pictures at most. Start a new chat to send more.';
    if (_room <= 0) return 'Up to $chatImageLimit pictures a message.';
    return null;
  }

  /// The attach button: the chooser, or what stands in its way.
  Future<void> _attach() async {
    final cannot = _cannotAttach;
    if (cannot != null) {
      setState(() => _imageNote = cannot);
      return;
    }
    final pick = widget.pictures?.pick;
    if (pick == null) return;
    try {
      final bytes = await pick();
      if (bytes != null) await _add(bytes);
    } catch (error) {
      if (mounted) setState(() => _imageNote = error is StateError ? error.message : '$error');
    }
  }

  /// A picture chosen, pasted or dropped, made ready and put with the next message.
  Future<void> _add(Uint8List bytes) async {
    if (!mounted) return;
    final cannot = _cannotAttach;
    if (cannot != null) {
      setState(() => _imageNote = cannot);
      return;
    }
    setState(() {
      _readying += 1;
      _imageNote = null;
    });
    try {
      final image = await readyChatImage(bytes, jpeg: widget.pictures?.jpeg);
      if (mounted) setState(() => _images.add(image));
    } on ChatImageProblem catch (problem) {
      if (mounted) setState(() => _imageNote = problem.message);
    } finally {
      if (mounted) setState(() => _readying -= 1);
    }
  }

  void _remove(int index) => setState(() {
        _images.removeAt(index);
        _imageNote = null;
      });

  void _toggleKeep() => setState(() => _keepPictures = !_keepPictures);

  /// A Mac's paste in the field: a picture on the clipboard is attached, words go in as the field's own paste puts
  /// them.
  KeyEventResult _key(KeyEvent event) {
    final clipboard = widget.pictures?.clipboard;
    if (clipboard == null || event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyV) return KeyEventResult.ignored;
    final keys = HardwareKeyboard.instance;
    final command = defaultTargetPlatform == TargetPlatform.macOS ? keys.isMetaPressed : keys.isControlPressed;
    if (!command || keys.isAltPressed) return KeyEventResult.ignored;
    unawaited(_paste(clipboard));
    return KeyEventResult.handled;
  }

  Future<void> _paste(Future<({Uint8List? picture, String? text})> Function() clipboard) async {
    final ({Uint8List? picture, String? text}) got;
    try {
      got = await clipboard();
    } catch (_) {
      return;
    }
    final picture = got.picture;
    if (picture != null) return _add(picture);
    final text = got.text;
    if (text == null || text.isEmpty || !mounted) return;
    final value = _field.value;
    final selection = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
    final next = value.text.replaceRange(selection.start, selection.end, text);
    _field.value = value.copyWith(text: next, selection: TextSelection.collapsed(offset: selection.start + text.length));
  }

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
  void didUpdateWidget(ClaudeChat old) {
    super.didUpdateWidget(old);
    final initial = widget.initial;
    if (initial != null && initial != old.initial && (_field.text.trim().isEmpty || _field.text == old.initial)) _field.text = initial;
  }

  /// How much of the window's end the chat covers, as it was last said.
  double _covers = 0;

  void _cover(double width) {
    if (width == _covers) return;
    _covers = width;
    // After the frame: the docks that hear it are being built in it.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _covers == width) windowEndCover.value = width;
    });
  }

  @override
  void dispose() {
    if (_covers > 0) SchedulerBinding.instance.addPostFrameCallback((_) => windowEndCover.value = 0);
    _stopBack?.call();
    unawaited(_drops?.cancel());
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send([String? said]) async {
    final runner = widget.runner;
    final images = runner.ready ? List<ChatImage>.of(_images) : const <ChatImage>[];
    var words = (said ?? _field.text).trim();
    if (words.isEmpty && images.isNotEmpty) words = chatImageDefaultAsk;
    if (words.isEmpty || _readying > 0) return;
    setState(() {
      _problem = null;
      _imageNote = null;
      _images.clear();
    });
    if (said == null) _field.clear();
    if (images.isNotEmpty) {
      try {
        await runner.ask(words, images: images, keepPictures: _keepPictures);
      } catch (error) {
        // Not sent: the pictures wait again, for another model or a fix.
        if (mounted) {
          setState(() {
            _problem = '$error';
            _images.insertAll(0, images);
          });
        }
      }
      return;
    }
    if (!runner.ready) {
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
    final listen = Listenable.merge([widget.runner, widget.runner.settings, _field, if (widget.follow != null) widget.follow!]);
    final panel = Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      label: 'Chat with ${widget.agent ?? widget.runner.speaker}',
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
                  if (_choosing && widget.runner.settings.hasKey && widget.runner.claudeAnswers) _Choices(settings: widget.runner.settings),
                  Expanded(child: _Messages(state: this)),
                  _Composer(state: this),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // Over the whole window on a phone: nothing of the page is in reach then, and nothing moves for it.
    _cover(wide ? claudeChatPanelWidth : 0);
    if (!wide) return panel;
    return Align(alignment: Alignment.centerRight, child: SizedBox(width: claudeChatPanelWidth, height: double.infinity, child: panel));
  }
}

/// A round button of the head and the composer.
class _Round extends StatelessWidget {
  const _Round({super.key, required this.label, required this.onPressed, required this.child, this.filled = false, this.side});

  final String label;
  final VoidCallback? onPressed;
  final Widget child;
  final bool filled;

  /// How wide it is: the top bar's ring unless told (the composer's Send, sized to sit inside the field).
  final double? side;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = this.side ?? t.len('app-bar-ring');
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

/// The model and the effort, under the head while open: two of the kit's segmented controls, each choice kept at
/// once for this device (the Claude plugin's page keeps the same). Matt, 2026-10-17: "add a model and effort selector to
/// the agent page".
class _Choices extends StatelessWidget {
  const _Choices({required this.settings});

  final ClaudeSettings settings;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget label(String words) => Padding(
          padding: EdgeInsets.only(bottom: t.space(1)),
          child: Text(words, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('glacier-text-subtle'))),
        );
    // Short words in the control, where five must fit across a phone.
    const shortEffort = {'low': 'Low', 'medium': 'Med', 'high': 'High', 'xhigh': 'X-high', 'max': 'Max'};
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Container(
        key: const ValueKey('claude-choices'),
        padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(3)),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            label('Model'),
            GlacierSegmentedControl(
              key: const ValueKey('claude-model'),
              ariaLabel: 'Model',
              fullWidth: true,
              size: GlacierSegmentedSize.sm,
              options: [for (final model in claudeModels) GlacierSegmentedOption(value: model.id, label: Text(model.name))],
              value: settings.model,
              onValueChange: (id) => settings.setModel(id),
            ),
            SizedBox(height: t.space(3)),
            label('Effort: how hard Claude thinks before answering'),
            GlacierSegmentedControl(
              key: const ValueKey('claude-effort'),
              ariaLabel: 'Effort',
              fullWidth: true,
              size: GlacierSegmentedSize.sm,
              options: [for (final (id, _) in claudeEfforts) GlacierSegmentedOption(value: id, label: Text(shortEffort[id] ?? id))],
              value: settings.effort,
              onValueChange: (id) => settings.setEffort(id),
            ),
          ],
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
    // Another provider answering (docs/AI_PROVIDERS.md) says its model; its page, not this, is where it is changed.
    final other = !runner.claudeAnswers;
    final line = run != null && run.working
        ? (at == null ? 'Thinking…' : '${at.doing[0].toUpperCase()}${at.doing.substring(1)} ${at.title.isEmpty ? 'a note' : at.title}')
        : other
            ? runner.model
            : runner.settings.hasKey
                ? '${claudeModelLabel(runner.settings.model)} · ${claudeEffortLabel(runner.settings.effort)} effort'
                : 'No API key on this device';
    // The line under the name opens the model and effort pickers, while Claude is not at work.
    final choosable = !other && runner.settings.hasKey && !(run != null && run.working);
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
            decoration: BoxDecoration(shape: BoxShape.circle, color: other ? claudeSlate : claudeOrange),
            child: other ? const AppIcon(Lucide.sparkles, size: 16, color: claudeIvory) : const ClaudeMark(size: 16, color: claudeIvory),
          ),
          SizedBox(width: t.space(2)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(chat.agent ?? runner.speaker, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: ink)),
                if (!choosable)
                  Text(line, key: const ValueKey('claude-chat-line'), maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('glacier-text-subtle')))
                else
                  GlacierPressable(
                    key: const ValueKey('claude-choose'),
                    onPressed: state._toggleChoosing,
                    semanticLabel: 'Model and effort: $line. ${state._choosing ? 'Close' : 'Change'}',
                    builder: (context, pressing) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(line, key: const ValueKey('claude-chat-line'), maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('glacier-text-subtle'))),
                        ),
                        SizedBox(width: t.space(1)),
                        AppIcon(state._choosing ? Lucide.chevronUp : Lucide.chevronDown, size: 13, color: t.color('glacier-text-subtle')),
                      ],
                    ),
                  ),
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
    final ais = chat.follow?.ais ?? const <AiOnline>[];
    // The agent this chat is with, online now; else every AI online, as the chip's menu listed them.
    final agentName = chat.agent?.toLowerCase();
    final shown = agentName == null ? ais : ais.where((ai) => ai.name.toLowerCase() == agentName).toList();
    final speaker = runner.speaker;
    final items = <Widget>[
      if (!runner.ready)
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
      if (runner.conversation.isEmpty && state._sent.isEmpty && runner.ready)
        Padding(
          padding: EdgeInsets.symmetric(vertical: t.space(6)),
          child: Column(
            children: [
              if (runner.claudeAnswers) const ClaudeMark(size: 34) else AppIcon(Lucide.sparkles, size: 34, color: t.color('glacier-text-subtle')),
              SizedBox(height: t.space(3)),
              Text(
                'Ask $speaker to write a note, find something, or change a note. The note it writes in opens, and you watch it type.',
                textAlign: TextAlign.center,
                style: pageText(t, t.fontSize('sm'), color: t.color('glacier-text-subtle')),
              ),
            ],
          ),
        ),
      for (final run in runner.conversation) ..._runItems(context, run, chat),
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

  static List<Widget> _runItems(BuildContext context, ClaudeRun run, ClaudeChat chat) => [
        for (final step in run.steps)
          switch (step.kind) {
            'asked' => step.pictures.isEmpty ? _Bubble(words: step.words, mine: true) : _Sent(step: step),
            'said' => _Bubble(words: step.words),
            'thought' => _Thought(words: step.words),
            'notice' => _Quiet(step.words),
            _ => _Step(step: step, onOpenNote: chat.onOpenNote),
          },
        if (run.thinking.trim().isNotEmpty) _Thought(words: run.thinking.trim(), live: true),
        if (run.saying.trim().isNotEmpty) _Bubble(words: run.saying.trim(), live: true),
        if (run.working && run.saying.isEmpty && run.thinking.trim().isEmpty) _Quiet(run.state == ClaudeState.writing ? 'Writing…' : 'Thinking…'),
        if (run.state == ClaudeState.stopped) const _Quiet('Stopped.'),
        if (run.state == ClaudeState.failed) _Quiet(run.problem ?? 'Something went wrong.'),
        if (run.touched.isNotEmpty) _NoteLinks(run: run, chat: chat),
      ];
}

/// The notes a run made or changed, each a link: a press opens the note, and Copy link puts its share link on the
/// clipboard (Matt, 2026-10-30: "have claude chat share an embeded link to notes it creates and edits"). Drawn as
/// soon as the first note is touched and kept under the run's last words, so the notes a long answer talked about
/// are a tap away from it.
class _NoteLinks extends StatelessWidget {
  const _NoteLinks({required this.run, required this.chat});

  final ClaudeRun run;
  final ClaudeChat chat;

  Future<void> _copy(BuildContext context, String noteId) async {
    final toast = GlacierToast.of(context);
    try {
      final link = await chat.onShareLink!(noteId);
      await Clipboard.setData(ClipboardData(text: link));
      toast.toast(message: const Text('Link copied.'));
    } catch (failure) {
      toast.toast(message: Text('The link couldn’t be made: ${failureText(failure)}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final xs = t.fontSize('xs');
    final subtle = t.color('glacier-text-subtle');
    final ink = t.color('app-ink');
    return _Card(
      key: ValueKey('claude-notes:${identityHashCode(run)}'),
      children: [
        Text(run.touched.length == 1 ? 'The note' : 'The notes', style: pageText(t, xs, weight: 'medium', color: subtle)),
        for (final entry in run.touched.entries) ...[
          SizedBox(height: t.space(2)),
          Row(children: [
            Expanded(
              child: GlacierPressable(
                key: ValueKey('claude-note:${entry.key}'),
                onPressed: () => chat.onOpenNote(entry.key),
                semanticLabel: 'Open ${entry.value.isEmpty ? 'the note' : entry.value}',
                builder: (context, state) => Row(children: [
                  AppIcon(Lucide.fileText, size: 16, color: claudeOrange),
                  SizedBox(width: t.space(2)),
                  Expanded(
                    child: Text(entry.value.isEmpty ? 'Untitled' : entry.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: ink)),
                  ),
                  SizedBox(width: t.space(2)),
                  Text(run.made.contains(entry.key) ? 'New' : 'Changed', style: pageText(t, xs, color: subtle)),
                ]),
              ),
            ),
            if (chat.onShareLink != null) ...[
              SizedBox(width: t.space(2)),
              GlacierPressable(
                key: ValueKey('claude-note-link:${entry.key}'),
                onPressed: () => _copy(context, entry.key),
                semanticLabel: 'Copy a link to ${entry.value.isEmpty ? 'the note' : entry.value}',
                builder: (context, state) => Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon(Lucide.link, size: 14, color: claudeOrange),
                  SizedBox(width: t.space(1)),
                  Text('Copy link', style: pageText(t, xs, weight: 'medium', color: claudeOrange)),
                ]),
              ),
            ],
          ]),
        ],
      ],
    );
  }
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

/// What Claude's words are set in on its orange: white, as Matt asked (2026-10-18: "make the text in the agent's
/// bubble white instead of black"). It was the dark of the mark's page before, for its contrast (over 6 to 1 where
/// white is 3); the look won.
const Color _claudeBubbleInk = Color(0xFFFFFFFF);

/// A message, as a bubble (Matt, 2026-10-17: "make the messages formatted more like message bubbles match the color
/// of the AI agent for the messages it sends"): Claude's on the left in its own orange, the person's on the right in
/// a quiet wash of the ink. Each is rounded but for the corner by its speaker's side, where it tucks in.
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
    final text = Text(words, style: pageText(t, t.fontSize('sm'), color: mine ? t.color('app-ink') : _claudeBubbleInk));
    final round = Radius.circular(t.radius('xl'));
    const tucked = Radius.circular(5);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: (width < 420 ? width : 420) * 0.82),
        child: Container(
          margin: EdgeInsets.symmetric(vertical: t.space(1)),
          padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
          decoration: BoxDecoration(
            color: mine ? t.colorOf('color-mix(in oklch, var(--app-ink) 8%, transparent)') : claudeOrange,
            borderRadius: BorderRadius.only(
              topLeft: round,
              topRight: round,
              bottomLeft: mine ? round : tucked,
              bottomRight: mine ? tucked : round,
            ),
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

/// What Claude thought before it went on (lib/claude/claude_run.dart, "Claude's thinking, shown"): the summary in
/// the page's quiet text under a hairline of Claude's orange down its start, a few lines of it, so a long thought
/// does not push the conversation away. Still arriving, it is read out as it changes.
class _Thought extends StatelessWidget {
  const _Thought({required this.words, this.live = false});

  final String words;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      key: const ValueKey('claude-thought'),
      margin: EdgeInsets.symmetric(vertical: t.space(1)),
      padding: EdgeInsets.only(left: t.space(2)),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: claudeOrange.withValues(alpha: 0.45), width: 2))),
      child: Semantics(
        liveRegion: live,
        label: 'Claude thought: $words',
        child: ExcludeSemantics(
          child: Text(words, maxLines: live ? 6 : 4, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('glacier-text-subtle'))),
        ),
      ),
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
    final hasKey = runner.ready;
    final speaker = runner.speaker;
    if (!hasKey && chat.onInbox == null) return const SizedBox.shrink();
    // Send is a small round inside the field's trailing end, three fifths of its height (Matt, 2026-10-17: "Make the
    // send / delete smaller"), and Stop the same.
    final send = (t.len('glacier-control-height-lg') * 0.6).roundToDouble();
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
                  words: run.following ? 'Watch $speaker in ${run.at!.title.isEmpty ? 'the note' : run.at!.title}' : 'Watch again',
                  // The note opened (the chat makes way), Claude's caret shown where it last typed, scrolled to.
                  onPressed: run.follow,
                ),
              ]),
            ),
          if (hasKey) _PictureTray(state: state),
          // One field, Send inside its trailing end (Matt, 2026-10-17: "a more streamlined text input that's inline
          // with the button, the send button should be nested inside the input as well to the right"): the kit's
          // GlacierInput, at its large size, with Send (Stop while Claude works) as its trailing control. Before it,
          // the picture button, where pictures can come from.
          Row(children: [
            if (hasKey && chat.pictures != null) ...[
              _AttachButton(state: state),
              SizedBox(width: t.space(2)),
            ],
            Expanded(child: GlacierInput(
            key: const ValueKey('claude-ask'),
            size: GlacierFieldSize.lg,
            ariaLabel: hasKey ? 'Message $speaker' : 'A request for your Ask Claude note',
            controller: state._field,
            focusNode: state._focus,
            placeholder: !hasKey
                ? 'A request for the Ask Claude note…'
                : runner.conversation.isEmpty
                    ? 'Message $speaker'
                    : 'Reply to $speaker',
            autoFocus: runner.conversation.isEmpty,
            enterKeyHint: TextInputAction.send,
            onSubmitted: (_) => state._send(),
            onKeyDown: chat.pictures?.clipboard == null ? null : state._key,
            trailingExtent: send,
            trailing: runner.working
                ? _Round(key: const ValueKey('claude-stop'), label: 'Stop Claude', onPressed: runner.stop, filled: true, side: send, child: const AppIcon(Lucide.square, size: 11, color: claudeIvory))
                : _Round(key: const ValueKey('claude-send'), label: 'Send', onPressed: state._send, filled: true, side: send, child: const AppIcon(Lucide.arrowUp, size: 15, color: claudeIvory)),
          )),
          ]),
        ],
      ),
    );
  }
}

/// The picture button before the field: the device's chooser, or, faded, why not (the model cannot see pictures, no AI
/// is set up, the limit is reached), said under the pictures' row when pressed.
class _AttachButton extends StatelessWidget {
  const _AttachButton({required this.state});

  final _ClaudeChatState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final cannot = state._cannotAttach;
    final ink = t.color('app-ink');
    return Opacity(
      opacity: cannot == null ? 1 : 0.4,
      child: _Round(
        key: const ValueKey('claude-attach'),
        label: cannot == null ? 'Attach a picture' : 'Attach a picture, not available: $cannot',
        onPressed: state._attach,
        child: AppIcon(Lucide.imagePlus, size: 20, color: ink),
      ),
    );
  }
}

/// The pictures waiting to go, each a thumbnail with its ×; the chips to send while nothing is written; "Keep pictures
/// in notes"; and what the row has to say.
class _PictureTray extends StatelessWidget {
  const _PictureTray({required this.state});

  final _ClaudeChatState state;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final images = state._images;
    final note = state._imageNote;
    if (images.isEmpty && state._readying == 0 && note == null) return const SizedBox.shrink();
    final subtle = t.color('glacier-text-subtle');
    final xs = t.fontSize('xs');
    final runner = state.widget.runner;
    final empty = state._field.text.trim().isEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (images.isNotEmpty || state._readying > 0)
            SingleChildScrollView(
              key: const ValueKey('claude-pictures'),
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (var i = 0; i < images.length; i += 1) _Thumb(image: images[i], index: i, onRemove: () => state._remove(i)),
                for (var i = 0; i < state._readying; i += 1)
                  Container(
                    width: 56,
                    height: 56,
                    margin: EdgeInsets.only(right: t.space(2)),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(t.radius('md')), color: t.colorOf('color-mix(in oklch, var(--app-ink) 8%, transparent)')),
                  ),
              ]),
            ),
          if (images.isNotEmpty && empty && !runner.working) ...[
            SizedBox(height: t.space(2)),
            Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [
              for (final chip in chatImageChips) _Pill(key: ValueKey('claude-chip:$chip'), words: chip, onPressed: () => state._send(chip)),
            ]),
          ],
          if (images.isNotEmpty && runner.keepPicture != null) ...[
            SizedBox(height: t.space(2)),
            GlacierPressable(
              key: const ValueKey('claude-keep-pictures'),
              onPressed: state._toggleKeep,
              semanticLabel: 'Keep pictures in notes: ${state._keepPictures ? 'on' : 'off'}',
              builder: (context, pressing) => Row(children: [
                AppIcon(state._keepPictures ? Lucide.squareCheckBig : Lucide.square, size: 14, color: state._keepPictures ? claudeOrange : subtle),
                SizedBox(width: t.space(2)),
                Flexible(child: Text('Keep pictures in notes', style: pageText(t, xs, color: subtle))),
              ]),
            ),
          ],
          if (note != null) ...[
            SizedBox(height: t.space(1)),
            Text(note, key: const ValueKey('claude-picture-note'), style: pageText(t, xs, color: subtle)),
          ],
        ],
      ),
    );
  }
}

/// One picture waiting to go: a thumbnail, its × at the corner.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.image, required this.index, required this.onRemove});

  final ChatImage image;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(right: t.space(2), top: 4),
      child: Stack(clipBehavior: Clip.none, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(t.radius('md')),
          child: Image.memory(image.bytes, key: ValueKey('claude-picture:$index'), width: 56, height: 56, fit: BoxFit.cover, cacheWidth: 168, gaplessPlayback: true, semanticLabel: 'Picture ${index + 1}'),
        ),
        Positioned(
          top: -4,
          right: -4,
          child: GlacierPressable(
            key: ValueKey('claude-picture-remove:$index'),
            onPressed: onRemove,
            semanticLabel: 'Remove picture ${index + 1}',
            builder: (context, state) => Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: claudeSlate, border: Border.all(color: t.color('app-paper'), width: 1.5)),
              child: const AppIcon(Lucide.x, size: 11, color: claudeIvory),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The person's message with the pictures it carried: the pictures over the bubble, on the right.
class _Sent extends StatelessWidget {
  const _Sent({required this.step});

  final ClaudeStep step;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: EdgeInsets.only(top: t.space(1)),
        child: Wrap(alignment: WrapAlignment.end, spacing: t.space(1), runSpacing: t.space(1), children: [
          for (final picture in step.pictures)
            ClipRRect(
              borderRadius: BorderRadius.circular(t.radius('md')),
              child: Image.memory(picture.bytes, width: 72, height: 72, fit: BoxFit.cover, cacheWidth: 216, gaplessPlayback: true, excludeFromSemantics: true),
            ),
        ]),
      ),
      _Bubble(words: step.words, mine: true),
    ]);
  }
}
