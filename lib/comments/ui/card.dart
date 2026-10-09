/// A comment thread drawn as a card (docs/SHARED.md, S8): who said what and when, in their colour, the replies under
/// it, a field to reply in, Resolve or Reopen, and Delete thread; a new comment's field; and the note's threads as a
/// list. A port of `src/app/editor/CommentCard.tsx` with its look, `CommentCard.module.css`, rule for rule. The
/// note's thread card is these inside the app's sheet (sheet.dart), and the ```comments fence is drawn as the list
/// (lib/editor/comments/comments.dart).
///
/// They take a thread as data and say what was pressed, and nothing here reads a note: a canvas's threads (S9, a
/// `comments` array in its JSON) are drawn by the same card, from the same shape (words.dart [CardThread]).
///
/// What differs:
/// - **How the words are set is handed in** ([CardType]). On the page the card inherits its face and its leading
///   from where it stands: the app's own face with `line-height: normal` in the sheet, the note's face at the
///   editor's 1.6 where the fence is drawn in the note. A widget inherits neither, so each place says its own.
/// - **The field's rows** are the page's `rows={min(5, max(1, lines))}`: as many as the words have line breaks,
///   five at most, a long line scrolling inside its row as a `textarea`'s does.
/// - **Enter sends** from a keyboard with keys, Shift+Enter is a new line; the phone's keyboard has Send where its
///   Enter was (`enterKeyHint="send"`), as on the page.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../sheet/css.dart';
import '../../sheet/flow.dart';
import '../../sheet/kit.dart';
import 'words.dart';

export 'words.dart';

/// How the card's words are set where it is drawn: the words at a size, in a weight and a colour, and whether a
/// line of them is `line-height: normal` (rounded as a page rounds it) or a multiple of its size.
class CardType {
  const CardType(this.at, {this.normal = true});

  /// In the app's sheet: the page's own face, `line-height: normal`.
  factory CardType.page(Tokens t) => CardType((px, {weight = 'regular', color}) => pageText(t, px, weight: weight, color: color));

  final TextStyle Function(double px, {String weight, Color? color}) at;
  final bool normal;

  /// Words set as the page sets them, a line as tall as the page's to the fraction.
  Widget words(BuildContext context, String text, double px, {String weight = 'regular', Color? color, int? maxLines, TextOverflow? overflow}) => ExactLines.of(
        Text(text, style: at(px, weight: weight, color: color), maxLines: maxLines, overflow: overflow),
        normal: normal,
        dpr: context.tokens.css.lineDpr,
      );
}

/// `data-hue` on an element: the tokens with `--app-space` the hue's (app/ink.css).
Tokens hued(Tokens t, String hue) => t.child(attrs: {'hue': hue});

/// A person's initial in their colour: the member rows' mark (notes/OrganizationScreen.tsx `.avatar`).
class CommentInitial extends StatelessWidget {
  const CommentInitial({super.key, required this.by, required this.people, required this.type});

  final String by;
  final CardPeople people;
  final CardType type;

  /// The letter drawn: the handle's own first, also for "You", unless there is no handle (`me`).
  static String letterOf(String by, CardPeople people) {
    final name = nameOf(by, people);
    final from = name == 'You' && by != 'me' ? by : name;
    return from.isEmpty ? '' : String.fromCharCode(from.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final worn = hued(t, people.colour(by));
    final space = worn.color('app-space');
    final side = t.lenOf('1.875rem');
    return ExcludeSemantics(
      child: Container(
        // `inline-size: 1.875rem; block-size: 1.875rem; border-radius: full; display: grid; place-items: center;
        // background: color-mix(in oklch, var(--app-space) 22%, transparent); color: var(--app-space)`
        width: side,
        height: side,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: worn.colorOf('color-mix(in oklch, var(--app-space) 22%, transparent)')),
        // `font-size: var(--glacier-font-size-sm); font-weight: var(--glacier-font-weight-semibold)`
        child: Text(letterOf(by, people), style: type.at(t.fontSize('sm'), weight: 'semibold', color: space)),
      ),
    );
  }
}

