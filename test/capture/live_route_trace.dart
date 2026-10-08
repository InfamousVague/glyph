/// What the live reader's tests (`live_route_test.dart`) are held against besides their own expectations: the steps
/// the web's reader handed its take in the same case, as `tool/voice_fixtures.mjs` wrote them to
/// `fixtures/live_route_web.json`.
///
/// `describe` and `it` stand where the web test has them; each case's takes are made by [tracedTake], which keeps
/// every list of steps `LiveTake.apply` is given. When the case's body is done, the steps of each take are compared
/// with the web's, list by list: a note is its id, and what is null is left out, on both sides.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/live_route.dart';
import 'package:ghost_md/capture/live_take.dart';
import 'package:ghost_md/capture/markdown.dart';
import 'package:ghost_md/capture/place.dart' show Placing, PlacingEnd, PlacingLane, PlacingLists;
import 'package:ghost_md/capture/take_host.dart';

final List<String> _groups = [];
List<List<Object?>> _takes = [];

Map<String, Object?>? _web;
Map<String, Object?> get _fixture => _web ??= jsonDecode(File('test/capture/fixtures/live_route_web.json').readAsStringSync()) as Map<String, Object?>;

/// The web's `describe`.
void describe(String name, void Function() body) {
  _groups.add(name);
  group(name, body);
  _groups.removeLast();
}

/// The web's `it`: the case's own expectations, then its steps against the web's.
void it(String name, void Function() body) {
  final full = [..._groups, name].join(' > ');
  test(name, () {
    _takes = [];
    try {
      body();
    } catch (_) {
      final wrong = _mismatch(full);
      if (wrong != null) printOnFailure(wrong);
      rethrow;
    }
    final wrong = _mismatch(full);
    if (wrong != null) fail(wrong);
  });
}

/// Where this case's steps part from the web's, or null when they are the same.
String? _mismatch(String name) {
  final web = _fixture[name];
  if (web == null) return 'no web trace for "$name"';
  final theirs = web as List<Object?>;
  for (var t = 0; t < theirs.length || t < _takes.length; t += 1) {
    final want = t < theirs.length ? theirs[t]! as List<Object?> : const <Object?>[];
    final got = t < _takes.length ? _takes[t] : const <Object?>[];
    for (var a = 0; a < want.length || a < got.length; a += 1) {
      final w = a < want.length ? jsonEncode(_sorted(want[a])) : '(nothing)';
      final g = a < got.length ? jsonEncode(_sorted(got[a])) : '(nothing)';
      if (w != g) return 'steps differ from the web in "$name", take $t, apply $a:\n  web:  $w\n  dart: $g';
    }
  }
  return null;
}

/// Data with every map's keys in order, so two of the same thing encode the same.
Object? _sorted(Object? value) => switch (value) {
  final Map<Object?, Object?> map => {for (final key in map.keys.cast<String>().toList()..sort()) key: _sorted(map[key])},
  final List<Object?> list => list.map(_sorted).toList(),
  _ => value,
};

class _TracedTake extends LiveTake {
  _TracedTake(super.notes, [super.options]);

  List<Object?>? _trace;

  @override
  void apply(List<LiveStep<MemoryNote>> steps) {
    if (_trace == null) {
      _trace = [];
      _takes.add(_trace!);
    }
    _trace!.add(steps.map(stepJson).toList());
    super.apply(steps);
  }
}

/// A take whose steps are kept for the case it is made in.
LiveTake tracedTake(List<MemoryNote> notes, [LiveTakeOptions options = const LiveTakeOptions()]) => _TracedTake(notes, options);

Map<String, Object?> _without(Map<String, Object?> map) => map..removeWhere((_, value) => value == null);

Map<String, Object?> _segment(Segment segment) => {'text': segment.text, 'startMs': segment.startMs, 'endMs': segment.endMs};

Map<String, Object?> _placing(Placing placing) => switch (placing) {
  PlacingEnd() => _without({'kind': 'end', 'lead': placing.lead}),
  PlacingLists() => _without({'kind': 'lists', 'task': placing.task, 'heading': placing.heading, 'fresh': placing.fresh?.name}),
  PlacingLane() => {'kind': 'lane', 'lane': placing.lane},
};

