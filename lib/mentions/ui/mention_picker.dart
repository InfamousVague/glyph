/// The at sign's picker (Matt, 2026-10-30: "add all 12", @mentions): typing `@` in a note lists who can be named
/// and the days a word could mean, under the caret, and narrows as more is typed. A tap or Enter writes the one
/// chosen, `@sam ` or `@2026-11-06 `; Escape, or a space after a name, leaves the words as typed.
///
/// - **People**: in a team's note, the organization's members in the colours they wear there, and you; in a note of
///   your own, you alone, since nobody else has it. A name typed that is nobody's is not offered, and stays words.
/// - **Days**: Today and Tomorrow while nothing is typed, then whatever the words name ("next friday", "nov 6",
///   "in 3 days": lib/mentions/mention_syntax.dart `dayOfWords`), with the day it is beside it.
///
/// The editor's half is lib/editor/items/mentions.dart: it says what is asked ([MentionPicker.asked]) and hands over
/// the list's keys ([MentionPicker.key]); [MentionLayer] is what a note's screen puts round its page for the list.
library;

import 'package:flutter/rendering.dart' show RenderStack;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../comments/ui/card.dart' show hued;
import '../../core/days.dart' show isoDay, isoDayAfter;
import '../../editor/editor.dart';
import '../../editor/items/mentions.dart';
import '../../sheet/css.dart';
import '../mention_syntax.dart';

/// One person who can be named: their handle, and the hue they wear in the note's organization (null for none).
typedef MentionPerson = ({String handle, String? hue});

/// One row of the list.
class MentionChoice {
  const MentionChoice.person(this.value, {this.hue, this.you = false})
      : day = false,
        label = value;
  const MentionChoice.day(this.value, {required this.label})
      : day = true,
        hue = null,
        you = false;

  /// What is written after the at sign.
  final String value;
  final bool day;
  final String? hue;
  final bool you;

  /// A day's own word for itself ("Today", "Next friday"); a person's handle.
  final String label;

  @override
  bool operator ==(Object other) => other is MentionChoice && other.value == value && other.day == day;

  @override
  int get hashCode => Object.hash(value, day);

  @override
  String toString() => day ? 'day $value' : 'person $value';
}

MentionChoice _day(String iso, String label) => MentionChoice.day(iso, label: label);

/// The most rows the list shows.
const int mostChoices = 8;

/// The rows for [query]: the people whose handle starts with it (then those whose handle has it), you among them,
/// then the days it could mean.
List<MentionChoice> mentionChoices(String query, {required List<MentionPerson> people, String? me, required DateTime today}) {
  final asked = query.trim().toLowerCase();
  final seen = <String>{};
  final everyone = <MentionPerson>[
    if (me != null && me.isNotEmpty) (handle: me, hue: people.where((p) => handleKey(p.handle) == handleKey(me)).firstOrNull?.hue),
    ...people,
  ];
  final first = <MentionChoice>[], later = <MentionChoice>[];
  for (final person in everyone) {
    final key = handleKey(person.handle);
    if (!seen.add(key)) continue;
    final you = me != null && key == handleKey(me);
    final choice = MentionChoice.person(person.handle, hue: person.hue, you: you);
    if (asked.isEmpty || key.startsWith(asked)) {
      first.add(choice);
    } else if (key.contains(asked)) {
      later.add(choice);
    }
  }
  final days = <MentionChoice>[];
  final now = isoDay(today);
  void offer(String? iso, String label) {
    if (iso == null || days.any((d) => d.value == iso)) return;
    days.add(_day(iso, label));
  }

  if (asked.isEmpty) {
    offer(now, 'Today');
    offer(isoDayAfter(now, 1), 'Tomorrow');
  } else {
    for (final (word, label) in const [('today', 'Today'), ('tomorrow', 'Tomorrow'), ('next week', 'Next week')]) {
      if (word.startsWith(asked)) offer(dayOfWords(word, today), label);
    }
    final named = dayOfWords(asked, today);
    if (named != null) offer(named, _capital(asked));
  }
  return [...first, ...later, ...days].take(mostChoices).toList();
}

