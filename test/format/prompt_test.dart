// A port of src/app/format/prompt.test.ts, and the proof that the prompts here are the web's and the phone's.
//
// The web's test reads prompt.ts's own source to show each recording prompt is a plain `String.raw` literal the
// Mac's Rust test can copy by name. Here that is an equality: every prompt constant in format/prompt.dart against
// the literal in the web's source, and the recording prompts, the templates and the numbers against what the phone's
// own write-up compiles in (src-tauri/src/write_up.rs) and the fixtures both sides read. The web checkout is looked
// for at GLYPH_REPO_DIR, then tauri/, then Matt's path; where it is not there those checks are skipped, and say so.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/item_syntax.dart' show jsTrim;
import 'package:ghost_md/format/modes.dart';
import 'package:ghost_md/format/prompt.dart';

/// The web app's checkout, or null where there is none.
Directory? webRepo() {
  for (final at in [Platform.environment['GLYPH_REPO_DIR'], 'tauri', '/Users/matt/Development/Apps/glyph/tauri']) {
    if (at != null && File('$at/src/app/format/prompt.ts').existsSync()) return Directory(at);
  }
  return null;
}

/// A file of the web checkout as text, or null (and the test marked skipped) where the checkout or the file is not there.
String? webFile(String path) {
  final repo = webRepo();
  final file = repo == null ? null : File('${repo.path}/$path');
  if (file == null || !file.existsSync()) {
    markTestSkipped('The web app’s $path is not on this machine (looked at GLYPH_REPO_DIR, tauri/ and /Users/matt/Development/Apps/glyph/tauri): the equality with it was not checked.');
    return null;
  }
  return file.readAsStringSync();
}

/// A `String.raw` literal of a page file by its constant's name, as `page_prompt_in` (src-tauri/src/llm/tests.rs) and
/// the web's own test read it: from the opener to the next backtick, trimmed.
String pageLiteral(String source, String name) {
  final opener = '$name = String.raw`';
  final found = source.indexOf(opener);
  expect(found, greaterThanOrEqualTo(0), reason: '$name is a String.raw literal');
  final start = found + opener.length;
  return jsTrim(source.substring(start, source.indexOf('`', start)));
}

/// A constant of write_up.rs's `prompts` module: a raw string `r#"…"#` or a plain one with no escapes in it.
String rustPrompt(String source, String name) {
  final raw = RegExp('pub const $name: &str = r#"([\\s\\S]*?)"#;').firstMatch(source);
  if (raw != null) return raw.group(1)!;
  final plain = RegExp('pub const $name: &str = "([^"\\\\]*)";').firstMatch(source);
  expect(plain, isNotNull, reason: 'write_up.rs holds prompts::$name as a literal with no escapes');
  return plain!.group(1)!;
}

int rustInt(String digits) => int.parse(digits.replaceAll('_', ''));

/// The web's name of every prompt, and the constant here.
const Map<String, String> prompts = {
  'SYSTEM_PROMPT': systemPrompt,
  'SUMMARIZE_PROMPT': summarizePrompt,
  'ENHANCE_PROMPT': enhancePrompt,
  'GIST_PROMPT': gistPrompt,
  'RECORDING_SUMMARY_PROMPT': recordingSummaryPrompt,
  'RECORDING_NOTES_PROMPT': recordingNotesPrompt,
  'PIECE_CONTEXT': pieceContext,
  'NOTES_CONTEXT': notesContext,
};

