// Snippets (lib/core/snippets.dart; Matt, 2026-10-27: "build ... snippets"): what a trigger is, what its words become
// at a moment, what Settings refuses, and how the list is kept with the preferences and merged between devices.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/locale_dates.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/snippets.dart';
import 'package:ghost_md/sync/prefs.dart';

final DateTime now = DateTime(2026, 10, 27, 16, 5);

const Snippet sig = Snippet(id: 's1', trigger: ';sig', text: 'Matt\n{cursor}');
const Snippet addr = Snippet(id: 's2', trigger: ';addr2', text: '1 Main St');

void main() {
  tearDown(() => toldLocale = null);

  group('a trigger', () {
    test('is a semicolon and one to 24 letters or digits', () {
      for (final good in [';sig', ';a', ';addr2', ';X9', ';${'a' * 24}']) {
        expect(snippetTriggerRule.hasMatch(good), isTrue, reason: good);
      }
      for (final bad in ['sig', ';', '; sig', ';si g', ';sig!', ';é', ';${'a' * 25}', ';;sig']) {
        expect(snippetTriggerRule.hasMatch(bad), isFalse, reason: bad);
      }
    });

    test('is found at the end of the words before the caret, on its own, whatever its case', () {
      expect(triggerBefore(';sig', [sig])?.from, 0);
      expect(triggerBefore('Thanks, ;sig', [sig])?.from, 8);
      expect(triggerBefore('Thanks, ;SIG', [sig])?.snippet, sig);
      expect(triggerBefore('Lunch\t;addr2', [sig, addr])?.snippet, addr);
      // Inside a word, after punctuation, or a trigger that is no snippet: nothing.
      expect(triggerBefore('x;sig', [sig]), isNull);
      expect(triggerBefore('(;sig', [sig]), isNull);
      expect(triggerBefore(';sigs', [sig]), isNull);
      expect(triggerBefore(';sig', const []), isNull);
    });
  });

  group('its words', () {
    test('fill {date}, {time} and {datetime} at the moment, in the phone’s order', () {
      final made = expandSnippet('{date} at {time}; {datetime}', now);
      expect(made.text, '27 October 2026 at 16:05; 27 October 2026, 16:05');
      expect(made.caret, made.text.length);
      toldLocale = DateLocale.enUS;
      expect(expandSnippet('{date}', now).text, 'October 27, 2026');
    });

    test('place the caret at the first {cursor}, and take every one out', () {
      final made = expandSnippet('Dear {cursor},\n\n{cursor}Matt', now);
      expect(made.text, 'Dear ,\n\nMatt');
      expect(made.caret, 5);
    });

    test('leave anything else in braces as it was typed, a template\'s {{date}} among it', () {
      expect(expandSnippet('{?the capital of France} {image: a cat} {{date}} {Date}', now).text, '{?the capital of France} {image: a cat} {{date}} {Date}');
    });

    test('read on one short line in a row', () {
      expect(snippetPreviewLine(const Snippet(id: 'x', trigger: ';x', text: 'Matt\n  Ghost.md\n{date}'), now), 'Matt · Ghost.md · 27 October 2026');
      expect(snippetPreviewLine(const Snippet(id: 'x', trigger: ';x', text: 'abcdefghij'), now, most: 5), 'abcd…');
    });
  });

  test('Settings says what is wrong, and nothing where nothing is', () {
    expect(snippetProblem('', 'x', const []), 'Give it a trigger, like ;sig.');
    expect(snippetProblem('sig', 'x', const []), 'A trigger starts with a semicolon, like ;sig.');
    expect(snippetProblem(';', 'x', const []), 'After the semicolon, letters and digits only, at most 24.');
    expect(snippetProblem(';s g', 'x', const []), 'After the semicolon, letters and digits only, at most 24.');
    expect(snippetProblem(';SIG', 'x', const [sig]), ';SIG is already a snippet.');
    expect(snippetProblem(';sig', '  \n', const []), 'Write what ;sig becomes.');
    expect(snippetProblem(' ;sig ', 'Matt', const [addr]), isNull);
    expect(newSnippetId(const [sig], now), startsWith('s-'));
  });

  group('kept with the preferences', () {
    test('a device that chose nothing has ;date and ;time, and a list emptied stays empty', () {
      expect(Preferences.defaults.snippets.map((each) => each.trigger), [';date', ';time']);
      expect(Preferences.fromJson(const <String, Object?>{}).snippets, defaultSnippets);
      expect(Preferences.fromJson({'snippets': <Object?>[]}).snippets, isEmpty);
      // The defaults are not written, so a device that chose nothing keeps the web's stored shape; an empty list is.
      expect(Preferences.defaults.toJson().containsKey('snippets'), isFalse);
      expect(Preferences.defaults.copyWith(snippets: const []).toJson()['snippets'], isEmpty);
      expect(Preferences.fromJson(Preferences.defaults.copyWith(snippets: const []).toJson()).snippets, isEmpty);
    });

    test('go out as a list of id, trigger and words, and come back the same', () {
      final prefs = Preferences.defaults.copyWith(snippets: const [sig, addr]);
      final json = jsonDecode(jsonEncode(prefs.toJson())) as Map<String, Object?>;
      expect(json['snippets'], [
        {'id': 's1', 'trigger': ';sig', 'text': 'Matt\n{cursor}'},
        {'id': 's2', 'trigger': ';addr2', 'text': '1 Main St'},
      ]);
      expect(Preferences.fromJson(json).snippets, const [sig, addr]);
      expect(Preferences.fromJson(json), prefs);
      expect(Preferences.fromJson(json).more.containsKey('snippets'), isFalse);
    });

    test('from a half-written store, only whole entries, each id once', () {
      final read = Preferences.fromJson({
        'snippets': [
          {'id': 's1', 'trigger': ';sig', 'text': 'Matt'},
          {'id': 's1', 'trigger': ';again', 'text': 'twice'},
          {'id': 's3', 'trigger': ';x'},
          'nonsense',
          {'id': 4, 'trigger': ';y', 'text': 'y'},
        ],
      }).snippets;
      expect(read, const [Snippet(id: 's1', trigger: ';sig', text: 'Matt')]);
      expect(Preferences.fromJson({'snippets': 'nonsense'}).snippets, defaultSnippets);
    });

    test('travel with the account, merged a snippet at a time where two devices changed them', () {
      expect(syncedPrefs, contains('snippets'));
      expect(pickSynced(Preferences.defaults.copyWith(snippets: const [sig]).toJson())['snippets'], [sig.toJson()]);
      final base = {'snippets': [sig.toJson()]};
      // Here ;sig's words changed; there ;addr2 was added.
      final mine = {'snippets': [sig.copyWith(text: 'M.').toJson()]};
      final theirs = {'snippets': [sig.toJson(), addr.toJson()]};
      expect(merged(base, mine, theirs)['snippets'], [sig.copyWith(text: 'M.').toJson(), addr.toJson()]);
      // One removed there and untouched here is gone.
      expect(merged(base, base, {'snippets': <Object?>[]})['snippets'], isEmpty);
    });
  });
}
