import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/command.dart';
import 'package:ghost_md/capture/final_instruction.dart';
import 'package:ghost_md/capture/instruction_intent.dart';
import 'package:ghost_md/capture/live_command.dart';
import 'package:ghost_md/capture/note_find.dart';
import 'package:ghost_md/capture/offers.dart';
import 'package:ghost_md/capture/route.dart';
import 'package:ghost_md/capture/take_types.dart';
import 'package:ghost_md/core/note.dart';

/// The web's `toMatchObject`, for the classes the capture port answers where the web answers object literals: a value
/// is read as the object literal it is on the web ([shapeOf]), and only the names a case gives are compared
/// ([matchObject]). Not a port of anything: vitest has this built in.

/// [value] as the web's object literal: a map by the web's field names, enums as their words.
Object? shapeOf(Object? value) => switch (value) {
  null || String() || num() || bool() => value,
  final Enum word => word.name,
  final List<Object?> list => [for (final each in list) shapeOf(each)],
  final Map<Object?, Object?> map => {for (final each in map.entries) each.key: shapeOf(each.value)},
  final TakeCandidate<Object> named => {'id': named.id, 'title': named.title, 'note': shapeOf(named.note)},
  final Candidate named => {'id': named.id, 'title': named.title},
  final TakeNote note => {'id': note.id, 'body': note.body},
  final Note note => {'id': note.id, 'body': note.body},
  final RouteCommandNote route => {'kind': 'note', 'name': route.name, 'rest': route.rest},
  final RouteCommandItem route => {'kind': 'item', 'name': route.name, 'rest': route.rest, 'task': route.task, 'many': route.many},
  final RouteCommandLeave route => {'kind': 'leave', 'name': route.name, 'rest': route.rest},
  final RouteCommandNew route => {'kind': 'new', 'rest': route.rest},
  final Placement placement => _placement(placement),
  final PlanPlace plan => {'kind': 'place', 'note': shapeOf(plan.note), 'text': plan.text, ..._placement(plan.placement)},
  final PlanAwait plan => {'kind': 'await', 'note': shapeOf(plan.note), ..._placement(plan.placement)},
  final PlanMove plan => {'kind': 'move', 'note': shapeOf(plan.note)},
  PlanNew() => {'kind': 'new'},
  final PlanCreateList plan => {'kind': 'create-list', 'title': plan.title, if (plan.items != null) 'items': plan.items},
  final PlanTable plan => {'kind': 'table', 'note': shapeOf(plan.note), 'columns': plan.columns},
  PlanBoard() => {'kind': 'board'},
  final PlanBook plan => {'kind': 'book', 'title': plan.title, 'pages': plan.pages},
  final PlanChapter plan => {'kind': 'chapter', 'note': shapeOf(plan.note), 'title': plan.title},
  final PlanNoNote plan => {'kind': 'no-note', 'name': plan.name},
  final HeardKeyword heard => {'before': heard.before, 'after': heard.after, 'misheard': heard.misheard},
  final Reading r => {
    'shape': r.shape,
    'name': r.name,
    'payload': r.payload,
    'trailing': r.trailing,
    'tail': r.tail,
    'placing': r.placing.name,
    'heading': r.heading,
    'move': r.move,
    'plainMove': r.plainMove,
    'nameFirst': r.nameFirst,
    'newNote': r.newNote,
    'self': r.self,
    'stopped': r.stopped,
    'noun': r.noun,
    'filed': r.filed,
    'split': r.split,
    'verb': r.verb,
  },
  final NameWords words => {'words': words.words, 'distinctive': words.distinctive, 'specific': words.specific, 'generic': words.generic},
  final FoundResolved<Object?> found => {'status': 'resolved', 'note': shapeOf(found.note), 'score': found.score},
  final FoundCurrent<Object?> found => {'status': 'current', 'heading': found.heading},
  final FoundUnsure<Object?> found => {'status': 'unsure', 'candidates': shapeOf(found.candidates), 'score': found.score},
  final FoundMissing<Object?> found => {'status': 'missing', 'near': shapeOf(found.near)},
  final OfferPlace<Object> offer => {
    'kind': 'place',
    'note': shapeOf(offer.note),
    'title': offer.title,
    'text': offer.text,
    'placement': _placement(offer.placement),
    'added': offer.added,
    'into': offer.into.name,
  },
  final OfferNew<Object> offer => {'kind': 'new', 'title': offer.title, if (offer.lines != null) 'lines': offer.lines},
  final InstructionIntentAppend intent => {'action': 'append', 'target': intent.target, 'content': intent.content, 'placement': intent.placement?.name},
  final InstructionIntentCreate intent => {'action': 'create', 'target': intent.target, 'content': intent.content},
  final InstructionIntentNone intent => {'action': 'none', 'reason': intent.reason.name},
  final InferenceResultIntent result => {'status': 'intent', 'intent': shapeOf(result.intent), 'model': result.model},
  final InferenceResultUnavailable result => {'status': 'unavailable', 'reason': result.reason},
  final InterpretedCommandDeterministic read => {'source': 'deterministic', 'plan': shapeOf(read.plan)},
  final InterpretedCommandInferred read => {'source': 'inferred', 'intent': shapeOf(read.intent), if (read.note != null) 'note': shapeOf(read.note)},
  final InterpretedCommandRejected read => {'source': 'rejected', 'reason': read.reason},
  final FinalInstructionOrdinary read => {'kind': 'ordinary', 'notice': read.notice},
  final FinalInstructionOffer read => {'kind': 'offer', 'plan': shapeOf(read.plan)},
  final FinalInstructionRejected read => {'kind': 'rejected', 'reason': read.reason},
  _ => value,
};

Map<String, Object?> _placement(Placement placement) => {
  'how': placement.how.name,
  'task': placement.task,
  'many': placement.many,
  if (placement.near != null) 'near': placement.near,
  if (placement.items != null) 'items': placement.items,
};

/// Whether [actual], already a shape, has everything [expected] names.
bool shapeHas(Object? actual, Object? expected) {
  if (expected is Matcher) return expected.matches(actual, <Object?, Object?>{});
  if (expected is Map) {
    if (actual is! Map) return false;
    for (final each in expected.entries) {
      if (!actual.containsKey(each.key) || !shapeHas(actual[each.key], each.value)) return false;
    }
    return true;
  }
  if (expected is List) {
    if (actual is! List || actual.length != expected.length) return false;
    for (var i = 0; i < expected.length; i += 1) {
      if (!shapeHas(actual[i], expected[i])) return false;
    }
    return true;
  }
  return actual == shapeOf(expected) || actual == expected;
}

/// `expect(value).toMatchObject(expected)`: the value's shape has every field [expected] names, with that value.
Matcher matchObject(Map<String, Object?> expected) => _MatchObject(expected);

/// `expect.objectContaining` inside a list: the same, by another name where the web's reads that way.
Matcher objectContaining(Map<String, Object?> expected) => _MatchObject(expected);

class _MatchObject extends Matcher {
  const _MatchObject(this.expected);

  final Map<String, Object?> expected;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) => shapeHas(shapeOf(item), shapeOf(expected));

  @override
  Description describe(Description description) => description.add('an object with ').addDescriptionOf(expected);

  @override
  Description describeMismatch(Object? item, Description mismatchDescription, Map<Object?, Object?> matchState, bool verbose) =>
      mismatchDescription.add('is ').addDescriptionOf(shapeOf(item));
}
