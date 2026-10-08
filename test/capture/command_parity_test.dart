import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/command.dart';
import 'package:ghost_md/capture/instruction_mutation.dart';
import 'package:ghost_md/capture/live_command.dart';
import 'package:ghost_md/capture/note_find.dart';
import 'package:ghost_md/capture/place.dart';
import 'package:ghost_md/capture/route.dart';
import 'package:ghost_md/capture/take_types.dart';

import 'support/shapes.dart';

/// The commands' grammar held to the web's own answers. Not a port of a web test: every string literal of the web's
/// capture tests (phrases people said, and notes' bodies) was put through the web's `parseRoute`, `planCommand`,
/// `readRoute`, `findNote`, `placeTake` and the rest by a throwaway Node script, and a sample of what they answered
/// is `fixtures/command_parity.json`. Each phrase here must come to the same thing, field for field.
///
/// `CAPTURE_PARITY` names another file of the same shape (the whole dump, kept out of the repository for its size).

/// A shape with every candidate as its id, as the dump wrote them.
Object? slim(Object? value) => switch (value) {
  final Candidate named => named.id,
  final List<Object?> list => [for (final each in list) slim(each)],
  final Map<Object?, Object?> map =>
    map['id'] is String && map['title'] is String ? map['id'] : {for (final each in map.entries) each.key: slim(each.value)},
  _ => value,
};

Object? shape(Object? value) => slim(shapeOf(slimNotes(value)));

/// Candidates taken out before [shapeOf] opens them up.
Object? slimNotes(Object? value) => value;

Map<String, Object?> placedShape(Placed placed) => {'body': placed.body, 'blocks': placed.blocks, 'spot': placed.spot};

Object? routeShape(TargetResolution<Candidate> found) => switch (found) {
  TargetResolutionResolved(:final note, :final score) => {'status': 'resolved', 'note': note.id, 'score': score},
  TargetResolutionAmbiguous(:final candidates) => {'status': 'ambiguous', 'candidates': [for (final c in candidates) c.id]},
  TargetResolutionNotFound() => {'status': 'not-found'},
};

void main() {
  final file = File(Platform.environment['CAPTURE_PARITY'] ?? 'test/capture/fixtures/command_parity.json');
  final dump = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final notes = <Candidate>[
    for (final raw in (dump['notes']! as List<Object?>).cast<Map<String, Object?>>())
      raw['body'] == null
          ? Candidate(id: raw['id']! as String, title: raw['title']! as String)
          : TakeCandidate<TakeNote>(id: raw['id']! as String, title: raw['title']! as String, note: TakeNote(id: raw['id']! as String, body: raw['body']! as String)),
  ];
  final aimed = dump['aim']! as Map<String, Object?>;
  final aim = Aim(id: aimed['id']! as String, body: aimed['body']! as String);
  final bases = (dump['bases']! as List<Object?>).cast<String>();
  final cases = (dump['cases']! as List<Object?>).cast<Map<String, Object?>>();

  test('every phrase of the web’s capture tests reads as the web reads it', () {
    final wrong = <String>[];
    void same(String phrase, String what, Object? actual, Object? expected) {
      if (!equals(expected).matches(actual, <Object?, Object?>{})) {
        if (wrong.length < 25) wrong.add('$what(${jsonEncode(phrase)})\n   web: ${jsonEncode(expected)}\n  dart: ${jsonEncode(actual)}');
      }
    }

    for (final item in cases) {
      final s = item['s']! as String;
      final words = commandWords(s);
      same(s, 'parseRoute', shape(parseRoute(s)), item['parseRoute']);
      same(s, 'similarity', [for (final n in notes) similarity(s, n.title)], item['similarity']);
      same(s, 'resolveTarget', routeShape(resolveTarget(s, notes)), item['resolveTarget']);
      final keyword = findKeyword(s);
      same(s, 'findKeyword', keyword == null ? null : {'before': keyword.before, 'after': keyword.after}, item['findKeyword']);
      same(s, 'finalCommandWords', finalCommandWords(s), item['finalCommandWords']);
      same(s, 'onlyFiller', onlyFiller(s), item['onlyFiller']);
      same(s, 'isStandaloneCommandLike', isStandaloneCommandLike(s), item['standalone']);
      same(s, 'withoutPayloadLead', withoutPayloadLead(s), item['withoutPayloadLead']);
      same(s, 'cellsOf', cellsOf(s), item['cellsOf']);
      same(s, 'planCommand', shape(planCommand(s, notes: notes)), item['plan']);
      same(s, 'planCommand(commandWords)', shape(planCommand(words, notes: notes)), item['planWords']);
      same(s, 'commandWords', words, item['commandWords']);
      same(s, 'readRoute', shape(readRoute(words)), item['readRoute']);
      same(s, 'readNameFirst', shape(readNameFirst(s)), item['readNameFirst']);
      same(s, 'isOpener', isOpener(s), item['isOpener']);
      same(s, 'nameable', nameable(s).name, item['nameable']);
      same(s, 'onlyLead', onlyLead(s), item['onlyLead']);
      same(s, 'onlyFillerPhrase', onlyFillerPhrase(s), item['onlyFillerPhrase']);
      same(s, 'silenceLine', silenceLine(s), item['silenceLine']);
      same(s, 'bareShape', [for (final r in readRoute(words)) bareShape(r)], item['bareShapes']);
      same(s, 'nameWords', shape(nameWords(s)), item['nameWords']);
      same(s, 'titleKind', titleKind(s)?.name, item['titleKind']);
      same(s, 'findNote', shape(findNote(s, notes)), item['findNote']);
      same(s, 'findNote(aim)', shape(findNote(s, notes, aim: aim)), item['findNoteAimed']);
      same(s, 'headingsOf', headingsOf(s), item['headingsOf']);
      final items = itemsOf(s);
      same(s, 'itemsOf', {
        'items': [
          for (final each in items.items) {'text': each.text, 'more': each.more},
        ],
        'after': items.after,
      }, item['itemsOf']);
      same(s, 'placeTake', [for (final base in bases) placedShape(placeTake(base, s, placingFor(base)))], item['placed']);
      same(s, 'placeTake(task, heading)', placedShape(placeTake(aim.body, s, placingFor(aim.body, said: const Said(task: true), heading: 'electrical'))), item['placedTask']);
      same(s, 'placingFor', placingFor(s).toJson(), item['placingFor']);
      same(s, 'literalMarkdown', literalMarkdown(s), item['literal']);
      same(s, 'listTitle', listTitle(s), item['listTitle']);
    }
    expect(wrong, isEmpty, reason: wrong.join('\n\n'));
  });
}
