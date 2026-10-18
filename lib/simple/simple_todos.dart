/// The To-dos view of simple mode (GHST-105): a tab beside Notes that lists every open to-do across the notes, in
/// Todoist's buckets - Overdue, Today, Later, Someday - with a Done shelf at the foot. Matt asked for the simple
/// mode to be built by "looking into simple apps like todoist and others to build out a clean simple UI"; what the
/// simple apps share is one list, a round tick on the left, the words, and a quiet line under them saying where and
/// when. Nothing else: no projects, no labels, no filters. The notes are the projects here, and a to-do is still a
/// line of Markdown in one of them.
///
/// The view writes nothing. A tick calls [SimpleTodos.onTick], and the root rewrites the note the way a query's
/// list does (lib/core/query/tick.dart `tickedBody`, then `_writeNote`); a tap on the words calls
/// [SimpleTodos.onOpen], and the root opens the note at that line. The notes arrive through a listenable, the root's
/// own list of the notes it shows (out of the trash); the groups are read again only when that list is another
/// object or the day has turned, never on every build.
///
/// A ticked row stays where it is, ticked, for a beat (`_beat`) before the list closes over it and it moves to Done:
/// the person sees what they did. The Done shelf holds what was ticked in this view this session; no tick writes a
/// ✅ date, so there is nothing in the notes to read "done today" from, and a shelf that forgets on leaving is
/// honest about that. A tap on a done row's tick clears the box again.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app/widgets.dart' show AppEyebrow;
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../core/days.dart';
import '../core/note.dart';
import '../core/trash.dart';
import '../home/home_text.dart' show pageText, tabular;
import 'todos_groups.dart';

/// How long a ticked row stays, ticked, before it leaves the open groups.
const Duration _beat = Duration(milliseconds: 450);

/// The widest the list is drawn: on the Fold open and the desktop a to-do's words have no business reaching across
/// the whole window (Matt, on wide layouts: "two cards across is fine", but a list is read down, not across).
const double _measure = 640;

class SimpleTodos extends StatefulWidget {
  const SimpleTodos({super.key, required this.notes, required this.clock, required this.onTick, required this.onOpen, this.onAdd, this.trash});

  /// The notes the app shows: the root's own list, which stays the same object while nothing in it changed.
  final ValueListenable<List<Note>> notes;

  /// The moment it is now; a test's clock stands still.
  final DateTime Function() clock;

  /// A to-do's box turned: [done] true from an open row, false from the Done shelf. The root writes the note.
  final void Function(String noteId, int line, bool done) onTick;

  /// The words tapped: the root opens the note at the line.
  final void Function(String noteId, int line) onOpen;

  /// Where the root offers a way to write a new to-do, the empty state's hint becomes a way in; otherwise it is
  /// words alone.
  final VoidCallback? onAdd;

  /// The trash, where the notes given are the whole library rather than the shown ones; a note in it is left out.
  final ValueListenable<TrashHeld>? trash;

  @override
  State<SimpleTodos> createState() => _SimpleTodosState();
}

class _SimpleTodosState extends State<SimpleTodos> {
  // The groups, and what they were read from: the notes list by identity, the trash's map by identity, and the day.
  TodoGroups? _groups;
  List<Note>? _readFrom;
  TrashHeld? _readLess;
  String? _readDay;

  // The rows ticked this session, newest first, and their keys; a tap on the shelf's tick takes one back out.
  final List<Todo> _done = [];
  final Set<String> _doneKeys = {};

  // While a tick's beat runs: the groups as they stood when the box was tapped, so the row stays put, and the keys
  // drawn ticked in them. A second tap within the beat joins it and starts the beat again.
  TodoGroups? _held;
  final Set<String> _ticking = {};
  Timer? _beatTimer;
  bool _doneOpen = false;

  @override
  void initState() {
    super.initState();
    widget.notes.addListener(_changed);
    widget.trash?.addListener(_changed);
  }

