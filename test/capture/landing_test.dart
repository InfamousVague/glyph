import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/landing.dart';

/// What a recording left in a note (lib/capture/landing.dart), case for case with the web's
/// `capture/landing.test.ts`.

/// [doc] with the changes `takeOut` found made.
({String out, int missing}) undone(String doc, List<String> blocks) {
  final found = takeOut(doc, blocks);
  var out = doc;
  for (final change in found.changes.reversed) {
    out = out.substring(0, change.from) + out.substring(change.to);
  }
  return (out: out, missing: found.missing);
}

void main() {
  group('taking a recording’s words out of the note again', () {
    test('takes out an item it put in a list, and the break before it', () {
      expect(undone('# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n', ['- [ ] Call Sam']), (out: '# House TODOs\n\n- [ ] Fix the gutter\n', missing: 0));
    });

    test('takes out a paragraph it put at the end, with the blank line before it', () {
      expect(undone('# Daily Life\n\nWent for a walk.\n\nWent for a run.', ['Went for a run.']), (out: '# Daily Life\n\nWent for a walk.', missing: 0));
    });

    test('takes out several pieces, in several lists', () {
      const doc = '## Electrical\n- [ ] Rewire\n- [ ] Call Sam\n\n## Garden\n- [ ] Mow\n- [ ] Trim the hedge\n';
      expect(undone(doc, ['- [ ] Call Sam', '- [ ] Trim the hedge']).out, '## Electrical\n- [ ] Rewire\n\n## Garden\n- [ ] Mow\n');
    });

    test('leaves a piece edited since, or there twice, as it is', () {
      expect(undone('- [ ] Call Sam tomorrow\n', ['- [ ] Call Sam']), (out: '- [ ] Call Sam tomorrow\n', missing: 1));
      expect(undone('- [ ] Call Sam\n- [ ] Call Sam\n', ['- [ ] Call Sam']), (out: '- [ ] Call Sam\n- [ ] Call Sam\n', missing: 1));
    });
  });

  group('what the note’s toast says', () {
    const landing = CaptureLanding(noteId: 'n', title: 'House TODOs', blocks: ['- [ ] Call Sam'], others: [], made: []);

    test('names the note the words went into, and the others', () {
      expect(landingLine(landing), 'Added to House TODOs');
      expect(landingLine(landing.copyWith(others: ['m1'], into: ['Home jobs'])), 'Added to House TODOs and Home jobs');
      expect(landingLine(landing.copyWith(others: ['m1', 'm2'], into: ['Home jobs', 'Todo'])), 'Added to House TODOs and 2 other notes');
    });

    test('names only the others for a note of the take’s own, which had nothing added to it', () {
      expect(landingLine(landing.copyWith(title: 'Buy milk', blocks: [], others: ['m1', 'm2'], into: ['House TODOs', 'Home jobs'])), 'Added to House TODOs and Home jobs');
    });

    test('names what the recording took back at Done, unseen', () {
      expect(landingLine(landing.copyWith(tookBack: ['Call Sam'])), 'Added to House TODOs. Took back “Call Sam”');
      expect(landingLine(landing.copyWith(tookBack: ['Call Sam', 'Buy fuses'])), 'Added to House TODOs. Took back “Call Sam” and 1 more');
      expect(landingLine(landing.copyWith(tookBack: [])), 'Added to House TODOs');
    });
  });
}
