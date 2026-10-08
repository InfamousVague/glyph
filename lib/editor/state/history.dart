/// Undo and redo: CodeMirror's history (@codemirror/commands, history.ts), ported line for line: `history()`,
/// `undo`, `redo`, `undoSelection`, `redoSelection`, `undoDepth`, `redoDepth`, `isolateHistory`, `invertedEffects`,
/// `historyField`.
///
/// Typing joins into one undo step while the changes touch and come less than `newGroupDelay` apart; a change marked
/// `addToHistory: false` (a sync from another device) is not a step, and the steps under it are moved so they still
/// undo the right text; undoing restores the selection as it was before the step.
///
/// What is not here: the `beforeinput` handler CodeMirror's `history()` carries (a browser's own undo menu) and
/// `historyKeymap`; keys are the input piece's (`lib/editor/input/`). The configuration is a class,
/// [HistoryConfig], not an object literal.
library;

import 'change.dart';
import 'selection.dart';
import 'state.dart';

// BranchName
const int _done = 0, _undone = 1;

typedef _FromHistory = ({int side, List<HistEvent> rest, EditorSelection selection});

final AnnotationType<_FromHistory> _fromHistory = Annotation.define<_FromHistory>();

/// CodeMirror's `isolateHistory`: `"before"` keeps a transaction from joining the step before it, `"after"` keeps
/// the next from joining it, `"full"` both.
final AnnotationType<String> isolateHistory = Annotation.define<String>();

/// CodeMirror's `invertedEffects`: each function is asked, for a transaction, which effects would undo its effects;
/// history keeps them with the step and applies them on undo.
final Facet<List<StateEffect<Object?>> Function(Transaction tr), List<List<StateEffect<Object?>> Function(Transaction tr)>> invertedEffects =
    Facet.define();

/// The options of [history].
class HistoryConfig {
  const HistoryConfig({this.minDepth, this.newGroupDelay, this.joinToEvent});

  /// How many steps are kept at least; 100 when nothing says. The largest given wins.
  final int? minDepth;

  /// How many milliseconds may pass between two changes that join into one step; 500 when nothing says. The
  /// smallest given wins.
  final int? newGroupDelay;

  /// Whether a change joins the step before it; by default when the two touch. Given twice, either saying yes
  /// joins.
  final bool Function(Transaction tr, bool isAdjacent)? joinToEvent;
}

class _ResolvedConfig {
  _ResolvedConfig(this.minDepth, this.newGroupDelay, this.joinToEvent);

  final int minDepth;
  final int newGroupDelay;
  final bool Function(Transaction tr, bool isAdjacent) joinToEvent;
}

bool _joinAdjacent(Transaction tr, bool isAdjacent) => isAdjacent;

final Facet<HistoryConfig, _ResolvedConfig> _historyConfig = Facet.define<HistoryConfig, _ResolvedConfig>(
  // CodeMirror's `combineConfig` with max, min and "either" for the three keys.
  combine: (configs) {
    int? minDepth, newGroupDelay;
    bool Function(Transaction tr, bool isAdjacent)? joinToEvent;
    for (final config in configs) {
      final depth = config.minDepth, delay = config.newGroupDelay, join = config.joinToEvent;
      if (depth != null) minDepth = minDepth == null || depth > minDepth ? depth : minDepth;
      if (delay != null) newGroupDelay = newGroupDelay == null || delay < newGroupDelay ? delay : newGroupDelay;
      if (join != null) {
        final a = joinToEvent;
        joinToEvent = a == null || identical(a, join) ? join : (tr, adj) => a(tr, adj) || join(tr, adj);
      }
    }
    return _ResolvedConfig(minDepth ?? 100, newGroupDelay ?? 500, joinToEvent ?? _joinAdjacent);
  },
);