  @override
  void didUpdateWidget(SimpleTodos old) {
    super.didUpdateWidget(old);
    if (old.notes != widget.notes) {
      old.notes.removeListener(_changed);
      widget.notes.addListener(_changed);
    }
    if (old.trash != widget.trash) {
      old.trash?.removeListener(_changed);
      widget.trash?.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _beatTimer?.cancel();
    widget.notes.removeListener(_changed);
    widget.trash?.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  /// The groups for the notes as they are now, read again only when something they were read from is new.
  TodoGroups _current() {
    final notes = widget.notes.value;
    final held = widget.trash?.value ?? const <String, int>{};
    final day = isoDay(widget.clock());
    if (_groups == null || !identical(notes, _readFrom) || !identical(held, _readLess) || day != _readDay) {
      _groups = todoGroups(notes, day, held: held);
      _readFrom = notes;
      _readLess = held;
      _readDay = day;
      // A to-do written open again - its box cleared in the editor - leaves the shelf, so it is never listed twice.
      final open = {for (final group in _groups!) for (final todo in group.todos) todo.key};
      _done.removeWhere((todo) => open.contains(todo.key));
      _doneKeys.removeWhere(open.contains);
    }
    return _groups!;
  }

  void _tick(Todo todo) {
    haptic(HapticKind.selection);
    widget.onTick(todo.noteId, todo.line, true);
    setState(() {
      _held ??= _current();
      _ticking.add(todo.key);
    });
    _beatTimer?.cancel();
    // Under reduced motion the beat is still a pause, not a movement: the row leaving at once would be the jump.
    _beatTimer = Timer(_beat, _afterBeat);
  }

  void _afterBeat() {
    if (!mounted) return;
    setState(() {
      final held = _held;
      if (held != null) {
        for (final group in held) {
          for (final todo in group.todos) {
            if (_ticking.contains(todo.key) && !_doneKeys.contains(todo.key)) {
              _done.insert(0, todo);
              _doneKeys.add(todo.key);
            }
          }
        }
      }
      _held = null;
      _ticking.clear();
    });
  }

  void _untick(Todo todo) {
    haptic(HapticKind.selection);
    widget.onTick(todo.noteId, todo.line, false);
    setState(() {
      _done.removeWhere((each) => each.key == todo.key);
      _doneKeys.remove(todo.key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final groups = _held ?? _current();
    final today = isoDay(widget.clock());
    // Done rows are never in the open groups, except in the beat, where the ticked row is still drawn in place.
    final open = [
      for (final group in groups)
        (group: group.group, todos: [for (final todo in group.todos) if (!_doneKeys.contains(todo.key)) todo]),
    ].where((group) => group.todos.isNotEmpty).toList();
    final gutterStart = t.len('app-gutter-start'), gutterEnd = t.len('app-gutter-end');
    final count = open.fold(0, (n, group) => n + group.todos.length);

    if (open.isEmpty && _done.isEmpty) {
      return _Empty(onAdd: widget.onAdd);
    }

    final children = <Widget>[
      for (final group in open) ...[
        _GroupHeading(words: todoGroupWords[group.group]!, count: group.todos.length, key: ValueKey('todos-${group.group.name}')),
        for (final todo in group.todos)
          _TodoRow(
            key: ValueKey('todo-${todo.key}'),
            todo: todo,
            today: today,
            ticked: _ticking.contains(todo.key),
            overdue: group.group == TodoGroup.overdue,
            onTick: () => _tick(todo),
            onOpen: () => widget.onOpen(todo.noteId, todo.line),
          ),
        SizedBox(height: t.space(4)),
      ],
      if (_done.isNotEmpty) ...[
        _DoneHeading(count: _done.length, open: _doneOpen, onToggle: () => setState(() => _doneOpen = !_doneOpen)),
        if (_doneOpen)
          for (final todo in _done)
            _TodoRow(key: ValueKey('done-${todo.key}'), todo: todo, today: today, ticked: true, overdue: false, onTick: () => _untick(todo), onOpen: () => widget.onOpen(todo.noteId, todo.line)),
      ],
    ];

    return Semantics(
      label: count == 1 ? 'To-dos, 1 open' : 'To-dos, $count open',
      container: true,
      // Laid out whole, not a scroller of its own: the page it sits in (lib/simple/simple_home.dart) is the one
      // that scrolls, header and all, as the Notes list does; a scroller inside a scroller has no height to take.
      child: ListView(
        shrinkWrap: true,
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        // The page pads the gutters; this pads only the top and the foot.
        padding: EdgeInsets.fromLTRB(0, t.space(4), 0, t.space(16)),
        children: [
          for (final child in children) Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: _measure), child: child)),
        ],
      ),
    );
  }
}

/// A group's heading: an eyebrow and how many are in it, as the home page heads its sections.
class _GroupHeading extends StatelessWidget {
  const _GroupHeading({super.key, required this.words, required this.count});
  final String words;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      header: true,
      label: '$words, $count',
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(t.space(1), t.space(2), t.space(1), t.space(1)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            AppEyebrow(words),
            SizedBox(width: t.space(2)),
            Text('$count', style: tabular(pageText(t, t.fontSize('xs'), color: t.color('app-ink-3')))),
          ],
        ),
      ),
    );
  }
}

