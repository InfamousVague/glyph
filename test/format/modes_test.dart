// A port of src/app/format/modes.test.ts.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/format/modes.dart';

void main() {
  group('the robot’s three modes', () {
    test('are Format, Summarize and Enhance, in the order the note’s cog lists them', () {
      expect(modes.map((mode) => mode.id.id), ['format', 'summarize', 'enhance']);
      expect(modes.every((mode) => isMode(mode.id)), isTrue);
      expect(RunKind.values.where(isMode), [RunKind.format, RunKind.summarize, RunKind.enhance]);
    });

    test('say in the cog what each does, under its word', () {
      // The words the note's cog draws for each row: the label, and the hint under it.
      expect(modes.map((mode) => (mode.label, mode.hint)), [
        ('Format', 'Tidy and organise, keeping every word that matters.'),
        ('Summarize', 'The point of the note and its tasks, in far fewer words.'),
        ('Enhance', 'Every thought finished and the note made fuller, without inventing.'),
      ]);
    });
  });
}