/// CodeMirror's `historyField`: the field that holds the history. `state.fieldOrNull(historyField)` is null for a
/// state without [history].
final StateField<HistoryState> historyField = StateField.define<HistoryState>(
  create: (_) => HistoryState.empty,
  update: (state, tr) {
    final config = tr.state.facet(_historyConfig);
    final fromHist = tr.annotation(_fromHistory);
    if (fromHist != null) {
      final item = HistEvent._fromTransaction(tr, fromHist.selection), from = fromHist.side;
      var other = from == _done ? state.undone : state.done;
      if (item != null) {
        other = _updateBranch(other, other.length, config.minDepth, item);
      } else {
        other = _addSelectionToBranch(other, tr.startState.selection);
      }
      return HistoryState._(from == _done ? fromHist.rest : other, from == _done ? other : fromHist.rest);
    }
    final isolate = tr.annotation(isolateHistory);
    if (isolate == 'full' || isolate == 'before') state = state._isolate();
    if (tr.annotation(Transaction.addToHistory) == false) {
      return !tr.changes.empty ? state._addMapping(tr.changes.desc) : state;
    }
    final event = HistEvent._fromTransaction(tr);
    final time = tr.annotation(Transaction.time)!, userEvent = tr.annotation(Transaction.userEvent);
    if (event != null) {
      state = state._addChanges(event, time, userEvent, config, tr);
    } else if (tr.selection != null) {
      state = state._addSelection(tr.startState.selection, time, userEvent, config.newGroupDelay);
    }
    if (isolate == 'full' || isolate == 'after') state = state._isolate();
    return state;
  },
  toJson: (value, _) => <String, Object?>{
    'done': <Object?>[for (final e in value.done) e.toJson()],
    'undone': <Object?>[for (final e in value.undone) e.toJson()],
  },
  fromJson: (json, _) {
    final map = json as Map;
    return HistoryState._(
      <HistEvent>[for (final e in map['done'] as List) HistEvent.fromJson(e)],
      <HistEvent>[for (final e in map['undone'] as List) HistEvent.fromJson(e)],
    );
  },
);

/// CodeMirror's `history()`: the extension that keeps undo history.
Extension history([HistoryConfig config = const HistoryConfig()]) =>
    Extension.list(<Extension>[historyField, _historyConfig.of(config)]);

StateCommand _cmd(int side, bool selection) {
  return (StateCommandTarget target) {
    final state = target.state;
    if (!selection && state.readOnly) return false;
    final historyState = state.fieldOrNull(historyField);
    if (historyState == null) return false;
    final tr = historyState._pop(side, state, selection);
    if (tr == null) return false;
    target.dispatch(tr);
    return true;
  };
}

/// Undoes one step of changes. False when there is nothing to undo or the state is read-only.
final StateCommand undo = _cmd(_done, false);

/// Redoes one undone step.
final StateCommand redo = _cmd(_undone, false);

/// Undoes one change of selection, or a step of changes when there is none after the last step.
final StateCommand undoSelection = _cmd(_done, true);

/// Redoes one undone change of selection.
final StateCommand redoSelection = _cmd(_undone, true);

int Function(EditorState state) _depth(int side) {
  return (EditorState state) {
    final histState = state.fieldOrNull(historyField);
    if (histState == null) return 0;
    final branch = side == _done ? histState.done : histState.undone;
    return branch.length - (branch.isNotEmpty && branch[0].changes == null ? 1 : 0);
  };
}

/// How many steps can be undone.
final int Function(EditorState state) undoDepth = _depth(_done);

/// How many steps can be redone.
final int Function(EditorState state) redoDepth = _depth(_undone);

const List<StateEffect<Object?>> _noEffects = <StateEffect<Object?>>[];
const List<EditorSelection> _noSelections = <EditorSelection>[];
const List<HistEvent> _noEvents = <HistEvent>[];

/// CodeMirror's `HistEvent`, internal there: a group of changes and effects that are undone or redone together.
/// Public only because [HistoryState] shows its branches.
class HistEvent {
  HistEvent._(
    // The changes in this event. Normal events hold at least one change or effect. But it may be necessary to store
    // selection events before the first change, in which case a special type of instance is created which doesn't
    // hold any changes, with changes == startSelection == undefined
    this.changes,
    // The effects associated with this event
    this.effects,
    // Accumulated mapping (from addToHistory==false) that should be applied to events below this one.
    this.mapped,
    // The selection before this event
    this.startSelection,
    // Stores selection changes after this event, to be used for selection undo/redo.
    this.selectionsAfter,
  );

  final ChangeSet? changes;
  final List<StateEffect<Object?>> effects;
  final ChangeDesc? mapped;
  final EditorSelection? startSelection;
  final List<EditorSelection> selectionsAfter;

  HistEvent _setSelAfter(List<EditorSelection> after) => HistEvent._(changes, effects, mapped, startSelection, after);

  Map<String, Object?> toJson() => <String, Object?>{
    'changes': changes?.toJson(),
    'mapped': mapped?.toJson(),
    'startSelection': startSelection?.toJson(),
    'selectionsAfter': <Object?>[for (final s in selectionsAfter) s.toJson()],
  };

  static HistEvent fromJson(Object? json) {
    final map = json as Map;
    return HistEvent._(
      map['changes'] != null ? ChangeSet.fromJson(map['changes']) : null,
      _noEffects,
      map['mapped'] != null ? ChangeDesc.fromJson(map['mapped']) : null,
      map['startSelection'] != null ? EditorSelection.fromJson(map['startSelection']) : null,
      <EditorSelection>[for (final s in map['selectionsAfter'] as List) EditorSelection.fromJson(s)],
    );
  }