Map<String, Object?> _card(LiveCard<MemoryNote> card) => {
  'id': card.id,
  'form': card.form.name,
  'heading': card.heading,
  'candidates': [
    for (final candidate in card.candidates) {'id': candidate.id, 'title': candidate.title, 'note': candidate.note.id},
  ],
  'newTitle': card.newTitle,
  'payload': card.payload,
};

/// A chip as the web's object, what is null left out: `{'phase': 'waiting', 'title': 'House TODOs'}`.
Map<String, Object?>? chipJson(RouteView? view) => switch (view) {
  null => null,
  RouteViewHearing() => {'phase': 'hearing', 'name': view.name},
  RouteViewDone() => {'phase': 'done', 'text': view.text},
  RouteViewCommand() => {'phase': 'command', 'words': view.words},
  RouteViewSaid() => {'phase': 'said', 'text': view.text},
  RouteViewWaiting() => {'phase': 'waiting', 'title': view.title},
  RouteViewAdded() => _without({'phase': 'added', 'title': view.title, 'body': view.body, 'added': view.added, 'insert': view.insert}),
  RouteViewMoved() => _without({'phase': 'moved', 'title': view.title, 'spot': view.spot}),
  RouteViewMissed() => {'phase': 'missed', 'title': view.title},
  RouteViewTookBack() => _without({
    'phase': 'tookBack',
    'said': view.said,
    'outcome': switch (view.outcome) {
      TookBackGone() => 'gone',
      TookBackSent(:final sent) => {'sent': sent},
      TookBackPlaced(:final placed) => {'placed': placed},
      TookBackChanged(:final changed) => {'changed': changed},
      TookBackReplaced(:final replaced) => {'replaced': replaced},
    },
    'undo': view.undo,
  }),
};

/// A step as the web's object: a note is its id, and what is null is left out.
Map<String, Object?> stepJson(LiveStep<MemoryNote> step) => _without(switch (step) {
  LiveStepWords() => {'kind': 'words', 'segment': _segment(step.segment), 'payload': step.payload},
  LiveStepUnword() => {'kind': 'unword', 'segments': step.segments.map(_segment).toList()},
  LiveStepCommand() => {
    'kind': 'command',
    'span': {'startMs': step.span.startMs, 'endMs': step.span.endMs},
  },
  LiveStepKeyword() => {
    'kind': 'keyword',
    'span': {'startMs': step.span.startMs, 'endMs': step.span.endMs},
  },
  LiveStepRoute() => {'kind': 'route', 'note': step.note.id, 'title': step.title, 'placing': _placing(step.placing), 'move': step.move, 'spot': step.spot},
  LiveStepRouteNew() => {'kind': 'route-new', 'title': step.title, 'task': step.task},
  LiveStepHome() => {'kind': 'home'},
  LiveStepPlacing() => {'kind': 'placing', 'placing': _placing(step.placing)},
  LiveStepInsert() => {'kind': 'insert', 'id': step.id, 'note': step.note.id, 'title': step.title, 'placing': _placing(step.placing), 'segments': step.segments.map(_segment).toList()},
  LiveStepInsertWords() => {'kind': 'insert-words', 'id': step.id, 'segments': step.segments.map(_segment).toList()},
  LiveStepInsertUnword() => {'kind': 'insert-unword', 'id': step.id, 'segments': step.segments.map(_segment).toList()},
  LiveStepInsertEnd() => {'kind': 'insert-end', 'id': step.id},
  LiveStepInsertDrop() => {'kind': 'insert-drop', 'id': step.id},
  LiveStepNewNote() => {'kind': 'new-note'},
  LiveStepCard() => {'kind': 'card', 'card': step.card == null ? null : _card(step.card!)},
  LiveStepAsk() => {'kind': 'ask', 'run': step.run, 'instruction': step.instruction},
  LiveStepChip() => {'kind': 'chip', 'view': chipJson(step.view)},
  LiveStepHaptic() => {'kind': 'haptic', 'haptic': step.haptic.name},
  LiveStepLog() => {'kind': 'log', 'line': step.line},
});