String _capital(String words) => words.isEmpty ? words : '${words[0].toUpperCase()}${words.substring(1)}';

/// The picker: what is asked, the rows that answer it, and which one Enter takes.
class MentionPicker extends ChangeNotifier implements MentionPicking {
  MentionPicker({required this.people, required this.me, DateTime Function()? today, this.owner}) : _today = today ?? DateTime.now;

  /// Who can be named in this note now (see the header), asked as the list is drawn.
  List<MentionPerson> Function() people;
  String? Function() me;
  final DateTime Function() _today;

  /// The handle a picked day is signed with, `@matt @2026-11-06` (lib/editor/items/mentions.dart `MentionHooks.owner`):
  /// the person's own in a team's note; null, or absent, in a note of their own.
  String? Function()? owner;

  /// What a pick writes: a day signed in a team's note, unless the line already names its person before the at sign.
  TransactionSpec _written(EditorState state, MentionAsk ask, String value) {
    final line = state.doc.lineAt(ask.from);
    return mentionWritten(ask, value, owner: owner?.call(), before: line.text.substring(0, ask.from - line.from));
  }

  EditorViewLike? _view;
  MentionAsk? _ask;
  int _index = 0;
  List<MentionChoice> _choices = const [];

  MentionAsk? get ask => _ask;
  EditorViewLike? get view => _view;
  List<MentionChoice> get choices => _choices;
  int get index => _index;
  DateTime get today => _today();

  @override
  void asked(EditorViewLike view, MentionAsk? ask) {
    _view = view;
    final was = _ask;
    _ask = ask;
    _choices = ask == null ? const [] : mentionChoices(ask.query, people: people(), me: me(), today: _today());
    if (ask == null || was?.from != ask.from || was?.query != ask.query) _index = 0;
    if (_index >= _choices.length) _index = 0;
    notifyListeners();
  }

  /// Whether the list is up: something asked, and something to offer.
  bool get open => _ask != null && _choices.isNotEmpty;

  @override
  bool key(String key, StateCommandTarget target) {
    final ask = _ask;
    if (ask == null) return false;
    if (key == 'Escape') {
      target.dispatch(target.state.update(TransactionSpec(effects: <StateEffect<Object?>>[closeMentionAsk.of(true)])));
      return true;
    }
    if (!open) return false;
    switch (key) {
      case 'ArrowDown':
        _index = (_index + 1) % _choices.length;
        notifyListeners();
        return true;
      case 'ArrowUp':
        _index = (_index - 1 + _choices.length) % _choices.length;
        notifyListeners();
        return true;
      case 'Enter' || 'Tab':
        target.dispatch(target.state.update(_written(target.state, ask, _choices[_index].value)));
        return true;
    }
    return false;
  }

  /// A row tapped: its words written, and the note has the focus back.
  void pick(MentionChoice choice) {
    final view = _view, ask = _ask;
    if (view == null || ask == null) return;
    view.dispatch(_written(view.state, ask, choice.value));
    view.focus();
  }

  /// Closed from outside: the note left, say.
  void close() {
    final view = _view;
    if (_ask == null || view == null) return;
    view.dispatch(TransactionSpec(effects: <StateEffect<Object?>>[closeMentionAsk.of(true)]));
  }
}

/// What a note's screen puts round its page: the page, and the list under the caret while one is asked.
class MentionLayer extends StatelessWidget {
  const MentionLayer({super.key, required this.picker, required this.child});

  final MentionPicker picker;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: picker,
      child: child,
      builder: (context, child) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child!,
            if (picker.open) _Placed(picker: picker),
          ],
        );
      },
    );
  }
}

/// The list, placed under the at sign, or over it where the room under it is short.
class _Placed extends StatefulWidget {
  const _Placed({required this.picker});
  final MentionPicker picker;

  @override
  State<_Placed> createState() => _PlacedState();
}

class _PlacedState extends State<_Placed> {
  /// The question last placed again after a frame, so a caret not laid out yet is waited for once, not forever.
  MentionAsk? _waited;

