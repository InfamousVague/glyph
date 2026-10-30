/// Mentions in the editor (Matt, 2026-10-30: "add all 12", @mentions of people and dates; lib/mentions/mention_syntax.dart
/// says what one is): drawn as chips, a day typed as words written as the day, and the at sign's picker.
///
/// - **A person** is a chip in their colour: a member of the note's organization in the hue they wear there (the
///   comments' colours, lib/comments/colours.dart), anyone else - and everyone in a note of the person's own, where
///   there is nobody to tell - in the quiet ink. On a list item's line the person is its assignee, and the field's
///   own chip is drawn (field_chips.dart), not this one.
/// - **A day** is a chip in the second ink, and in red once it has passed (today is not past).
/// - **A day typed as words** - `@today`, `@tomorrow`, `@next friday`, `@in 3 days`, `@nov 6` - becomes the day,
///   `@2026-11-06`, as the space after it is typed, the way a snippet's trigger becomes its words
///   (lib/editor/input/snippets.dart): one step, which Undo takes back to the words as they were typed.
/// - **The picker**: an at sign typed where a mention may open asks for one ([mentionAsk]): the words typed after it
///   are the question, and whoever made the editor shows the people and days that answer it and writes the one
///   picked ([MentionHooks.picking], lib/mentions/ui/mention_picker.dart). The arrow keys, Enter, Tab and Escape are
///   the list's while it is up. It goes when the caret leaves the words, a space is typed after a name, or Escape.
///
/// Nothing in code, an address, maths, HTML or the front matter, as the syntax says, and the picker not there either.
library;

import 'dart:ui' show Color;

import '../../comments/ui/card.dart' show hued;
import '../../core/workspaces.dart' show workspaceHues;
import '../../core/item_syntax.dart' show listLead;
import '../../mentions/mention_syntax.dart';
import '../commands/commands.dart' show KeyBinding;
import '../editor.dart';
import '../input/keymap.dart' show editorKeymap;
import '../looks/look.dart';
import '../looks/sheets.dart';
import '../marks/run_paint.dart';
import '../syntax/syntax.dart';
import '../view/extended.dart' show frontMatter;
import '../view/syntax_tree.dart';
import 'inline_box.dart';

/// What the editor asks of whoever made it, each asked as it is used.
class MentionHooks {
  const MentionHooks({this.hue, this.today, this.picking});

  /// The hue a person wears here: a workspace hue for a member of the note's organization, null for anyone else.
  final String? Function(String handle)? hue;

  /// The day it is; the clock's when absent.
  final DateTime Function()? today;

  /// Told of the at sign's question as it changes, and handed the list's keys while one is asked; none, and an at
  /// sign asks nothing.
  final MentionPicking? picking;
}

/// What a picker is told and asked (lib/mentions/ui/mention_picker.dart).
abstract interface class MentionPicking {
  /// The question now: null when none is asked. [view] is the editor it is asked in.
  void asked(EditorViewLike view, MentionAsk? ask);

  /// A key the list may take while a question is asked: `ArrowDown`, `ArrowUp`, `Enter`, `Tab`, `Escape`. True when
  /// it took it; [target] is where a pick is written.
  bool key(String key, StateCommandTarget target);
}

/// The at sign's question: where the at sign is, and the words typed after it to the caret.
class MentionAsk {
  const MentionAsk(this.from, this.query);

  final int from;
  final String query;

  /// Where the words end: the caret.
  int get to => from + 1 + query.length;

  @override
  bool operator ==(Object other) => other is MentionAsk && other.from == from && other.query == query;

  @override
  int get hashCode => Object.hash(from, query);

  @override
  String toString() => 'MentionAsk($from, "$query")';
}

final Facet<MentionHooks, MentionHooks?> _hooks = Facet.define<MentionHooks, MentionHooks?>(combine: (values) => values.isEmpty ? null : values.first);

/// The question closed: Escape, a pick written, or the picker's own close.
final StateEffectType<bool> closeMentionAsk = StateEffect.define<bool>();