/// The Done shelf's heading: collapsed, it is a line to open; a chevron says which way it is.
class _DoneHeading extends StatelessWidget {
  const _DoneHeading({required this.count, required this.open, required this.onToggle});
  final int count;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink3 = t.color('app-ink-3');
    return GlacierPressable(
      onPressed: onToggle,
      semanticLabel: open ? 'Done, $count, hide' : 'Done, $count, show',
      toggled: open,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('sm'),
        child: Padding(
          padding: EdgeInsets.fromLTRB(t.space(1), t.space(2), t.space(1), t.space(1)),
          child: ExcludeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppEyebrow('Done'),
                SizedBox(width: t.space(2)),
                Text('$count', style: tabular(pageText(t, t.fontSize('xs'), color: ink3))),
                SizedBox(width: t.space(1)),
                AppIcon(open ? Lucide.chevronUp : Lucide.chevronDown, size: t.fontSize('sm'), color: ink3, wash: false),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One to-do: the round tick on the left, the words, and under them the note's name, the due day and a priority
/// worth a word. The tick and the words are two targets, as every simple app has them: the tick for doing, the
/// words for going to where it was written.
class _TodoRow extends StatelessWidget {
  const _TodoRow({super.key, required this.todo, required this.today, required this.ticked, required this.overdue, required this.onTick, required this.onOpen});
  final Todo todo;
  final String today;
  final bool ticked;
  final bool overdue;
  final VoidCallback onTick;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final md = t.fontSize('md'), sm = t.fontSize('sm');
    final ink = t.color('app-ink'), ink3 = t.color('app-ink-3');
    // The kit's danger tokens are the ink in this app's monochrome sheet; a red that is red is the red scale's own,
    // as the swipe rows and the field picker draw theirs (red-11 for words, red-9 for a solid).
    final danger = t.color('glacier-red-11');
    final due = todo.due == null ? null : dueWords(todo.due!, today);
    final priority = priorityWords(todo.priority);
    final meta = [todo.noteName, ?due, ?priority];
    final said = [todo.text, ...meta, if (ticked) 'done' else if (overdue) 'overdue'].join(', ');

    return Semantics(
      container: true,
      child: Container(
        constraints: BoxConstraints(minHeight: t.space(12)),
        padding: EdgeInsets.symmetric(vertical: t.space(1)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Tick(ticked: ticked, overdue: overdue && !ticked, onPressed: onTick, label: ticked ? 'Clear ${todo.text}' : 'Tick ${todo.text}'),
            Expanded(
              child: GlacierPressable(
                onPressed: onOpen,
                semanticLabel: '$said. Opens the note',
                builder: (context, state) => GlacierFocusRing(
                  visible: state.focused,
                  radius: t.radius('sm'),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(2)),
                    // `.row:hover`'s wash of the ink, as the home rows have it.
                    color: state.hovered ? t.colorOf('color-mix(in oklch, var(--app-ink) 4%, transparent)') : null,
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            todo.text,
                            style: pageText(t, md, color: ticked ? ink3 : ink).copyWith(decoration: ticked ? TextDecoration.lineThrough : null, decorationColor: ink3),
                          ),
                          const SizedBox(height: 2),
                          Text.rich(
                            TextSpan(
                              style: pageText(t, sm, color: ink3),
                              children: [
                                TextSpan(text: todo.noteName),
                                if (due != null) ...[
                                  const TextSpan(text: ' · '),
                                  // An overdue day is said in the danger ink, as its ring is; once ticked it is history.
                                  TextSpan(text: due, style: overdue && !ticked ? TextStyle(color: danger) : null),
                                ],
                                if (priority != null) TextSpan(text: ' · $priority'),
                              ],
                            ),
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The round tick target: an empty ring, red when the to-do is overdue, a filled disc with a check once ticked.
/// The ring is 22px and the target is 44px, a finger's width, so the words beside it keep their own target.
class _Tick extends StatelessWidget {
  const _Tick({required this.ticked, required this.overdue, required this.onPressed, required this.label});
  final bool ticked;
  final bool overdue;
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-ink'), ink3 = t.color('app-ink-3');
    final ring = overdue ? t.color('glacier-red-9') : ink3;
    final paper = t.color('app-paper');
    const size = 22.0;
    // 44 is a finger's width (iOS's own minimum), not one of the kit's steps.
    const target = 44.0;
    return GlacierPressable(
      onPressed: onPressed,
      semanticLabel: label,
      haptic: HapticKind.selection,
      toggled: ticked,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: target / 2,
        child: SizedBox(
          width: target,
          height: target,
          child: Center(
            child: AnimatedContainer(
              // The disc fills in a short cross-fade; none under reduced motion.
              duration: t.reducedMotion ? Duration.zero : const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ticked ? ink : (state.hovered || state.pressed ? ring.withValues(alpha: ring.a * 0.12) : null),
                border: Border.all(color: ticked ? ink : ring, width: overdue ? 2 : 1.5),
              ),
              child: ticked ? Center(child: AppIcon(Lucide.check, size: 14, color: paper, strokeWidth: 3, wash: false)) : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Nothing to do: the words, and how a to-do is made, since in this app one is a line in a note rather than a
/// form of its own.
class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final md = t.fontSize('md'), sm = t.fontSize('sm');
    final ink2 = t.color('app-ink-2'), ink3 = t.color('app-ink-3');
    final hint = Text.rich(
      TextSpan(
        style: pageText(t, sm, color: ink3),
        children: [
          const TextSpan(text: 'Start a line with '),
          TextSpan(text: '- [ ] ', style: t.textAt(sm, mono: true, color: ink2)),
          const TextSpan(text: 'to make one.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: t.len('app-gutter-start')),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(Lucide.listTodo, size: 28, color: ink3, wash: false),
              SizedBox(height: t.space(3)),
              Text('Nothing to do.', style: pageText(t, md, weight: 'semibold', color: ink2), textAlign: TextAlign.center),
              SizedBox(height: t.space(1)),
              Text('To-dos you write in any note show here.', style: pageText(t, sm, color: ink3), textAlign: TextAlign.center),
              SizedBox(height: t.space(3)),
              if (onAdd == null)
                hint
              else
                GlacierPressable(
                  onPressed: onAdd!,
                  semanticLabel: 'Write a to-do',
                  builder: (context, state) => GlacierFocusRing(visible: state.focused, radius: t.radius('sm'), child: Padding(padding: EdgeInsets.all(t.space(1)), child: hint)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