/// `.byline`: who, and how long ago, on one baseline.
class _Byline extends StatelessWidget {
  const _Byline({required this.by, required this.at, required this.people, required this.type, required this.now});

  final String by;
  final String at;
  final CardPeople people;
  final CardType type;
  final int now;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // `display: flex; flex-wrap: wrap; align-items: baseline; gap: var(--glacier-space-2)`
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      spacing: t.space(2),
      children: [
        // `.who { font-weight: semibold; color: var(--glacier-text) }`
        Flexible(child: type.words(context, nameOf(by, people), t.fontSize('md'), weight: 'semibold', color: t.color('glacier-text'), maxLines: 1, overflow: TextOverflow.ellipsis)),
        // `.when { font-size: sm; color: var(--glacier-text-subtle) }`
        type.words(context, ago(at, now), t.fontSize('sm'), color: t.color('glacier-text-subtle')),
      ],
    );
  }
}

/// `.comment`: one comment of a thread, a reply in by a step.
class _OneComment extends StatelessWidget {
  const _OneComment({required this.comment, required this.people, required this.type, required this.now, this.reply = false});

  final CardComment comment;
  final CardPeople people;
  final CardType type;
  final int now;
  final bool reply;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      // `.comment[data-reply] { padding-inline-start: var(--glacier-space-6) }`
      padding: EdgeInsetsDirectional.only(start: reply ? t.space(6) : 0),
      // `display: flex; align-items: flex-start; gap: var(--glacier-space-3)`
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: t.space(3),
        children: [
          CommentInitial(by: comment.by, people: people, type: type),
          Expanded(
            // `.body { display: grid; gap: 2px; min-inline-size: 0 }`
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                _Byline(by: comment.by, at: comment.at, people: people, type: type, now: now),
                // `.words { color: var(--glacier-text); white-space: pre-wrap; overflow-wrap: anywhere }`
                type.words(context, comment.words, t.fontSize('md'), color: t.color('glacier-text')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A field for words, a send at its end, quiet until there are words: the More sheet's Ask field's shape
/// (lib/note/note_settings.dart `AskField`), taking several lines. Enter sends; Shift+Enter is a new line, as in
/// any chat (`CommentField`).
class CommentField extends StatefulWidget {
  const CommentField({super.key, required this.label, required this.placeholder, required this.send, required this.onSend, this.autoFocus = false});

  /// What the field is called, for a screen reader.
  final String label;
  final String placeholder;

  /// What the send is called.
  final String send;
  final ValueChanged<String> onSend;
  final bool autoFocus;

  @override
  State<CommentField> createState() => _CommentFieldState();
}

class _CommentFieldState extends State<CommentField> {
  final TextEditingController _words = TextEditingController();
  late final FocusNode _focus = FocusNode(debugLabel: widget.label, onKeyEvent: _onKey);

  @override
  void initState() {
    super.initState();
    _words.addListener(() => setState(() {}));
    if (widget.autoFocus) {
      // Once it is on the screen: a sheet is built a frame before it is laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _words.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final said = _words.text.trim();
    if (said.isEmpty) return;
    widget.onSend(said);
    _words.clear();
  }

  /// `onKeyDown`: Enter sends, unless Shift is held or the keyboard is in the middle of a word it is composing.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || (event.logicalKey != LogicalKeyboardKey.enter && event.logicalKey != LogicalKeyboardKey.numpadEnter)) return KeyEventResult.ignored;
    if (_words.value.composing.isValid) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) {
      final value = _words.value;
      final at = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
      _words.value = TextEditingValue(text: value.text.replaceRange(at.start, at.end, '\n'), selection: TextSelection.collapsed(offset: at.start + 1));
      return KeyEventResult.handled;
    }
    _submit();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final md = t.fontSize('md');
    final ink = t.color('glacier-text');
    final empty = _words.text.trim().isEmpty;
    // `.input { font-size: var(--glacier-font-size-md); line-height: 1.4 }`
    final style = pageText(t, md, color: ink, height: 1.4);
    final rows = '\n'.allMatches(_words.text).length + 1;
    final shown = rows < 1 ? 1 : (rows > 5 ? 5 : rows);
    final send = t.lenOf('2.25rem');
    return Semantics(
      container: true,
      label: widget.label,
      child: DecoratedBox(
        // `border: 1px solid var(--glacier-border-subtle); border-radius: var(--glacier-radius-lg);
        // background: var(--app-paper)`
        decoration: BoxDecoration(
          color: t.color('app-paper'),
          borderRadius: BorderRadius.circular(t.radius('lg')),
          border: Border.all(color: t.color('glacier-border-subtle'), width: snapBorder(context, 1)),
        ),
        child: Padding(
          // `padding: space-2 space-2 space-2 space-4`, inside the border.
          padding: EdgeInsetsDirectional.fromSTEB(t.space(4), t.space(2), t.space(2), t.space(2)).add(EdgeInsets.all(snapBorder(context, 1))),
          // `display: flex; align-items: flex-end; gap: var(--glacier-space-3)`
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: t.space(3),
            children: [
              Expanded(
                child: Padding(
                  // `.input { padding: var(--glacier-space-2) 0 }`
                  padding: EdgeInsets.symmetric(vertical: t.space(2)),
                  child: Stack(
                    alignment: AlignmentDirectional.topStart,
                    children: [
                      // `.input::placeholder { color: var(--glacier-text-subtle) }`
                      if (_words.text.isEmpty) ExcludeSemantics(child: Text(widget.placeholder, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: style.copyWith(color: t.color('glacier-text-subtle')))),
                      Semantics(
                        label: widget.label,
                        textField: true,
                        child: EditableText(
                          controller: _words,
                          focusNode: _focus,
                          style: style,
                          cursorColor: ink,
                          cursorWidth: 1,
                          backgroundCursorColor: t.color('glacier-text-subtle'),
                          selectionColor: t.color('glacier-selection'),
                          minLines: shown,
                          maxLines: shown,
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submit(),
                          keyboardAppearance: t.isDark ? Brightness.dark : Brightness.light,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              GlacierPressable(
                onPressed: empty ? null : _submit,
                semanticLabel: widget.send,
                builder: (context, state) {
                  // `.send { color: var(--glacier-text) }`, `.send:disabled { color: var(--glacier-text-muted) }`
                  final color = empty ? t.color('glacier-text-muted') : ink;
                  return Container(
                    // `inline-size: 2.25rem; block-size: 2.25rem; border: var(--app-line) solid currentColor;
                    // border-radius: 50%`
                    width: send,
                    height: send,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: snapBorder(context, t.len('app-line')))),
                    child: AppIcon(Lucide.arrowUp, size: 18, strokeWidth: 2.2, color: color),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.quote`: the words the thread is about, washed in its author's colour as they are in the note.
class _Quote extends StatelessWidget {
  const _Quote({required this.words, required this.type, this.hue, this.resolved = false});

  final String words;
  final CardType type;

  /// `data-hue`; null for a new comment's, which has no author yet.
  final String? hue;
  final bool resolved;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final worn = hue == null ? null : hued(t, hue!);
    // `.quote { border-inline-start: 3px solid var(--app-ink-3); background: var(--app-wash) }`;
    // `.quote[data-hue] { border-inline-start-color: var(--app-space);
    //   background: color-mix(in oklch, var(--app-space) 14%, transparent) }`;
    // `.thread[data-resolved] .quote { border-inline-start-color: var(--app-ink-3); background: none }`.
    final edge = resolved || worn == null ? t.color('app-ink-3') : worn.color('app-space');
    final ground = resolved
        ? null
        : worn == null
            ? t.color('app-wash')
            : worn.colorOf('color-mix(in oklch, var(--app-space) 14%, transparent)');
    return ClipRRect(
      // `border-radius: var(--glacier-radius-sm)`
      borderRadius: BorderRadius.circular(t.radius('sm')),
      child: DecoratedBox(
        decoration: BoxDecoration(color: ground, border: BorderDirectional(start: BorderSide(color: edge, width: 3))),
        child: Padding(
          // `padding: var(--glacier-space-2) var(--glacier-space-3)`, inside the edge.
          padding: EdgeInsetsDirectional.fromSTEB(t.space(3) + 3, t.space(2), t.space(3), t.space(2)),
          // `color: var(--glacier-text); font-size: sm; white-space: pre-wrap; overflow-wrap: anywhere`
          child: Align(alignment: AlignmentDirectional.centerStart, child: type.words(context, words, t.fontSize('sm'), color: t.color('glacier-text'))),
        ),
      ),
    );
  }
}

/// How long Delete thread waits for its second press, as leaving an organization does (`ARMED_MS`).
const Duration deleteArmed = Duration(milliseconds: 4000);

/// A thread's card: its comments, a reply field, Resolve or Reopen, and Delete thread, which asks a second press
/// (`CommentThread`).
class CommentThread extends StatefulWidget {
  const CommentThread({
    super.key,
    required this.thread,
    required this.people,
    this.quote,
    required this.onReply,
    required this.onResolve,
    required this.onReopen,
    required this.onDelete,
    this.now,
    this.type,
  });

  final CardThread thread;
  final CardPeople people;

  /// The words the thread is about, as the note has them; null for one anchored after a line.
  final String? quote;
  final ValueChanged<String> onReply;
  final VoidCallback onResolve;
  final VoidCallback onReopen;
  final VoidCallback onDelete;

  /// This moment in ms, for "2 hr ago"; the clock's unless given.
  final int? now;
  final CardType? type;

  @override
  State<CommentThread> createState() => _CommentThreadState();
}

class _CommentThreadState extends State<CommentThread> {
  bool _armed = false;
  Timer? _disarm;

  @override
  void dispose() {
    _disarm?.cancel();
    super.dispose();
  }

  void _delete() {
    _disarm?.cancel();
    if (!_armed) {
      setState(() => _armed = true);
      _disarm = Timer(deleteArmed, () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    setState(() => _armed = false);
    widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final type = widget.type ?? CardType.page(t);
    final thread = widget.thread;
    final people = widget.people;
    final now = widget.now ?? DateTime.now().millisecondsSinceEpoch;
    final resolved = thread.resolved;
    final quote = widget.quote;
    // `.thread { display: grid; gap: var(--glacier-space-3) }`
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: t.space(3),
      children: [
        if (quote != null && quote.isNotEmpty) _Quote(words: quote, type: type, hue: people.colour(thread.head.by), resolved: resolved != null),
        // `.comments { display: grid; gap: var(--glacier-space-3) }`
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: t.space(3),
          children: [
            _OneComment(comment: thread.head, people: people, type: type, now: now),
            for (final reply in thread.replies) _OneComment(comment: reply, people: people, type: type, now: now, reply: true),
          ],
        ),
        if (resolved != null)
          // `.resolved { font-size: sm; color: var(--glacier-text-subtle) }`
          type.words(context, 'Resolved by ${nameOf(resolved.by, people)}, ${ago(resolved.at, now).toLowerCase()}.', t.fontSize('sm'), color: t.color('glacier-text-subtle')),
        CommentField(label: 'Reply', placeholder: resolved != null ? 'Reply, and it stays resolved' : 'Reply', send: 'Send reply', onSend: widget.onReply),
        SheetGroup(
          children: [
            if (resolved != null)
              SheetRow(icon: const AppIcon(Lucide.rotateCcw, size: 18, strokeWidth: 2.2), label: 'Reopen', hint: 'Its wash comes back on the words.', onPress: widget.onReopen)
            else
              SheetRow(icon: const AppIcon(Lucide.circleCheck, size: 18, strokeWidth: 2.2), label: 'Resolve', hint: 'The thread stays, without its wash.', onPress: widget.onResolve),
            SheetRow(
              icon: const AppIcon(Lucide.trash2, size: 18, strokeWidth: 2.2),
              label: _armed ? 'Delete it? Press again' : 'Delete thread',
              hint: _armed ? 'Its comments and its mark in the note go.' : null,
              danger: true,
              onPress: _delete,
            ),
          ],
        ),
      ],
    );
  }
}

/// A new comment's card: the words it is about, and a field to write it in, focused (`NewComment`).
class NewComment extends StatelessWidget {
  const NewComment({super.key, required this.quote, required this.onSave, this.type});

  final String? quote;
  final ValueChanged<String> onSave;
  final CardType? type;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final said = quote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: t.space(3),
      children: [
        if (said != null && said.isNotEmpty) _Quote(words: said, type: type ?? CardType.page(t)),
        CommentField(label: 'Comment', placeholder: 'Write a comment', send: 'Add comment', onSend: onSave, autoFocus: true),
      ],
    );
  }
}

/// The first line of some words, cut to [max] characters (`firstLine`).
String firstLine(String words, [int max = 90]) {
  final line = words.split('\n').first;
  return line.length > max ? '${line.substring(0, max - 1).trimRight()}…' : line;
}

/// The threads in the order the list shows them: open ones first.
List<CardThread> listOrder(Iterable<CardThread> threads) => [
      for (final thread in threads)
        if (thread.resolved == null) thread,
      for (final thread in threads)
        if (thread.resolved != null) thread,
    ];

/// The threads as a list, open ones first: who started each, its first words, its replies, and whether it is
/// resolved (`CommentList`).
class CommentList extends StatelessWidget {
  const CommentList({super.key, required this.threads, required this.people, required this.onOpen, this.now, this.type});

  final List<CardThread> threads;
  final CardPeople people;
  final ValueChanged<String> onOpen;
  final int? now;
  final CardType? type;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final type = this.type ?? CardType.page(t);
    final now = this.now ?? DateTime.now().millisecondsSinceEpoch;
    final sm = t.fontSize('sm');
    final quiet = t.color('glacier-text-subtle');
    // `.list { display: grid; gap: var(--glacier-space-3) }`
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: t.space(3),
      children: [
        for (final thread in listOrder(threads))
          GlacierPressable(
            key: ValueKey<String>('thread ${thread.id}'),
            onPressed: () => onOpen(thread.id),
            builder: (context, state) => Opacity(
              // `.item[data-resolved] { opacity: 0.6 }`
              opacity: thread.resolved != null ? 0.6 : 1,
              child: ColoredBox(
                // `.item:active { background: var(--app-wash) }`
                color: state.pressed ? t.color('app-wash') : const Color(0x00000000),
                child: Padding(
                  // `padding: var(--glacier-space-2) 0`
                  padding: EdgeInsets.symmetric(vertical: t.space(2)),
                  // `display: flex; align-items: flex-start; gap: var(--glacier-space-3); inline-size: 100%`
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: t.space(3),
                    children: [
                      CommentInitial(by: thread.head.by, people: people, type: type),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          spacing: 2,
                          children: [
                            _Byline(by: thread.head.by, at: thread.head.at, people: people, type: type, now: now),
                            type.words(context, firstLine(thread.head.words), t.fontSize('md'), color: t.color('glacier-text')),
                            if (thread.replies.isNotEmpty || thread.resolved != null)
                              // `.meta { display: flex; flex-wrap: wrap; gap: var(--glacier-space-3); font-size: sm;
                              //   color: var(--glacier-text-subtle) }`
                              Wrap(
                                spacing: t.space(3),
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (thread.replies.isNotEmpty)
                                    // `.replies { display: inline-flex; align-items: center; gap: var(--glacier-space-1) }`
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      spacing: t.space(1),
                                      children: [
                                        AppIcon(Lucide.messageSquare, size: 12, strokeWidth: 2.2, color: quiet),
                                        type.words(context, repliesWords(thread.replies.length), sm, color: quiet),
                                      ],
                                    ),
                                  if (thread.resolved != null) type.words(context, 'Resolved', sm, color: quiet),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A block of a sheet with the card in it: the sheet lays its children out as blocks (flow.dart).
Widget sheetBlock(Widget child) => CssFlow.block(child: child);
