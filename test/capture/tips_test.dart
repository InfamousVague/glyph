import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/live_take.dart';
import 'package:ghost_md/capture/markdown.dart' show Segment;
import 'package:ghost_md/capture/tips.dart';
import 'package:ghost_md/core/book.dart' show bookNoteBody;

/// What the recorder suggests saying (lib/capture/tips.dart), case for case with the web's `capture/tips.test.ts`.
///
/// Two of the web's cases hold a tip to the reader at Done (`ai/instruction.ts`: `readInstruction`, `bareWords`,
/// `runOf`), which is `lib/ai`'s to port and is not this folder's to import. So what that reader answers for each
/// tip's words is data here: `fixtures/tips.json`, written by running the web's own reader over the web's own tips
/// (a throwaway script, `tips.mjs`). Each case first holds the Dart tip to the words the web reader was given, then
/// holds the web reader's answer to what the web's test expects.

Segment seg(String text, int startMs, int endMs) => Segment(text: text, startMs: startMs, endMs: endMs);

String lowerFirst(String text) => text[0].toLowerCase() + text.substring(1);

void main() {
  final fixture = jsonDecode(File('test/capture/fixtures/tips.json').readAsStringSync()) as Map<String, Object?>;

  group('tips in a pause', () {
    test('teach the newer cues', () {
      final said = tips(noteTitle: 'Groceries', continuing: true).map((tip) => tip.say);
      expect(said, contains('Info box'));
      expect(said, contains('Option'));
    });

    // A take-back is a cue, not a command: said without any keyword, and taught early.
    test('teach taking back the last thing said, and it works as taught', () {
      final tip = tips(noteTitle: 'Groceries', continuing: true).where((candidate) => candidate.say == 'Scratch that').firstOrNull;
      expect(tip, const Tip(say: 'Scratch that', does: 'to take back the last thing you said'));
      final take = LiveTake(const []);
      take.phrase(seg('Pick up the parcel.', 0, 900), 0);
      take.phrase(seg('Call Sam.', 1000, 1900), 1000);
      take.phrase(seg('${tip!.say}.', 2000, 2900), 2000);
      take.close(3000);
      expect(take.result().made, ['# Pick up the parcel']);
    });

    // Changed on purpose: a recording no longer makes a voice memo, so no tip offers one. The clips already in notes
    // still play.
    test('offer no voice memo', () {
      final said = tips(noteTitle: 'Groceries', continuing: true).expand((tip) => [tip.say, tip.does]);
      expect(said.any((line) => RegExp(r'\bmemo\b', caseSensitive: false).hasMatch(line)), false);
    });

    // Changed on purpose: a recording no longer carries out a table, a book or a chapter, so no tip teaches one. Nor
    // a notebook or a journal, the book's names since. A board's lane is carried out on its own Speak but not taught
    // yet. A command needs no keyword: every tip says it bare, in a form the bare gate takes.
    test('teach only the commands a recording carries out as they are said, without the keyword', () {
      final said = tips(noteTitle: 'Groceries', continuing: true).map((tip) => tip.say).toList();
      for (final line in ['Add … to Groceries', 'New item for Groceries, …', 'New note', 'Move this to Groceries']) {
        expect(said, contains(line));
      }
      expect(said.any((line) => RegExp(r'\b(?:table|chapter|book|notebook|journal|lane)\b', caseSensitive: false).hasMatch(line)), false);
      expect(said.any((line) => RegExp(r'fix the spelling|summari[sz]e', caseSensitive: false).hasMatch(line)), false);
      expect(said.any((line) => RegExp('Hey Ghost', caseSensitive: false).hasMatch(line)), false);
      // A note whose title does not say it is a list: "a note" said is the evidence the gate wants.
      expect(tips(noteTitle: 'Work', continuing: true).map((tip) => tip.say), contains('Add a note to Work, …'));
    });
  });

  group('the card before the first word', () {
    test('shows a couple of each kind, naming a note of theirs', () {
      final card = starters(noteTitle: 'Groceries', asking: true);
      expect(card.shape.map((tip) => tip.say), ['Bullet point', 'The next item is …']);
      expect(card.send.map((tip) => tip.say), ['Add … to Groceries', 'Move this to Groceries']);
      expect(card.ask.map((tip) => tip.say), ['Fix the spelling', 'Summarise this']);
    });

    test('still sends somewhere with no note to name, and offers no ask where none can run', () {
      final card = starters(noteTitle: null);
      expect(card.send.map((tip) => tip.say), ['Make a list called … with …']);
      expect(card.ask, isEmpty);
      expect(starters(noteTitle: null, asking: true).ask.first.say, 'Fix the spelling');
    });

    // Its items said the natural way, in a sentence after the name, would be the reader's title: the tip teaches
    // "with". The reader is the web's own (see the header): its answers are the fixture's.
    test('makes a new list with its items, as the reader at Done reads it, with the keyword or without', () {
      final tip = starters(noteTitle: null).send.first;
      final read = (fixture['list'] as List).cast<Map<String, Object?>>();
      expect(read.map((row) => row['lead']), ['', 'Hey Ghost, ']);
      for (final row in read) {
        final lead = row['lead'] as String;
        final said = '$lead${lead.isNotEmpty ? lowerFirst(tip.say) : tip.say}'.replaceFirst('…', 'packing').replaceFirst('…', 'toothbrush, socks and charger');
        expect(row['said'], said, reason: 'the words the web reader was given');
        expect(
          row['read'],
          {
            'kind': 'command',
            'plan': {
              'kind': 'create-list',
              'title': 'packing',
              'items': ['toothbrush', 'socks', 'charger'],
            },
          },
          reason: said,
        );
      }
    });

    test('never suggests an ask the reader would not take: each one, spoken first, is read as its run, bare as the whole phrase', () {
      expect(asks.length, 5);
      final read = (fixture['asks'] as List).cast<Map<String, Object?>>();
      expect(read.map((row) => row['say']), asks.map((ask) => ask.say));
      for (var i = 0; i < asks.length; i += 1) {
        final ask = asks[i];
        final row = read[i];
        expect((row['bare'] as Map?)?['keyed'], false, reason: ask.say);
        expect(row['runWhole'], isNotNull, reason: ask.say);
        expect(row['keyedSaid'], 'Hey Ghost, ${lowerFirst(ask.say)}', reason: 'the words the web reader was given');
        expect((row['keyed'] as Map?)?['keyed'], true, reason: ask.say);
        expect(row['runKeyed'], isNotNull, reason: ask.say);
      }
    });
  });

  /// Every tip that sends words to a note, said with a sample of words, as the live reader hears it
  /// (lib/capture/live_route.dart): a tip is always something that works.
  group('the tips that send words to a note', () {
    const groceries = MemoryNote(id: 'groceries', body: '# Groceries\n\n- Eggs\n');
    const work = MemoryNote(id: 'work', body: '# Work\n\nNotes.\n');
    List<Tip> sending(List<Tip> list) => list.where((tip) => RegExp('Groceries|new note', caseSensitive: false).hasMatch(tip.say)).toList();

    test('are each carried out, mid-take on a note’s own Speak, as the tip says, without the keyword', () {
      final list = sending([...tips(noteTitle: 'Groceries', continuing: true), ...starters(noteTitle: 'Groceries').send]);
      expect(list.length, greaterThan(3));
      for (final tip in list) {
        final take = LiveTake(const [groceries, work], const LiveTakeOptions(own: work));
        take.phrase(seg('First words.', 0, 900), 0);
        final said = '${tip.say.replaceFirst('…', 'oat milk')}.';
        take.phrase(seg(said, 1000, 1900), 1000);
        take.close(2000);
        final (:bodies, :made) = take.result();
        if (RegExp('move this', caseSensitive: false).hasMatch(tip.say)) {
          expect(take.aim?.id, 'groceries', reason: said);
        } else if (RegExp('new note', caseSensitive: false).hasMatch(tip.say)) {
          expect(take.parts, hasLength(1), reason: said);
        } else {
          expect(bodies['groceries'], contains('Oat milk'), reason: said);
        }
        expect(RegExp('Hey Ghost', caseSensitive: false).hasMatch(made.join()), false, reason: said);
      }
    });

    // The item after the name in the same breath, as the tip says: mid-take a bare command needs its words in its
    // own phrase, so "New item for Groceries." | "Oat milk." is two lines of the take, which is why the tip does not
    // teach it.
    test('teach the item in the same breath as its note, since the two breaths apart are words mid-take', () {
      final tip = tips(noteTitle: 'Groceries', continuing: true).where((candidate) => candidate.say.startsWith('New item for')).firstOrNull;
      expect(tip, const Tip(say: 'New item for Groceries, …', does: 'with the item after it, to add to its list'));
      final take = LiveTake(const [groceries, work], const LiveTakeOptions(own: work));
      take.phrase(seg('First words.', 0, 900), 0);
      take.phrase(seg('New item for Groceries.', 1000, 1900), 1000);
      take.phrase(seg('Oat milk.', 2000, 2900), 2000);
      take.close(3000);
      expect(take.result().bodies['groceries'], groceries.body);
    });

    // A note whose title does not say it is a list gets the "a note" form, which the gate takes into any note.
    test('send words into a note whose title does not say it is a list, with “a note” said', () {
      final tip = starters(noteTitle: 'Work').send.first;
      expect(tip.say, 'Add a note to Work, …');
      final take = LiveTake(const [groceries, work], const LiveTakeOptions(own: groceries));
      take.phrase(seg('First words.', 0, 900), 0);
      take.phrase(seg('${tip.say.replaceFirst('…', 'call Sam')}.', 1000, 1900), 1000);
      take.close(2000);
      expect(take.result().bodies['work'], '# Work\n\nNotes.\n\nCall Sam.');
    });

    // A title that starts with a verb is read as what to do ("Call log" is "call log"), so no tip names it: bare,
    // "Add a note to Call log, call Sam" and "Move this to Book club" are words. The tips name the next note, and
    // the card offers a new list instead.
    test('never name a note whose title starts with a verb, and each tip they give instead is carried out', () {
      const calls = TipNote(id: 'calls', title: 'Call log', body: '# Call log\n\n- Jo\n');
      const club = TipNote(id: 'club', title: 'Book club', body: '# Book club\n\n- Dune\n');
      final named = <String>{
        for (var turn = 0; turn < 120; turn += 1)
          tipInPause(notes: [calls, club, TipNote(id: 'work', title: 'Work', body: work.body)], own: 'new', target: null, pluginTips: (_) => const [], turn: turn)?.say ?? '',
      }.toList();
      expect(named.any((say) => RegExp('Call log|Book club').hasMatch(say)), false);
      final routing = named.where((say) => RegExp('Work|new note', caseSensitive: false).hasMatch(say)).toList();
      expect(routing, ['Add a note to Work, …', 'New item for Work, …', 'Move this to Work']);
      for (final say in routing) {
        final take = LiveTake(const [groceries, work], const LiveTakeOptions(own: groceries));
        take.phrase(seg('First words.', 0, 900), 0);
        take.phrase(seg('${say.replaceFirst('…', 'call Sam')}.', 1000, 1900), 1000);
        take.close(2000);
        if (RegExp('move this', caseSensitive: false).hasMatch(say)) {
          expect(take.aim?.id, 'work', reason: say);
        } else {
          expect(take.result().bodies['work'], contains('Call Sam'), reason: say);
        }
      }
      expect(starters(noteTitle: 'Call log').send.map((tip) => tip.say), ['Make a list called … with …']);
    });
  });

  group('the tip for a pause', () {
    const groceries = TipNote(id: 'groceries', title: 'Groceries', body: '# Groceries\n\n- Eggs');
    const work = TipNote(id: 'work', title: 'Work', body: '# Work');
    final guide = TipNote(id: 'guide', title: 'Field guide', body: bookNoteBody('Field guide', ['Birds']));
    Tip? pause(int turn, {List<TipNote>? notes, String own = 'new', String? target, List<Tip> Function(String? recent)? pluginTips}) =>
        tipInPause(notes: notes ?? const [groceries, work], own: own, target: target, pluginTips: pluginTips ?? (_) => const [], turn: turn);

    /// Every tip a recording's pauses come round to: more turns than there are tips, so each is seen.
    List<String> all({List<TipNote>? notes, String own = 'new', String? target, List<Tip> Function(String? recent)? pluginTips}) => <String>{
          for (var turn = 0; turn < 120; turn += 1) pause(turn, notes: notes, own: own, target: target, pluginTips: pluginTips)?.say ?? '',
        }.toList();

    test('comes round the tips in turn, and back to the first after the last', () {
      final list = tips(noteTitle: 'Groceries', continuing: false);
      expect(pause(0), list[0]);
      expect(pause(1), list[1]);
      expect(pause(4), list[4]);
      expect(pause(list.length), list[0]);
      expect(pause(list.length + 2), list[2]);
    });

    test('names the most recent note that is not the one being written to, in the form its title allows', () {
      expect(all(), contains('Add … to Groceries'));
      final aimed = all(own: 'groceries', target: groceries.body);
      expect(aimed, contains('Add a note to Work, …'));
      expect(aimed.any((say) => say.contains('Groceries')), false);
    });

    test('teaches nothing for a book or a board', () {
      expect(all(notes: [groceries, guide]).any((say) => RegExp(r'\b(?:chapter|book)\b', caseSensitive: false).hasMatch(say)), false);
      // The book the most recent note: the tip names the next note, never the book.
      expect(all(notes: [guide, work]), contains('Add a note to Work, …'));
      expect(all(notes: [guide, work]).any((say) => say.contains('Field guide')), false);
      expect(all(target: '# Launch\n\n```board\nTo do:\nDoing:\n```').any((say) => say.contains('Doing')), false);
    });

    // No plugin gives a tip now; the seam stays, and is held here with one of a plugin's own making.
    test('adds the plugins’ own tips for the note it names, as the plugin wrote them', () {
      final asked = <String?>[];
      List<Tip> pluginTips(String? recent) {
        asked.add(recent);
        return const [Tip(say: 'Ring the bell', does: 'to try a plugin’s tip')];
      }

      final plain = all(pluginTips: pluginTips);
      expect(plain, contains('Ring the bell'));
      expect(asked[0], 'Groceries');
      expect(plain, contains('Add … to Groceries'));
      expect(plain.any((say) => say.startsWith('Hey Ghost')), false);
    });
  });
}
