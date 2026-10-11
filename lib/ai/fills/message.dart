/// What the model reads for a fill, and how a press is split into generations (docs/DESIGN.md §145, 5.2 to 5.5). A
/// port of `src/app/ai/fills/message.ts`. Pure, and pinned by a fixture the page's tests and the Rust bar both read
/// (src/app/ai/fills.fixture.json, copied to test/ai/fixtures), so what the Mac measures is what the phone sends.
///
/// Smaller is faster on the phone, and reading the note is most of a fill's time, so a fill reads the note's title
/// and the part its blank needs: its section, a cell's header and its own row (probe C: with only those, the Year of
/// The Remains of the Day came back right, and with another row under it, wrong), a list and the line above it, a
/// title's first two thousand characters. Other blanks are `___`, worked-out ones their answers, earlier fills their
/// words, and links their words, so the only `{?` in the message are the numbered ones. The front matter, other notes
/// and the plugins' context are never read, so "from this note" means this note.
///
/// Today's date is the first line, in fixed English: the probes whose examples the prompt carries ran with it, and a
/// phone in German still sends the string the Rust bar measured. The model is never trusted with it: dates are
/// code's.
///
/// What differs: the shapes. `ROOM` is the record [room]; an ask's `again` is an [Again]; `tight` is an `int`, 0, 1
/// or 2; [buildFill]'s options are named parameters. One thing is not carried over: for a language blank on a
/// table's last line with no row under it (`| Say | {?in Japanese}` ending the note) the page reads a line past the
/// note's end and throws; here that line is passed over and the message is built.
library;

import '../../core/blanks.dart';
import '../../core/front_matter.dart';
import '../../core/item_syntax.dart';
import 'prompts.dart';
import 'shape.dart';

/// An answer asked again: the old answer's words, written back as the question with `It is not: …` (7.2).
class Again {
  const Again({required this.words});

  final String words;

  @override
  bool operator ==(Object other) => other is Again && other.words == words;

  @override
  int get hashCode => words.hashCode;

  @override
  String toString() => 'Again($words)';
}

/// One thing a generation asks: a blank, or a filled answer asked again, and its shape (`Ask`). Two asks are the
/// same ask only when they are the same object, as on the page.
class Ask {
  const Ask({required this.blank, required this.info, this.again});

  /// Its span in the note: the blank's braces, or the whole filled mark for Ask again.
  final Blank blank;
  final ShapeInfo info;

  /// Asked again; null for a blank asked the first time.
  final Again? again;

  @override
  String toString() => 'Ask($blank, ${info.shape.name}${again == null ? '' : ', $again'})';
}

/// One generation, ready to send (`Built`).
class Built {
  const Built({required this.system, required this.prompt, required this.maxTokens, required this.numbers});

  final String system;
  final String prompt;
  final int maxTokens;

  /// The numbers each ask is written with, in the asks' order: several for an items blank, one a new item.
  final List<List<int>> numbers;

  @override
  String toString() => 'Built($maxTokens tokens, $numbers, $prompt)';
}

/// The most one generation may write, and the most it may read and write together: three quarters of the 8,192
/// window (`ROOM`).
const ({int output, int window}) room = (output: 512, window: 6144);

/// The least a generation is given, whatever its blanks' budgets add up to. The engine makes a window of the prompt,
/// the budget and 16 more, rounded up to 512, and refuses a prompt with under 64 tokens of it left
/// (src-tauri/src/llm/generate.rs `window`): measured on the Mac, a one-blank fill of 969 prompt tokens and 35 to
/// write was refused as too long for a 1,024 window. With 48 the window always has the 64. The model stops when it
/// has answered, so the floor costs nothing (`LEAST_BUDGET`).
const int leastBudget = 48;

const List<String> _weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const List<String> _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// "Monday 28 September 2026" on every phone, from two fixed lists of English names. The day is read on the
/// device's own calendar.
String modelDay(DateTime date) {
  final local = date.toLocal();
  return '${_weekdays[local.weekday % 7]} ${local.day} ${_months[local.month - 1]} ${local.year}';
}

final RegExp _cjk = RegExp(r'[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]', unicode: true);
final RegExp _latin = RegExp(r'[\p{Script=Latin}\p{N}\p{P}\p{S}\s]', unicode: true);