/// The chips drawn again: the colours arrived, or the day turned.
final StateEffectType<int> refreshMentions = StateEffect.define<int>();

final RegExp _opens = RegExp(r'[\s([{]');

/// Words after an at sign that a day typed as words may still be on its way to: `next`, `this`, `in 3`.
final RegExp _dayOnItsWay = RegExp(r'^(next|this|in)( \d{0,3}( [a-z]*)?| [a-z]*)?$', caseSensitive: false);
final RegExp _askWords = RegExp(r'^[\p{L}\p{N}_.-]*$', unicode: true);

/// Whether a transaction typed an at sign just before the caret, where a mention may open.
bool _typedAt(Transaction tr) {
  if (!tr.docChanged || !tr.isUserEvent('input.type') || tr.isUserEvent('input.type.compose')) return false;
  final head = tr.newSelection.main;
  if (!head.empty || head.head < 1) return false;
  var typed = false;
  tr.changes.iterChanges((fromA, toA, fromB, toB, inserted) {
    // The last letter alone: a whole string of what was put in would be made on every key.
    if (toB == head.head && inserted.length > 0 && inserted.sliceString(inserted.length - 1) == '@') typed = true;
  });
  if (!typed) return false;
  final doc = tr.newDoc;
  final at = head.head - 1;
  return at == 0 || _opens.hasMatch(doc.sliceString(at - 1, at));
}

/// The question as [tr] leaves it, from what it was.
MentionAsk? _nextAsk(MentionAsk? was, Transaction tr) {
  if (tr.effects.any((effect) => effect.isOf(closeMentionAsk))) return null;
  final head = tr.newSelection.main;
  if (!head.empty) return null;
  var ask = was;
  if (ask != null && tr.docChanged) ask = MentionAsk(tr.changes.mapPos(ask.from, 1), ask.query);
  if (_typedAt(tr)) ask = MentionAsk(head.head - 1, '');
  if (ask == null) return null;
  final doc = tr.newDoc;
  if (ask.from >= doc.length || head.head <= ask.from || doc.sliceString(ask.from, ask.from + 1) != '@') return null;
  final query = doc.sliceString(ask.from + 1, head.head);
  if (query.length > 40 || query.contains('\n')) return null;
  // A space ends a name; a day typed as words may have one or two on its way (`next friday`, `in 3 days`).
  if (!_askWords.hasMatch(query) && !_dayOnItsWay.hasMatch(query)) return null;
  return ask.query == query && ask == was ? was : MentionAsk(ask.from, query);
}

/// The at sign's question, as the state holds it.
final StateField<MentionAsk?> mentionAsk = StateField.define<MentionAsk?>(create: (_) => null, update: _nextAsk);

/// Whether [at] is somewhere a mention is only words: code, an address and the rest, or the front matter.
bool _quietAt(EditorState state, int at) {
  final front = frontMatter(state.doc);
  if (front != null) {
    final line = state.doc.lineAt(at).number;
    if (line >= front.from && line <= front.to) return true;
  }
  return inQuietText(syntaxTree(state), at);
}

/// What a pick writes over the at sign and the words after it: `@handle ` or `@2026-11-06 `, the caret after the
/// space, as one step of its own.
TransactionSpec mentionWritten(MentionAsk ask, String value) {
  final text = '@$value ';
  return TransactionSpec(
    changes: ChangeSpec(from: ask.from, to: ask.to, insert: text),
    selection: EditorSelection.single(ask.from + text.length),
    effects: <StateEffect<Object?>>[closeMentionAsk.of(true)],
    userEvent: 'input.complete',
    annotations: isolateHistory.of('full'),
    scrollIntoView: true,
  );
}

// ---- a day typed as words, written as the day -------------------------------------------------------------------