void main() {
  group('the recording prompts', () {
    test('ask for a box only on the person recording’s own to-dos, and can be read by name from the Mac’s test', () {
      for (final prompt in [recordingSummaryPrompt, recordingNotesPrompt]) {
        expect(prompt.startsWith('You are the editor inside Ghost.md'), isTrue);
        expect(prompt, contains('"- [ ] "'));
        expect(prompt, contains('Never a task item'));
        expect(prompt, contains('[the words](link-1)'));
      }
      expect(recordingSummaryPrompt, contains('Decided: '));
      expect(recordingSummaryPrompt, contains('no numbered lists'));
      expect(recordingSummaryPrompt.endsWith('no code fence around it.'), isTrue);
      // The rule for other people's actions sits with the points, where the example puts "- Sam: the press list."
      final points = recordingSummaryPrompt.split('\n').firstWhere((line) => line.contains('three to eight points'));
      expect(points, contains("Other people's actions are points, with the name first"));
      // The web reads its own source here; the port's equality with that source is the group below.
      final source = webFile('src/app/format/prompt.ts');
      if (source == null) return;
      expect(pageLiteral(source, 'RECORDING_SUMMARY_PROMPT'), recordingSummaryPrompt);
      expect(pageLiteral(source, 'RECORDING_NOTES_PROMPT'), recordingNotesPrompt);
    });

    test('keep the two context lines as templates the phone’s own write-up can read by name and fill the same way', () {
      expect(fill(pieceContext, {'n': 2, 'm': 5}), 'Part 2 of 5 of one recording.');
      // The page's `(41230).toLocaleString('en')`.
      expect(fill(notesContext, {'words': '41,230'}), contains('about 41,230 words'));
      // A slot the values do not name is left as it is, and a name that is not a slot is not a slot.
      expect(fill('{n} of {m} {x}', {'n': 1}), '1 of {m} {x}');
      final source = webFile('src/app/format/prompt.ts');
      if (source == null) return;
      expect(pageLiteral(source, 'PIECE_CONTEXT'), pieceContext);
      expect(pageLiteral(source, 'NOTES_CONTEXT'), notesContext);
    });

    test('give a summary a sixth of the transcript and a piece’s notes a quarter of the piece, within their floors and ceilings', () {
      expect(recordingSummaryBudget(100), 200);
      expect(recordingSummaryBudget(20000), (5000 / 6).ceil() + 96);
      expect(recordingSummaryBudget(400000), 1024);
      expect(recordingNotesBudget(100), 128);
      expect(recordingNotesBudget(4000), 1000 ~/ 4 + 64);
      expect(recordingNotesBudget(100000), 512);
    });
  });

  group('the prompts', () {
    test('has one per mode, each keeping links as tokens and asking for markdown alone', () {
      for (final mode in modes) {
        final prompt = promptFor(mode.id);
        expect(prompt.startsWith('You are the editor inside Ghost.md'), isTrue);
        expect(prompt, contains('[the words](link-1)'));
        expect(prompt.endsWith('no code fence around it.'), isTrue);
      }
      expect(promptFor(RunKind.format), systemPrompt);
      expect(promptFor(RunKind.summarize), summarizePrompt);
      expect(promptFor(RunKind.enhance), enhancePrompt);
      expect({systemPrompt, summarizePrompt, enhancePrompt}.length, 3);
    });

    test('tells every prompt that knows the table’s token of the place’s and the video’s too', () {
      final told = [systemPrompt, summarizePrompt, enhancePrompt].where((prompt) => prompt.contains('![table-1](table)')).toList();
      expect(told, hasLength(3));
      for (final prompt in told) {
        expect(prompt, contains('![place-1](place)'));
        expect(prompt, contains('![video-1](video)'));
      }
      // A summary may leave one out; the others copy it where it was.
      expect(summarizePrompt, contains('leave it out of the summary, or copy the line exactly if it is the point of the note'));
      expect(systemPrompt, matches(RegExp(r'!\[video-1\]\(video\): copied exactly, on its own line, where it was\. Never describe it\.')));
    });

    test('gives a summary less room than the note and an enhancement more', () {
      const chars = 2000; // about 500 tokens
      expect(budgetFor(RunKind.format, chars), outputBudget(chars));
      expect(budgetFor(RunKind.summarize, chars), lessThan(budgetFor(RunKind.format, chars)));
      expect(budgetFor(RunKind.enhance, chars), greaterThan(budgetFor(RunKind.format, chars)));
      // Floors for a tiny note, ceilings for a huge one.
      expect(budgetFor(RunKind.summarize, 10), 160);
      expect(budgetFor(RunKind.enhance, 10), 512);
      expect(budgetFor(RunKind.summarize, 100000), 768);
      expect(budgetFor(RunKind.enhance, 100000), 4096);
    });
  });

  group('the prompts are the web’s, byte for byte', () {
    test('every prompt constant equals its String.raw literal in src/app/format/prompt.ts, and none is left out', () {
      final source = webFile('src/app/format/prompt.ts');
      if (source == null) return;
      // Every `String.raw` literal the file declares is one of the eight held here.
      final declared = RegExp(r'export const (\w+) = String\.raw`').allMatches(source).map((m) => m.group(1)!).toList();
      expect(declared, prompts.keys.toList());
      for (final MapEntry(key: name, value: prompt) in prompts.entries) {
        final opener = '$name = String.raw`';
        final start = source.indexOf(opener) + opener.length;
        final literal = source.substring(start, source.indexOf('`', start));
        // Untrimmed too: a literal with a blank edge would be a different prompt on the page than the Mac measures.
        expect(prompt, literal, reason: name);
        expect(prompt, pageLiteral(source, name), reason: name);
        // `String.raw` and a Dart raw string agree only where nothing is built in.
        expect(literal, isNot(contains(r'${')), reason: name);
      }
    });

    test('the temperature and the budgets’ sums are the web’s', () {
      final source = webFile('src/app/format/prompt.ts');
      if (source == null) return;
      expect(double.parse(RegExp(r'export const TEMPERATURE = ([\d.]+);').firstMatch(source)!.group(1)!), temperature);
      // Each budget's line, as the page writes it, read for its numbers and worked again here.
      List<int> numbers(String pattern) => RegExp(pattern).firstMatch(source)!.groups([1, 2, 3, 4]).map((n) => int.parse(n!)).toList();
      final summary = numbers(r'return Math\.min\((\d+), Math\.max\((\d+), Math\.ceil\(tokens / (\d+)\) \+ (\d+)\)\);\n\}\n\n/\*\* How much room the notes');
      final notes = numbers(r'return Math\.min\((\d+), Math\.max\((\d+), Math\.ceil\(tokens / (\d+)\) \+ (\d+)\)\);\n\}\n\n/\*\* The prompt for a mode');
      final output = numbers(r'return Math\.min\((\d+), Math\.max\((\d+), noteTokens \* (\d+) \+ (\d+)\)\);\n\}');
      final summarize = numbers(r"'summarize'\) return Math\.min\((\d+), Math\.max\((\d+), Math\.ceil\(noteTokens / (\d+)\) \+ (\d+)\)\);");
      final enhance = numbers(r"'enhance'\) return Math\.min\((\d+), Math\.max\((\d+), noteTokens \* (\d+) \+ (\d+)\)\);");
      for (final chars in [0, 1, 3, 4, 5, 10, 100, 399, 2000, 4000, 12000, 20000, 41230, 100000, 400000]) {
        final tokens = (chars / 4).ceil();
        int within(List<int> n, int room) => room.clamp(n[1], n[0]);
        expect(recordingSummaryBudget(chars), within(summary, (tokens / summary[2]).ceil() + summary[3]), reason: 'recordingSummaryBudget($chars)');
        expect(recordingNotesBudget(chars), within(notes, (tokens / notes[2]).ceil() + notes[3]), reason: 'recordingNotesBudget($chars)');
        expect(outputBudget(chars), within(output, tokens * output[2] + output[3]), reason: 'outputBudget($chars)');
        expect(budgetFor(RunKind.format, chars), outputBudget(chars));
        expect(budgetFor(RunKind.summarize, chars), within(summarize, (tokens / summarize[2]).ceil() + summarize[3]), reason: 'budgetFor(summarize, $chars)');
        expect(budgetFor(RunKind.enhance, chars), within(enhance, tokens * enhance[2] + enhance[3]), reason: 'budgetFor(enhance, $chars)');
      }
    });
  });

  group('the prompts are the phone’s own write-up’s', () {
    test('the four the write-up compiles in (src-tauri/src/write_up.rs `prompts`) equal the constants here', () {
      final source = webFile('src-tauri/src/write_up.rs');
      if (source == null) return;
      expect(rustPrompt(source, 'SUMMARY'), recordingSummaryPrompt);
      expect(rustPrompt(source, 'NOTES'), recordingNotesPrompt);
      expect(rustPrompt(source, 'PIECE'), pieceContext);
      expect(rustPrompt(source, 'PARTS'), notesContext);
    });

    test('its `fill` and the one here build the same lines from the same templates', () {
      final source = webFile('src-tauri/src/write_up.rs');
      if (source == null) return;
      // What write_up.rs's own test (`the_prompt_helpers_twin_the_pages`) asserts of its compiled-in copies.
      expect(source, contains(r'assert_eq!(fill(prompts::PIECE, &[("n", "2"), ("m", "5")]), "Part 2 of 5 of one recording.");'));
      expect(fill(rustPrompt(source, 'PIECE'), {'n': '2', 'm': '5'}), 'Part 2 of 5 of one recording.');
      expect(fill(rustPrompt(source, 'PARTS'), {'words': '41,230'}), fill(notesContext, {'words': '41,230'}));
    });

    test('the numbers it falls back to (`Config::read`) are the temperature here and the web’s piece rule', () {
      final source = webFile('src-tauri/src/write_up.rs');
      if (source == null) return;
      final heat = RegExp(r'temperature: if raw\.temperature <= 0\.0 \{ ([\d.]+) \}').firstMatch(source);
      final onePass = RegExp(r'one_pass_chars: if raw\.one_pass_chars == 0 \{ ([\d_]+) \}').firstMatch(source);
      final piece = RegExp(r'piece_chars: if raw\.piece_chars == 0 \{ ([\d_]+) \}').firstMatch(source);
      expect([heat, onePass, piece], everyElement(isNotNull), reason: 'Config::read still fills its blanks where it did');
      expect(double.parse(heat!.group(1)!), temperature);

      // The piece rule's two numbers are the web's ai/summaryText.ts (ONE_PASS_CHARS, PIECE_CHARS), not this module's.
      final text = webFile('src/app/ai/summaryText.ts');
      if (text == null) return;
      final webOnePass = rustInt(RegExp(r'export const ONE_PASS_CHARS = ([\d_]+);').firstMatch(text)!.group(1)!);
      final webPiece = rustInt(RegExp(r'export const PIECE_CHARS = ([\d_]+);').firstMatch(text)!.group(1)!);
      expect(rustInt(onePass!.group(1)!), webOnePass);
      expect(rustInt(piece!.group(1)!), webPiece);
      // And the port's, once it is written (lib/ai/summary_text.dart is another worker's): read as text, so this file
      // compiles without it.
      final port = File('lib/ai/summary_text.dart');
      if (!port.existsSync()) return;
      final dart = port.readAsStringSync();
      final dartOnePass = RegExp(r'const int onePassChars = ([\d_]+);').firstMatch(dart);
      final dartPiece = RegExp(r'const int pieceChars = ([\d_]+);').firstMatch(dart);
      if (dartOnePass != null) expect(rustInt(dartOnePass.group(1)!), webOnePass);
      if (dartPiece != null) expect(rustInt(dartPiece.group(1)!), webPiece);
    });

    test('the config fixture its jobs read in their own test (src-tauri/src/jobs.rs) carries the same numbers', () {
      final source = webFile('src-tauri/src/jobs.rs');
      if (source == null) return;
      final fixture = RegExp(r'let json = r#"(\{"model":[^\n]*\})"#;').firstMatch(source);
      expect(fixture, isNotNull, reason: 'jobs.rs still reads a whole config in its test');
      final config = jsonDecode(fixture!.group(1)!) as Map<String, dynamic>;
      expect(config['temperature'], temperature);
      // The shape `JobConfig.toJson` (lib/ai/backend.dart) sends: the four prompts each in its place, by these names.
      expect((config['prompts'] as Map).keys, ['summary', 'notes', 'piece', 'parts']);
      expect(config.keys, ['model', 'prompts', 'onePassChars', 'pieceChars', 'temperature', 'writeUp', 'summaries']);
      final writeUp = webFile('src-tauri/src/write_up.rs');
      if (writeUp == null) return;
      expect(config['onePassChars'], rustInt(RegExp(r'one_pass_chars == 0 \{ ([\d_]+) \}').firstMatch(writeUp)!.group(1)!));
      expect(config['pieceChars'], rustInt(RegExp(r'piece_chars == 0 \{ ([\d_]+) \}').firstMatch(writeUp)!.group(1)!));
    });

    test('its budgets (`summary_budget`, `notes_budget`) are the budgets here, by its source and by the fixture both sides read', () {
      final source = webFile('src-tauri/src/write_up.rs');
      if (source == null) return;
      List<int> sum(String name) {
        final found = RegExp('pub fn $name\\(chars: usize\\) -> u32 \\{\\s*let tokens = chars\\.div_ceil\\((\\d+)\\);\\s*\\(tokens\\.div_ceil\\((\\d+)\\) \\+ (\\d+)\\)\\.clamp\\((\\d+), (\\d+)\\) as u32').firstMatch(source);
        expect(found, isNotNull, reason: '$name is still the sum it was');
        return found!.groups([1, 2, 3, 4, 5]).map((n) => int.parse(n!)).toList();
      }

      final summary = sum('summary_budget');
      final notes = sum('notes_budget');
      int rust(List<int> n, int chars) => (((chars / n[0]).ceil() / n[1]).ceil() + n[2]).clamp(n[3], n[4]);
      for (var chars = 0; chars <= 420000; chars += chars < 2000 ? 1 : 997) {
        expect(recordingSummaryBudget(chars), rust(summary, chars), reason: 'the summary’s for $chars');
        expect(recordingNotesBudget(chars), rust(notes, chars), reason: 'a piece’s notes’ for $chars');
      }

      final twins = webFile('src/app/ai/writeUpTwins.fixture.json');
      if (twins == null) return;
      final budgets = (jsonDecode(twins) as Map<String, dynamic>)['budgets'] as List;
      expect(budgets, isNotEmpty);
      for (final budget in budgets.cast<Map<String, dynamic>>()) {
        final chars = budget['chars'] as int;
        expect([recordingSummaryBudget(chars), recordingNotesBudget(chars)], [budget['summary'], budget['notes']], reason: '$chars');
      }
    });
  });
}