/// Tokens, estimated on the high side by script: Latin letters, digits and punctuation one for every four
/// characters, Han, kana and Hangul one each, any other script one for every two. Twelve Japanese scopes would
/// otherwise pass the window that twelve English ones fit.
int estimateTokens(String text) {
  var latin = 0;
  var cjk = 0;
  var other = 0;
  for (final rune in text.runes) {
    if (rune < 128) {
      latin += 1;
      continue;
    }
    final ch = String.fromCharCode(rune);
    if (_cjk.hasMatch(ch)) {
      cjk += 1;
    } else if (_latin.hasMatch(ch)) {
      latin += 1;
    } else {
      other += 1;
    }
  }
  return (latin / 4).ceil() + cjk + (other / 2).ceil();
}

// ---- the scope ------------------------------------------------------------------------------------------------------

final RegExp _heading = RegExp(r'^\s*(#{1,6})\s');
bool _isHeading(String line) => _heading.hasMatch(line);
int _levelOf(String line) => _heading.firstMatch(line)?.group(1)?.length ?? 7;

/// A line the model is never shown: a picture, a place, a film.
final RegExp _drawn = RegExp(r'^\s*(?:!\[[^\]]*\]\([^)]*\)|\[[^\]]*\]\(geo:[^)]*\)|\[!\[[^\]]*\]\([^)]*\)\]\([^)]*\))\s*$');
final RegExp _tableLine = RegExp(r'^\s*\|');

/// The line index an offset of the text is on.
int _lineIndexAt(String text, int offset) => '\n'.allMatches(text.substring(0, offset)).length;

/// The headings above a line, nearest first and each a level higher than the last: the section's chain.
List<int> _headingsAbove(List<String> lines, int index, int start) {
  final chain = <int>[];
  var level = 7;
  for (var at = index - 1; at >= start; at -= 1) {
    if (_isHeading(lines[at]) && _levelOf(lines[at]) < level) {
      chain.add(at);
      level = _levelOf(lines[at]);
      if (level == 1) break;
    }
  }
  return chain;
}

/// Lines around [index] within a span, up to [before] characters above it and [after] below, cut at line ends.
List<int> _around(List<String> lines, int index, int from, int to, int before, int after) {
  final out = [index];
  var used = 0;
  for (var at = index - 1; at >= from; at -= 1) {
    used += lines[at].length + 1;
    if (used > before) break;
    out.add(at);
  }
  used = 0;
  for (var at = index + 1; at < to; at += 1) {
    used += lines[at].length + 1;
    if (used > after) break;
    out.add(at);
  }
  return out;
}

/// The lines a blank's shape reads (5.2), [tight] cutting it again for a blank that will not fit alone.
List<int> _scopeOf(List<String> lines, int index, ShapeInfo info, int start, int tight) {
  if (tight == 2) return [index];
  var sectionStart = start;
  for (var at = index; at >= start; at -= 1) {
    if (_isHeading(lines[at])) {
      sectionStart = at;
      break;
    }
  }
  final level = sectionStart < lines.length && _isHeading(lines[sectionStart]) ? _levelOf(lines[sectionStart]) : 0;
  var sectionEnd = lines.length;
  for (var at = index + 1; at < lines.length; at += 1) {
    if (_isHeading(lines[at]) && (level == 0 || _levelOf(lines[at]) <= level)) {
      sectionEnd = at;
      break;
    }
  }
  List<int> section(int before, int after) {
    final size = sectionStart < sectionEnd ? lines.sublist(sectionStart, sectionEnd).join('\n').length : 0;
    if (size <= before + after && tight == 0) return [for (var at = sectionStart; at < sectionEnd; at += 1) at];
    return _around(lines, index, sectionStart, sectionEnd, tight != 0 ? 400 : before, tight != 0 ? 200 : after);
  }

  switch (info.shape) {
    case Shape.title:
      final out = <int>[];
      var used = 0;
      for (var at = start; at < lines.length; at += 1) {
        used += lines[at].length + 1;
        if (used > (tight != 0 ? 600 : 2000) && out.isNotEmpty) break;
        out.add(at);
      }
      return out;
    case Shape.summary:
      return section(1600, 400);
    case Shape.cell:
    case Shape.language:
      if (!_tableLine.hasMatch(lines[index])) return section(1000, 600);
      var top = index;
      while (top > start && _tableLine.hasMatch(lines[top - 1])) {
        top -= 1;
      }
      return [..._headingsAbove(lines, top, start), top, top + 1, index];
    case Shape.items:
      var top = index;
      while (top > start && listLead(lines[top - 1]) != null) {
        top -= 1;
      }
      var bottom = index;
      while (bottom + 1 < lines.length && listLead(lines[bottom + 1]) != null) {
        bottom += 1;
      }
      final out = [..._headingsAbove(lines, top, start)];
      if (top - 1 >= start && jsTrim(lines[top - 1]).isNotEmpty) out.add(top - 1);
      var used = 0;
      final list = <int>[];
      for (var at = bottom; at >= top; at -= 1) {
        used += lines[at].length + 1;
        if (used > (tight != 0 ? 600 : 1600) && at < index) break;
        list.add(at);
      }
      return [...out, ...list];
    case Shape.number:
    case Shape.line:
    case Shape.phrase:
      return section(1000, 600);
  }
}