/// Whether what a transaction put in ends with a space where the caret is.
bool _endsWithSpaceAtCaret(Transaction tr) {
  final head = tr.newSelection.main;
  if (!head.empty) return false;
  var ends = false;
  tr.changes.iterChanges((fromA, toA, fromB, toB, inserted) {
    if (toB == head.head && inserted.length > 0 && inserted.sliceString(inserted.length - 1) == ' ') ends = true;
  });
  return ends;
}

/// A transaction that typed a space after a day typed as words, as the one that writes the day there instead; the
/// transaction itself otherwise.
Object dayOnSpace(Transaction tr, DateTime today) {
  if (!tr.docChanged || !tr.isUserEvent('input.type') || tr.isUserEvent('input.type.compose')) return tr;
  if (!_endsWithSpaceAtCaret(tr)) return tr;
  final space = tr.newSelection.main.head;
  final line = tr.newDoc.lineAt(space);
  final before = dayWordsBefore(line.text, space - 1 - line.from);
  if (before == null) return tr;
  final day = dayOfWords(before.words, today);
  // Already a day as written, or no day at all: as typed.
  if (day == null || before.words == day) return tr;
  final from = line.from + before.from;
  final after = tr.state;
  if (_quietAt(after, from)) return tr;
  final written = ChangeSet.of(ChangeSpec(from: from + 1, to: space - 1, insert: day), after.doc.length);
  return TransactionSpec(
    changes: tr.changes.compose(written),
    selection: EditorSelection.single(from + 1 + day.length + 1),
    effects: <StateEffect<Object?>>[closeMentionAsk.of(true)],
    userEvent: 'input.complete',
    annotations: isolateHistory.of('full'),
    scrollIntoView: true,
  );
}

// ---- the chips ----------------------------------------------------------------------------------------------------

/// `padding: 0 0.3em` of a chip at `font-size: 0.92em`, in the line's own ems, as a tag's (tags.dart).
const double _pad = 0.3 * 0.92;
final Decoration _padBefore = Decoration.widget(widget: const GapWidget(em: _pad), side: -1);
final Decoration _padAfter = Decoration.widget(widget: const GapWidget(em: _pad), side: 1);

final Map<String, Decoration> _people = {for (final hue in workspaceHues) hue: Decoration.mark(className: 'cm-mention', attributes: <String, String>{'data-hue': hue})};
final Decoration _day = Decoration.mark(className: 'cm-mention cm-mentionDay');
final Decoration _pastDay = Decoration.mark(className: 'cm-mention cm-mentionDay', attributes: const <String, String>{'data-past': ''});

/// The mentions on each line, kept for every line of a document: the lines on screen are not read again on every
/// letter.
final LineFact<List<Mention>> _mentioned = LineFact<List<Mention>>((text) {
  if (!text.contains('@')) return null;
  final found = mentionsIn(text);
  return found.isEmpty ? null : found;
});

DecorationSet _decorate(EditorViewLike view) {
  final state = view.state;
  final hooks = state.facet(_hooks);
  final today = hooks?.today?.call() ?? DateTime.now();
  final found = <Range<Decoration>>[];
  final doc = state.doc;
  final tree = syntaxTree(state);
  final front = frontMatter(doc);
  for (final range in view.visibleRanges) {
    for (final line in _mentioned.between(doc, doc.lineAt(range.from).number, doc.lineAt(range.to).number)) {
      if (front != null && line.number >= front.from && line.number <= front.to) continue;
      final item = listLead(line.text) != null;
      for (final mention in line.fact) {
        final from = line.from + mention.from, to = line.from + mention.to;
        if (inQuietText(tree, from)) continue;
        final Decoration mark;
        if (mention.person) {
          // A list item's person is its assignee, and wears the field's chip.
          if (item) continue;
          final hue = hooks?.hue?.call(mention.value);
          mark = _people[hue != null && workspaceHues.contains(hue) ? hue : 'ink']!;
        } else {
          final day = mention.dayOn(today);
          mark = day != null && dayPast(day, today) ? _pastDay : _day;
        }
        found
          ..add(_padBefore.range(from))
          ..add(mark.range(from, to))
          ..add(_padAfter.range(to));
      }
    }
  }
  return Decoration.set(found, true);
}

