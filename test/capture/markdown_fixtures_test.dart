import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/markdown.dart';
import 'package:ghost_md/capture/spoken/extras.dart';
import 'package:ghost_md/capture/spoken/fields.dart';
import 'package:ghost_md/capture/spoken/inline.dart';
import 'package:ghost_md/capture/spoken/lists.dart';
import 'package:ghost_md/capture/spoken/numbers.dart';

/// The spoken marks held against the web's own outputs, beyond the ported cases: `test/capture/fixtures/markdown.json`
/// is what the web's `renderNote` and its rule families answered for every script in the voice suite
/// (`voice-tests/suite.json`: each as the phone would commit it, titled and not, with the plugins' marks on and off,
/// and with its last line still being guessed), every run of phrases `capture/markdown.test.ts` speaks, and every
/// string in either, on its own. Written by a throwaway Node script that imports the web's modules as they are; not a
/// web test file.
void main() {
  final web = jsonDecode(File('test/capture/fixtures/markdown.json').readAsStringSync()) as Map<String, dynamic>;
  final today = web['today'] as String;
  final formats = [for (final format in (web['formats'] as List).cast<Map<String, dynamic>>()) SpokenFormat(word: format['word'] as String, delimiter: format['delimiter'] as String)];
  final titles = (web['titles'] as List).cast<String>();

  tearDown(() {
    setSpokenFormats(const []);
    setLinkTitles(const []);
  });

  test('renders every note as the web renders it', () {
    final notes = (web['notes'] as List).cast<Map<String, dynamic>>();
    expect(notes.length, greaterThan(2000));
    var wrong = 0;
    for (final note in notes) {
      final segments = [for (final s in (note['s'] as List).cast<List<dynamic>>()) Segment(text: s[0] as String, startMs: s[1] as int, endMs: s[2] as int)];
      setSpokenFormats(note['f'] == 1 ? formats : const []);
      setLinkTitles(note['l'] == 1 ? titles : const []);
      final out = renderNote(segments, note['p'] as String, RenderOptions(titled: note['t'] == 1, today: today));
      final said = segments.map((s) => s.text).toList();
      if (out.markdown != note['md'] || out.plain != note['plain'] || out.pendingFrom != note['from']) wrong += 1;
      expect(out.markdown, note['md'], reason: '$said partial ${note['p']} titled ${note['t']} formats ${note['f']} titles ${note['l']}');
      expect(out.plain, note['plain'], reason: '$said');
      expect(out.pendingFrom, note['from'], reason: '$said');
    }
    expect(wrong, 0);
  });

  test('reads every string as the web reads it, rule family by rule family', () {
    final each = (web['each'] as List).cast<Map<String, dynamic>>();
    expect(each.length, greaterThan(600));
    setLinkTitles(titles);
    for (final row in each) {
      final text = row['text'] as String;
      final one = [Segment(text: text, startMs: 0, endMs: 1000)];
      expect(spokenInlineMarkup(text, formats), row['inline'], reason: 'inline: $text');
      expect(spokenInlineMarkup(text, const []), row['bare'], reason: 'inline, no plugins: $text');
      expect(spokenExtras(text), row['extras'], reason: 'extras: $text');
      expect(splitSentences(text), row['sentences'], reason: 'sentences: $text');
      expect(toParagraphs(one), row['paragraphs'], reason: 'paragraphs: $text');
      expect(renderTranscript(one, 'and the'), row['transcript'], reason: 'transcript: $text');
      final list = enumeration(text);
      expect(list == null ? null : {'intro': list.intro, 'items': list.items}, row['list'], reason: 'enumeration: $text');
      expect(spokenAddress(text), row['address'], reason: 'address: $text');
      expect(spokenSlug(text), row['slug'], reason: 'slug: $text');
      expect(spokenNumber(text), row['number'], reason: 'number: $text');
      expect(spokenSum(text), row['sum'], reason: 'sum: $text');
      expect(spokenMaths(text), row['maths'], reason: 'maths: $text');
      expect(spokenScript(text), row['script'], reason: 'script: $text');
      final fields = spokenFields(text, today);
      expect({'words': fields.words, 'due': fields.due, 'priority': fields.priority, 'people': fields.people}, row['fields'], reason: 'fields: $text');
      expect(withSpokenFields(text, today), row['fielded'], reason: 'fielded: $text');
    }
  });
}