final RegExp _linkWords = RegExp(r'(?<!!)\[([^\]\n]*)\]\((?:https?:|mailto:)[^)\s]*\)');
final RegExp _autolink = RegExp(r'<(?:https?:|mailto:)[^<>\s]*>');
final RegExp _bareAddress = RegExp(r'\bhttps?:\/\/[^\s<>()]+');
final RegExp _trailingBlanks = RegExp(r'[ \t]+$');

/// JavaScript's `slice` on a line: either end past the line is the line's end, and a start past the end is nothing.
String _slice(String line, int from, [int? to]) {
  final end = (to ?? line.length).clamp(0, line.length);
  final start = from.clamp(0, line.length);
  return start >= end ? '' : line.substring(start, end);
}

/// What the model is shown for one line: asked blanks numbered, the rest as words or `___`, links as their words.
String _renderLine(String line, int lineStart, Map<int, ({int to, String text})> marks) {
  final out = StringBuffer();
  var at = 0;
  final starts = marks.keys.where((k) => k >= lineStart && k < lineStart + line.length + 1).toList()..sort();
  for (final start in starts) {
    final mark = marks[start]!;
    out
      ..write(_slice(line, at, start - lineStart))
      ..write(mark.text);
    at = mark.to - lineStart;
  }
  out.write(_slice(line, at));
  return out.toString().replaceAllMapped(_linkWords, (m) => m.group(1)!).replaceAll(_autolink, '').replaceAll(_bareAddress, '').replaceFirst(_trailingBlanks, '');
}

final RegExp _threeNewlines = RegExp(r'\n{3,}');

/// The scope of every ask, merged in the note's order, rendered: the title line first, `(lines left out)` wherever
/// words were skipped. [write] says how an asked target is written: `{?1 question}` for the first two rungs,
/// `{?question}` for the third. [worked] gives a blank the app worked out its answer, to stand in its place.
String scopeText(String text, List<Ask> asks, String Function(Ask ask, int index) write, [String? Function(Blank blank)? worked, int tight = 0]) {
  final lines = text.split('\n');
  final start = frontMatterEnd(lines);
  final chosen = <int>{};
  for (final ask in asks) {
    for (final index in _scopeOf(lines, _lineIndexAt(text, ask.blank.from), ask.info, start, tight)) {
      // A table's one line at the very end of the note has no row under it to show: the page reads past the end here.
      if (index >= start && index < lines.length) chosen.add(index);
    }
  }
  final title = titleLineIndex(text);
  if (title >= 0) chosen.add(title);
  // What stands in for each blank and fill in the lines shown.
  final marks = <int, ({int to, String text})>{};
  for (var i = 0; i < asks.length; i += 1) {
    marks[asks[i].blank.from] = (to: asks[i].blank.to, text: write(asks[i], i));
  }
  for (final fill in fillsIn(text)) {
    marks.putIfAbsent(fill.from, () => (to: fill.to, text: fill.words));
  }
  for (final blank in blanksIn(text)) {
    marks.putIfAbsent(blank.from, () => (to: blank.to, text: worked?.call(blank) ?? '___'));
  }
  final offsets = <int>[];
  var offset = 0;
  for (final line in lines) {
    offsets.add(offset);
    offset += line.length + 1;
  }
  final out = <String>[];
  var last = -1;
  for (final index in chosen.toList()..sort()) {
    if (_drawn.hasMatch(lines[index])) continue;
    if (last >= 0 && index > last + 1) {
      final skipped = lines.sublist(last + 1, index);
      if (skipped.any((l) => jsTrim(l).isNotEmpty && !_drawn.hasMatch(l))) {
        out.addAll(['', '(lines left out)', '']);
      } else if (skipped.isNotEmpty) {
        out.add('');
      }
    }
    out.add(_renderLine(lines[index], offsets[index], marks));
    last = index;
  }
  return jsTrim(out.join('\n').replaceAll(_threeNewlines, '\n\n'));
}