  // This does not check `addToHistory` and such, it assumes the transaction needs to be converted to an item.
  // Returns null when there are no changes or effects in the transaction.
  static HistEvent? _fromTransaction(Transaction tr, [EditorSelection? selection]) {
    var effects = _noEffects;
    for (final invert in tr.startState.facet(invertedEffects)) {
      final result = invert(tr);
      if (result.isNotEmpty) effects = <StateEffect<Object?>>[...effects, ...result];
    }
    if (effects.isEmpty && tr.changes.empty) return null;
    return HistEvent._(tr.changes.invert(tr.startState.doc), effects, null, selection ?? tr.startState.selection, _noSelections);
  }

  static HistEvent _selection(List<EditorSelection> selections) => HistEvent._(null, _noEffects, null, null, selections);
}

List<HistEvent> _updateBranch(List<HistEvent> branch, int to, int maxLen, HistEvent newEvent) {
  final start = to + 1 > maxLen + 20 ? to - maxLen - 1 : 0;
  return <HistEvent>[...branch.sublist(start, to), newEvent];
}

bool _isAdjacent(ChangeDesc a, ChangeDesc b) {
  final ranges = <int>[];
  var isAdjacent = false;
  a.iterChangedRanges((f, t, _, _) {
    ranges
      ..add(f)
      ..add(t);
  });
  b.iterChangedRanges((_, _, f, t) {
    for (var i = 0; i < ranges.length;) {
      final from = ranges[i++], to = ranges[i++];
      if (t >= from && f <= to) isAdjacent = true;
    }
  });
  return isAdjacent;
}

bool _eqSelectionShape(EditorSelection a, EditorSelection b) {
  if (a.ranges.length != b.ranges.length) return false;
  for (var i = 0; i < a.ranges.length; i++) {
    if (a.ranges[i].empty != b.ranges[i].empty) return false;
  }
  return true;
}

List<E> _conc<E>(List<E> a, List<E> b) => a.isEmpty
    ? b
    : b.isEmpty
    ? a
    : <E>[...a, ...b];

const int _maxSelectionsPerEvent = 200;

List<HistEvent> _addSelectionToBranch(List<HistEvent> branch, EditorSelection selection) {
  if (branch.isEmpty) {
    return <HistEvent>[
      HistEvent._selection(<EditorSelection>[selection]),
    ];
  } else {
    final lastEvent = branch.last;
    final all = lastEvent.selectionsAfter;
    final sels = all.sublist(all.length > _maxSelectionsPerEvent ? all.length - _maxSelectionsPerEvent : 0);
    if (sels.isNotEmpty && sels.last.eq(selection)) return branch;
    sels.add(selection);
    return _updateBranch(branch, branch.length - 1, 1000000000, lastEvent._setSelAfter(sels));
  }
}

// Assumes the top item has one or more selectionAfter values
List<HistEvent> _popSelection(List<HistEvent> branch) {
  final last = branch.last;
  final newBranch = List<HistEvent>.of(branch);
  newBranch[branch.length - 1] = last._setSelAfter(last.selectionsAfter.sublist(0, last.selectionsAfter.length - 1));
  return newBranch;
}

// Add a mapping to the top event in the given branch. If this maps away all the changes and effects in that item,
// drop it and propagate the mapping to the next item.
List<HistEvent> _addMappingToBranch(List<HistEvent> branch, ChangeDesc mapping) {
  if (branch.isEmpty) return branch;
  var length = branch.length;
  var selections = _noSelections;
  while (length > 0) {
    final event = _mapEvent(branch[length - 1], mapping, selections);
    if (event.changes != null && !event.changes!.empty || event.effects.isNotEmpty) {
      // Event survived mapping
      final result = branch.sublist(0, length);
      result[length - 1] = event;
      return result;
    } else {
      // Drop this event, since there's no changes or effects left
      // A step without changes has no mapping; it is always the first of its branch, so the walk ends here.
      mapping = event.mapped ?? mapping;
      length--;
      selections = event.selectionsAfter;
    }
  }
  return selections.isNotEmpty ? <HistEvent>[HistEvent._selection(selections)] : _noEvents;
}

HistEvent _mapEvent(HistEvent event, ChangeDesc mapping, List<EditorSelection> extraSelections) {
  final selections = _conc(
    event.selectionsAfter.isNotEmpty ? <EditorSelection>[for (final s in event.selectionsAfter) s.map(mapping)] : _noSelections,
    extraSelections,
  );
  // Change-less events don't store mappings (they are always the last event in a branch)
  final changes = event.changes;
  if (changes == null) return HistEvent._selection(selections);
  final mappedChanges = changes.map(mapping), before = mapping.mapDesc(changes, true);
  final fullMapping = event.mapped != null ? event.mapped!.composeDesc(before) : before;
  return HistEvent._(mappedChanges, StateEffect.mapEffects(event.effects, mapping), fullMapping, event.startSelection!.map(before), selections);
}

