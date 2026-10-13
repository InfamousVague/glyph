import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/live_take.dart';
import 'package:ghost_md/capture/take_types.dart';
import 'package:ghost_md/capture/ui/read_instruction.dart';
import 'package:ghost_md/capture/voice_plan.dart';
import 'package:ghost_md/core/note.dart' show Segment;
import 'package:ghost_md/guide/phrases.dart';

/// `guide/guide.test.ts`, case for case. The guide may only teach what the speech rules do. Each example is rendered
/// by the real rules and must still produce its marker; a failure here means a rule changed and the guide
/// (lib/guide/phrases.dart) has to change with it.
void main() {
  group('the spoken-markdown guide', () {
    for (final group in phrases) {
      test('"${group.title}" still produces ${jsonEncode(group.example.expect)}', () {
        expect(renderExample(group.example), contains(group.example.expect));
      });
    }

    test('never shows a cue word left behind as text', () {
      final left = RegExp(r'\b(bullet point|next point|heading:|new paragraph|new section|quote:|check box|divider|end bold|end italic|number one|number two)\b', caseSensitive: false);
      for (final group in phrases) {
        expect(renderExample(group.example), isNot(matches(left)), reason: group.title);
      }
    });

    test('applies a cue said on its own to the next sentence, as the guide promises', () {
      expect(renderExample(cueAlone), contains(cueAlone.expect));
    });

    test('shows beside each cue the mark its example really writes', () {
      for (final group in phrases) {
        final first = group.symbol.split(' ').first;
        if (first.isNotEmpty) expect(renderExample(group.example), contains(first), reason: group.title);
      }
    });
  });

  // The habits page's two phrases, bare as the page said them, and with "Hey Ghost" first, which is optional.
  group('what the habits page says to say, with or without “Hey Ghost” first', () {
    const groceries = (id: 'g1', title: 'Groceries', body: '# Groceries\n\n- Eggs\n');
    const library = [groceries, (id: 'w1', title: 'Work', body: '# Work\n')];
    String keyed(String say) => 'Hey Ghost, ${say[0].toLowerCase()}${say.substring(1)}';
    List<String> ways(String say) => [say, keyed(say)];
    List<MemoryNote> memory() => [for (final c in library) MemoryNote(id: c.id, body: c.body)];
    List<TakeCandidate<TakeNote>> candidates() => [for (final c in library) TakeCandidate(id: c.id, title: c.title, note: TakeNote(id: c.id, body: c.body))];

    test('is a command the recorder carries out as it is said, putting the words in the note it names', () {
      for (final said in ways(command.say)) {
        final take = LiveTake(memory());
        take.phrase(Segment(text: '$said.', startMs: 0, endMs: 1500), 0);
        take.close(2000);
        expect(take.body('g1'), '# Groceries\n\n- Eggs\n- ${command.words[0].toUpperCase()}${command.words.substring(1)}\n', reason: said);
        expect(take.result().made, isEmpty, reason: said);
      }
    });

    test('is a command for a note whose title does not say it is a list, with “a note” said, carried out as it is said', () {
      for (final said in ways(noteCommand.say)) {
        final take = LiveTake(memory());
        take.phrase(const Segment(text: 'First words.', startMs: 0, endMs: 900), 0);
        take.phrase(Segment(text: '$said.', startMs: 1000, endMs: 2500), 1000);
        take.close(3000);
        expect(take.body('w1'), '# ${noteCommand.note}\n\n${noteCommand.words}', reason: said);
      }
    });

    test('is read the same by the reader at Done, putting the words in the note it names', () async {
      for (final said in ways(command.say)) {
        final read = await readInstruction(said, candidates());
        expect(read.kind, 'command', reason: said);
        final actions = (read as ReadCommand<TakeCandidate<TakeNote>>).actions;
        expect(actions, hasLength(1), reason: 'one request, one change');
        final action = actions.single;
        expect(action, isA<VoiceAppend<TakeCandidate<TakeNote>>>(), reason: 'not a command to place words');
        action as VoiceAppend<TakeCandidate<TakeNote>>;
        expect(action.note.title, command.note);
        expect(action.text, command.words);
      }
    });

    test('is an ask the AI runs on the note, not words written into it', () async {
      for (final said in ways(ask.say)) {
        final read = await readInstruction(said, candidates());
        expect(read, isA<ReadRun<TakeCandidate<TakeNote>>>(), reason: said);
        expect((read as ReadRun<TakeCandidate<TakeNote>>).run, ask.run, reason: said);
      }
    });
  });
}