// ---- the message ----------------------------------------------------------------------------------------------------

/// The kinds probes' block for a shape, for the third rung (`SHAPE_BLOCKS`).
const Map<Shape, String> shapeBlocks = {
  Shape.phrase: fillAnswer,
  Shape.line: fillAnswer,
  Shape.number: fillNumber,
  Shape.title: fillTitle,
  Shape.summary: fillSummary,
  Shape.items: fillItems,
  Shape.cell: fillCell,
  Shape.language: fillTranslate,
};

/// The one number the third rung asks its one blank by.
const List<int> _one = [1];

/// The question an ask writes back: the blank's own, or an asked-again fill's from its bracket.
String _questionOf(Ask ask) => ask.blank.question;

final RegExp _numberMarker = RegExp(r'^(\d+)([.)])$');

/// The lead the next item of a list line takes: its indent, its mark or the next number, and an empty box for a
/// to-do.
String nextLead(String line, [int step = 1]) {
  final lead = listLead(line);
  if (lead == null) return '- ';
  final number = _numberMarker.firstMatch(lead.marker);
  final marker = number != null ? '${int.parse(number.group(1)!) + step}${number.group(2)}' : lead.marker;
  return '${lead.indent}$marker ${lead.done != null ? '[ ] ' : ''}';
}

/// An items blank asks one new item a numbered blank (docs/DESIGN.md §145, 5.8). Measured on the Mac, every model
/// gave one item where the first form asked for three under one number: the 4B "Sunglasses", the 9B "Cash, power
/// bank, and rain jacket" on one line. Asked as three blanks, one to a line, each is one item, as the models already
/// answer several blanks. The first carries the question, the rest are new lines of the list under it.
String _itemSlots(String text, Ask ask, List<int> numbers) {
  final lineStart = ask.blank.from <= 0 ? 0 : text.lastIndexOf('\n', ask.blank.from - 1) + 1;
  final lineEnd = text.indexOf('\n', ask.blank.to);
  final line = text.substring(lineStart, lineEnd == -1 ? text.length : lineEnd);
  // The blank is its item's whole words, so nothing on its line follows it but spaces.
  return [
    '{?${numbers.first} ${_questionOf(ask)}}',
    for (var i = 1; i < numbers.length; i += 1) '${nextLead(line, i)}{?${numbers[i]} }',
  ].join('\n');
}

/// The hint for an items blank asked as [numbers].
String _itemsHint(List<int> numbers) {
  if (numbers.length == 1) return 'Blank ${numbers[0]} is a whole item of the list it is in.';
  final which = numbers.length == 2 ? '${numbers[0]} and ${numbers[1]}' : '${numbers.first} to ${numbers.last}';
  return 'Blanks $which are whole items of the list they are in, each one new.';
}

/// The third rung's words after `Fill {?…}`: a cell named in words, and an items blank's count.
String _fillPhrase(ShapeInfo info) {
  if (info.shape == Shape.cell && info.cell != null) return ', the ${info.cell!.header} of ${info.cell!.row}.';
  if (info.shape == Shape.language && info.cell != null) return ', ${info.cell!.row} in ${info.language!.name}.';
  if (info.shape == Shape.items) return '. Give ${info.count}.';
  return '.';
}