  /// Placed again once the frame is done: the editor lays out the line just typed in the frame this is built in.
  void _again(MentionAsk? ask) {
    if (ask == null || _waited == ask) return;
    _waited = ask;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  MentionPicker get picker => widget.picker;

  @override
  Widget build(BuildContext context) {
    // Over the whole page, and holding nothing but the list: a press anywhere else is the page's.
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layer = context.findAncestorRenderObjectOfType<RenderStack>();
          final ask = picker.ask, view = picker.view;
          final rect = ask == null || view == null ? null : view.coordsAtPos(ask.from);
          if (rect == null || layer == null || !layer.hasSize) {
            _again(ask);
            return const SizedBox.shrink();
          }
          final at = layer.globalToLocal(rect.bottomLeft);
          final top = layer.globalToLocal(rect.topLeft).dy;
          final size = constraints.biggest;
          const width = 260.0;
          final t = context.tokens;
          final height = picker.choices.length * t.space(10) + 2 * t.space(1);
          final room = size.height - at.dy;
          final above = room < height + 8 && top > height + 8;
          final most = size.width - width - t.space(2);
          final left = most < t.space(2) ? t.space(2) : at.dx.clamp(t.space(2), most).toDouble();
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(left: left, top: above ? top - height - 4 : at.dy + 4, width: width, child: MentionList(picker: picker)),
            ],
          );
        },
      ),
    );
  }
}

/// The rows, as a card: who first, then the days.
class MentionList extends StatelessWidget {
  const MentionList({super.key, required this.picker});
  final MentionPicker picker;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      container: true,
      label: 'Mention someone or a day',
      child: DecoratedBox(
        key: const ValueKey('mention-picker'),
        decoration: BoxDecoration(
          color: t.color('app-paper'),
          borderRadius: BorderRadius.circular(t.radius('md')),
          border: Border.all(color: t.color('app-rule'), width: snapBorder(context, t.len('glacier-hairline'))),
          boxShadow: const [BoxShadow(color: Color(0x24000000), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: t.space(1)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, choice) in picker.choices.indexed) _Row(choice: choice, lit: i == picker.index, today: picker.today, onPick: () => picker.pick(choice)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.choice, required this.lit, required this.today, required this.onPick});
  final MentionChoice choice;
  final bool lit;
  final DateTime today;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final hue = choice.hue ?? 'ink';
    final ink = hue == 'ink' ? t.color('app-ink-2') : hued(t, hue).color('app-space');
    final Widget mark = choice.day
        ? SizedBox(width: 22, height: 22, child: Center(child: AppIcon(Lucide.calendarDays, size: 16, strokeWidth: 2, color: t.color('app-ink-2'))))
        : Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: inkShareOf(ink, 0.16)),
            child: Text(choice.value.isEmpty ? '' : choice.value.substring(0, 1).toUpperCase(), style: pageText(t, 0.85 * sm, weight: 'semibold', color: ink)),
          );
    final hint = choice.day ? dayShown(choice.value, today) == choice.label ? choice.value : dayShown(choice.value, today) : (choice.you ? 'you' : null);
    return GlacierPressable(
      key: ValueKey('mention-${choice.day ? 'day' : 'person'}-${choice.value}'),
      onPressed: onPick,
      semanticLabel: choice.day ? '${choice.label}, ${choice.value}' : (choice.you ? '${choice.value}, you' : choice.value),
      builder: (context, state) => Container(
        height: t.space(10),
        padding: EdgeInsets.symmetric(horizontal: t.space(3)),
        color: lit || state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 7%, transparent)') : null,
        child: Row(
          spacing: t.space(2),
          children: [
            mark,
            Expanded(child: Text(choice.day ? choice.label : '@${choice.value}', maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, sm, weight: 'medium', color: choice.day ? t.color('app-ink') : ink))),
            if (hint != null) Text(hint, maxLines: 1, style: pageText(t, 0.9 * sm, color: t.color('app-ink-3'))),
          ],
        ),
      ),
    );
  }
}

/// [color] at [share] of its strength.
Color inkShareOf(Color color, double share) => color.withValues(alpha: color.a * share);