final RegExp _joinableUserEvent = RegExp(r'^(input\.type|delete)($|\.)');
final RegExp _selectEvent = RegExp(r'^select($|\.)');

/// CodeMirror's `HistoryState`, the value of [historyField]: what was done and what was undone.
class HistoryState {
  HistoryState._(this.done, this.undone, [this.prevTime = 0, this.prevUserEvent]);

  /// The steps that can be undone, oldest first.
  final List<HistEvent> done;

  /// The steps that can be redone.
  final List<HistEvent> undone;

  /// When the last step was added, for grouping; 0 after an isolate.
  final int prevTime;

  /// The last step's user event.
  final String? prevUserEvent;

  /// A history with nothing in it.
  static final HistoryState empty = HistoryState._(_noEvents, _noEvents);

  HistoryState _isolate() => prevTime != 0 ? HistoryState._(done, undone) : this;

  HistoryState _addChanges(HistEvent event, int time, String? userEvent, _ResolvedConfig config, Transaction tr) {
    var done = this.done;
    final lastEvent = done.isNotEmpty ? done.last : null;
    if (lastEvent != null &&
        lastEvent.changes != null &&
        !lastEvent.changes!.empty &&
        event.changes != null &&
        (userEvent == null || userEvent.isEmpty || _joinableUserEvent.hasMatch(userEvent)) &&
        ((lastEvent.selectionsAfter.isEmpty &&
                time - prevTime < config.newGroupDelay &&
                config.joinToEvent(tr, _isAdjacent(lastEvent.changes!, event.changes!))) ||
            // For compose (but not compose.start) events, always join with previous event
            userEvent == 'input.type.compose')) {
      done = _updateBranch(
        done,
        done.length - 1,
        config.minDepth,
        HistEvent._(
          event.changes!.compose(lastEvent.changes!),
          _conc(StateEffect.mapEffects(event.effects, lastEvent.changes!), lastEvent.effects),
          lastEvent.mapped,
          lastEvent.startSelection,
          _noSelections,
        ),
      );
    } else {
      done = _updateBranch(done, done.length, config.minDepth, event);
    }
    return HistoryState._(done, _noEvents, time, userEvent);
  }

  HistoryState _addSelection(EditorSelection selection, int time, String? userEvent, int newGroupDelay) {
    final last = done.isNotEmpty ? done.last.selectionsAfter : _noSelections;
    if (last.isNotEmpty &&
        time - prevTime < newGroupDelay &&
        userEvent == prevUserEvent &&
        userEvent != null &&
        _selectEvent.hasMatch(userEvent) &&
        _eqSelectionShape(last.last, selection)) {
      return this;
    }
    return HistoryState._(_addSelectionToBranch(done, selection), undone, time, userEvent);
  }

  HistoryState _addMapping(ChangeDesc mapping) =>
      HistoryState._(_addMappingToBranch(done, mapping), _addMappingToBranch(undone, mapping), prevTime, prevUserEvent);

  Transaction? _pop(int side, EditorState state, bool onlySelection) {
    final branch = side == _done ? done : undone;
    if (branch.isEmpty) return null;
    final event = branch.last;
    final selection = event.selectionsAfter.isNotEmpty
        ? event.selectionsAfter[0]
        : (event.startSelection != null ? event.startSelection!.map(event.changes!.invertedDesc, 1) : state.selection);
    if (onlySelection && event.selectionsAfter.isNotEmpty) {
      return state.update(
        TransactionSpec(
          selection: event.selectionsAfter.last,
          annotations: _fromHistory.of((side: side, rest: _popSelection(branch), selection: selection)),
          userEvent: side == _done ? 'select.undo' : 'select.redo',
          scrollIntoView: true,
        ),
      );
    } else if (event.changes == null) {
      return null;
    } else {
      var rest = branch.length == 1 ? _noEvents : branch.sublist(0, branch.length - 1);
      if (event.mapped != null) rest = _addMappingToBranch(rest, event.mapped!);
      return state.update(
        TransactionSpec(
          changes: event.changes,
          selection: event.startSelection,
          effects: event.effects,
          annotations: _fromHistory.of((side: side, rest: rest, selection: selection)),
          filter: false,
          userEvent: side == _done ? 'undo' : 'redo',
          scrollIntoView: true,
        ),
      );
    }
  }
}