/// The generation for these asks at this rung: its system prompt, its message and its budget (5.3, 5.8). The first
/// two rungs number every blank and give each shape's hint; the third asks one blank the way the kinds probes did.
Built buildFill(String text, List<Ask> asks, {required Rung rung, required DateTime today, String? Function(Blank blank)? worked, int tight = 0}) {
  final header = 'Today is ${modelDay(today)}.';
  final budget = asks.fold<int>(0, (sum, ask) => sum + budgetOf(ask.info));
  final maxTokens = budget > leastBudget ? budget : leastBudget;
  final againLine = [
    for (final ask in asks)
      if (ask.again != null) 'It is not: ${ask.again!.words}.',
  ];
  if (rung == 3) {
    final ask = asks[0];
    final written = '{?${_questionOf(ask)}}';
    final scope = scopeText(text, [ask], (_, _) => written, worked, tight);
    final last = [...againLine, 'Fill $written${_fillPhrase(ask.info)}'].join('\n');
    return Built(system: '$fillCore\n\n${shapeBlocks[ask.info.shape]}', prompt: '$header\n\nThe note:\n$scope\n\n$last', maxTokens: maxTokens, numbers: [_one]);
  }
  // Each ask's numbers: one, or one an item for an items blank.
  final numbers = <List<int>>[];
  var next = 1;
  for (final ask in asks) {
    final size = ask.info.shape == Shape.items ? ask.info.count : 1;
    numbers.add([for (var i = 0; i < size; i += 1) next + i]);
    next += size;
  }
  final scope = scopeText(text, asks, (ask, i) => ask.info.shape == Shape.items ? _itemSlots(text, ask, numbers[i]) : '{?${numbers[i][0]} ${_questionOf(ask)}}', worked, tight);
  final hints = <String>[];
  for (var i = 0; i < asks.length; i += 1) {
    final hint = asks[i].info.shape == Shape.items ? _itemsHint(numbers[i]) : hintFor(numbers[i][0], asks[i].info);
    if (hint != null) hints.add(hint);
  }
  final total = next - 1;
  final answer = total == 1 ? 'Answer blank 1.' : 'Answer blanks 1 to $total.';
  final parts = [header, 'The note:\n$scope'];
  if (hints.isNotEmpty) parts.add(hints.join('\n'));
  parts.add([...againLine, answer].join('\n'));
  return Built(system: fillPrompt, prompt: parts.join('\n\n'), maxTokens: maxTokens, numbers: numbers);
}

/// Whether a generation fits the room: its budget, and the prompt, the message and the budget in the window.
bool fits(Built built) => built.maxTokens <= room.output && fillPromptTokens + estimateTokens(built.prompt) + built.maxTokens <= room.window;

/// One generation of a press: which asks, and how much of the note it reads (`Generation`).
class Generation {
  const Generation({required this.asks, required this.tight});

  final List<Ask> asks;

  /// 0 for the whole scope, 1 for a cut one, 2 for the blank's line alone.
  final int tight;

  @override
  String toString() => 'Generation($asks, tight $tight)';
}

/// A press split into generations by the rung and the room (5.5, 5.8): at rung 1 blanks share a generation in the
/// note's order while it fits, at rungs 2 and 3 each has its own, the third grouped by shape so each block's
/// snapshot stays warm. A blank that will not fit alone has its scope cut, then its line alone.
List<Generation> fillPlan(String text, List<Ask> asks, Rung rung, DateTime today) {
  // In the note's order, asks at one place keeping the order they came in, as JavaScript's sort keeps them.
  final order = [for (var i = 0; i < asks.length; i += 1) i]..sort((a, b) => asks[a].blank.from != asks[b].blank.from ? asks[a].blank.from - asks[b].blank.from : a - b);
  final sorted = [for (final i in order) asks[i]];
  Generation alone(Ask ask) {
    for (final tight in const [0, 1, 2]) {
      if (fits(buildFill(text, [ask], rung: rung, today: today, tight: tight))) return Generation(asks: [ask], tight: tight);
    }
    return Generation(asks: [ask], tight: 2);
  }

  if (rung == 2) return sorted.map(alone).toList();
  if (rung == 3) {
    final shapes = <Shape>[];
    for (final ask in sorted) {
      if (!shapes.contains(ask.info.shape)) shapes.add(ask.info.shape);
    }
    return [
      for (final shape in shapes)
        for (final ask in sorted)
          if (ask.info.shape == shape) alone(ask),
    ];
  }
  final plan = <Generation>[];
  var group = <Ask>[];
  for (final ask in sorted) {
    final next = [...group, ask];
    if (group.isNotEmpty && !fits(buildFill(text, next, rung: rung, today: today))) {
      plan.add(group.length == 1 ? alone(group[0]) : Generation(asks: group, tight: 0));
      group = [ask];
    } else {
      group = next;
    }
  }
  if (group.isNotEmpty) plan.add(group.length == 1 ? alone(group[0]) : Generation(asks: group, tight: 0));
  return plan;
}