/// The chip's ground: [color], a share of it.
void Function(Props p, LookEnv e) _ground(Color Function(LookEnv e) color, double share) =>
    (p, e) => p.painter = MarkPaint.add(p.painter, BoxLayer(color: inkShare(color(e), share), radius: p.em(0.35), padStart: p.em(0.3), padEnd: p.em(0.3)));

Color _hueInk(LookEnv e, String hue) => hue == 'ink' ? e.t.color('app-ink-2') : hued(e.t, hue).color('app-space');

final LookSheet _theme = LookSheet('editor/mentions', <LookRule>[
  // A person: their hue's ink, on a tenth of it; the quiet ink where they wear none.
  for (final hue in workspaceHues)
    LookRule(
      'cm-mention',
      classes: 2,
      when: (element, context) => !element.has('cm-mentionDay') && (element.attrs['data-hue'] ?? 'ink') == hue,
      (p, e) {
        p
          ..color = _hueInk(e, hue)
          ..sizeEm(0.92);
      },
      box: _ground((e) => _hueInk(e, hue), hue == 'ink' ? 0.09 : 0.14),
    ),
  // A day: the second ink; red once it has passed.
  LookRule(
    'cm-mentionDay',
    classes: 3,
    when: (element, context) => !element.attrs.containsKey('data-past'),
    (p, e) {
      p
        ..color = e.t.color('app-ink-2')
        ..sizeEm(0.92);
    },
    box: _ground((e) => e.t.color('app-ink-2'), 0.09),
  ),
  LookRule(
    'cm-mentionDay',
    classes: 3,
    when: (element, context) => element.attrs.containsKey('data-past'),
    (p, e) {
      p
        ..color = e.t.color('glacier-red-11')
        ..sizeEm(0.92);
    },
    box: _ground((e) => e.t.color('glacier-red-11'), 0.12),
  ),
]);

class _Chips extends PluginValue {
  _Chips(EditorViewLike view) : decorations = _decorate(view);

  DecorationSet decorations;

  @override
  void update(ViewUpdate update) {
    final refreshed = update.transactions.any((tr) => tr.effects.any((effect) => effect.isOf(refreshMentions)));
    if (refreshed || update.docChanged || update.viewportChanged || !identical(syntaxTree(update.startState), syntaxTree(update.state))) decorations = _decorate(update.view);
  }
}

final ViewPlugin<_Chips> _chips = ViewPlugin.define<_Chips>(_Chips.new, decorations: (value) => value.decorations);

/// Whether the list may take a key now: a question is asked, somewhere a mention can be.
bool _listKey(StateCommandTarget target, String key) {
  final ask = target.state.field(mentionAsk);
  final picking = target.state.facet(_hooks)?.picking;
  if (ask == null || picking == null || _quietAt(target.state, ask.from)) return false;
  return picking.key(key, target);
}

/// Mentions in a note: their chips, a day typed as words written as the day, and the at sign's question for
/// [hooks]' picker.
Extension mentions(MentionHooks hooks) {
  DateTime today() => hooks.today?.call() ?? DateTime.now();
  return Extension.list(<Extension>[
    _hooks.of(hooks),
    mentionAsk,
    _chips,
    EditorState.transactionFilter.of((tr) => dayOnSpace(tr, today())),
    EditorViewLike.updateListener.of((update) {
      final picking = hooks.picking;
      if (picking == null) return;
      final was = update.startState.field(mentionAsk), now = update.state.field(mentionAsk);
      if (was == now) return;
      picking.asked(update.view, now == null || _quietAt(update.state, now.from) ? null : now);
    }),
    Prec.highest(editorKeymap.of(<KeyBinding>[
      for (final key in const ['ArrowDown', 'ArrowUp', 'Enter', 'Tab', 'Escape']) KeyBinding(key: key, run: (target) => _listKey(target, key)),
    ])),
    baseTheme(_theme),
  ]);
}
