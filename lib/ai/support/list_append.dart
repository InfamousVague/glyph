/// "New item for AttackFM": putting items into a note's list, not at the bottom of the note. A port of the half of
/// `src/app/capture/listAppend.ts` the review's added lines need: [appendToList], [leaveNote], and what they read a
/// note's lists with.
///
/// A note's list is the last run of list lines in it (a to-do, a bullet or a numbered line, with any indented lines
/// that continue them). New items go on the end of that run in the run's own style: a numbered list the next number,
/// a bullet list its own bullet, and a to-do list a box after either, at the run's indent. A note with no list gets
/// one at its end, as to-dos when asked. Pure.
///
/// What differs: only this half is here. `linesAbove`, `semanticListKind`, `Placing` and `placeWords` are the
/// recorder's and come with the capture stage; this file belongs in lib/capture/list_append.dart then, and should
/// go when that one lands. A run's style is one class ([RunStyle]) with `number` saying which kind it is. The
/// answers are records. `today` defaults to the clock's day, as on the web.
library;

import '../../capture/append_body.dart';
import '../../core/days.dart';
import '../../core/front_matter.dart';
import '../../core/item_syntax.dart';
import '../../core/text.dart';
import 'spoken_fields.dart';

/// How a run's last top-level item is marked: its bullet or its next number, and whether it is a to-do.
class RunStyle {
  const RunStyle.bullet({required this.mark, required this.task}) : number = false, next = 0, delimiter = '';
  const RunStyle.number({required this.next, required this.delimiter, required this.task}) : number = true, mark = '';

  /// Whether the run is numbered (`kind: 'number'`) rather than bulleted.
  final bool number;
  final String mark;
  final int next;
  final String delimiter;
  final bool task;
}

/// One list in a note (`Run`).
class Run {
  const Run({required this.first, required this.last, required this.indent, required this.style});

  /// Index of the run's first and last line.
  final int first;
  final int last;
  final String indent;
  final RunStyle style;
}

final RegExp _fence = RegExp(r'^\s*(`{3,}|~{3,})');
final RegExp _leadingSpace = RegExp(r'^\s+');
final RegExp _digit = RegExp(r'\d');
final RegExp _digits = RegExp(r'^\d+');

/// Every list in [lines], in order, from the end of the note's front matter: a key's value is never a list to put
/// words in.
List<Run> runsOf(List<String> lines) {
  final runs = <Run>[];
  var i = frontMatterEnd(lines);
  String? fence;
  while (i < lines.length) {
    final line = lines[i];
    final marker = _fence.firstMatch(line)?.group(1);
    if (marker != null) {
      if (fence == null) {
        fence = marker[0];
      } else if (marker[0] == fence) {
        fence = null;
      }
      i += 1;
      continue;
    }
    if (fence != null) {
      i += 1;
      continue;
    }
    final head = listLead(line);
    if (head == null) {
      i += 1;
      continue;
    }
    final indent = head.indent;
    final first = i;
    var last = i;
    var style = styleOf(head);
    i += 1;
    while (i < lines.length) {
      final line = lines[i];
      final item = listLead(line);
      if (item != null && item.indent.length >= indent.length) {
        if (item.indent.length == indent.length) style = styleOf(item);
        last = i;
        i += 1;
      } else if (jsTrim(line).isNotEmpty && (_leadingSpace.firstMatch(line)?.group(0)!.length ?? 0) > indent.length) {
        // An indented line under an item continues it.
        last = i;
        i += 1;
      } else {
        break;
      }
    }
    runs.add(Run(first: first, last: last, indent: indent, style: style));
  }
  return runs;
}

/// Words that say nothing of which list: the small ones, and the verbs a thing to do starts with.
final Set<String> _quiet =
    'the and for with that this from into onto about have has was were are its our your their them then than just also need needs should will would could can call book buy email send pick make check clean take find sort look ring text order tell remember finish write read bring sure want'
        .split(' ')
        .toSet();

final RegExp _linkTarget = RegExp(r'\]\([^)]*\)');
final RegExp _notLetters = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// A text's stems: the first six letters of each word of four or more that says something.
Set<String> _stems(String text) => text
    .toLowerCase()
    .replaceAll(_linkTarget, ' ')
    .split(_notLetters)
    .where((word) => word.length >= 4 && !_quiet.contains(word))
    .map((word) => word.length > 6 ? word.substring(0, 6) : word)
    .toSet();

final RegExp _heading = RegExp(r'^#{1,6}\s+(.+?)\s*#*\s*$');
final RegExp _titleLine = RegExp(r'^#\s');
final RegExp _labelEnd = RegExp(r':\s*$');

/// For each line, the heading it sits under, fence-aware, never the note's own title (its first line, as a heading).
List<String?> _headingsAbove(List<String> lines) {
  final out = <String?>[];
  final start = frontMatterEnd(lines);
  String? current;
  String? fence;
  var titled = false;
  for (var i = 0; i < lines.length; i += 1) {
    final line = lines[i];
    out.add(current);
    if (i < start) continue;
    final marker = _fence.firstMatch(line)?.group(1);
    if (marker != null) {
      if (fence == null) {
        fence = marker[0];
      } else if (marker[0] == fence) {
        fence = null;
      }
      continue;
    }
    if (fence != null || jsTrim(line).isEmpty) continue;
    final heading = _heading.firstMatch(line);
    if (heading != null && !titled && _titleLine.hasMatch(line)) {
      titled = true;
      continue;
    }
    titled = true;
    if (heading != null) current = heading.group(1)!;
  }
  return out;
}

/// A list's heading as its words go: the heading above it, or the "Label:" line just above it.
String? _headingOf(List<String> lines, Run run, List<String?> above) {
  for (var i = run.first - 1; i >= 0; i -= 1) {
    final line = jsTrim(lines[i]);
    if (line.isEmpty) continue;
    if (_labelEnd.hasMatch(line) && listLead(line) == null) return line.replaceFirst(_labelEnd, '');
    break;
  }
  return above[run.first];
}

/// A note's list, with the words that say what goes in it: its heading and its items (`ListOf`).
typedef ListOf = ({Run run, String? heading, String items});

/// The lists of [lines] ([runsOf], or some of them), each with its heading and its items' words.
List<ListOf> listsOf(List<String> lines, List<Run> runs) {
  final above = _headingsAbove(lines);
  return <ListOf>[for (final run in runs) (run: run, heading: _headingOf(lines, run, above), items: lines.sublist(run.first, run.last + 1).join(' '))];
}

/// How well [text] fits a list: the stems it shares with the list's heading count twice, with its items once.
int fitOf(String text, {required String? heading, required String items}) {
  final wanted = _stems(text);
  final titled = _stems(heading ?? '');
  final listed = _stems(items);
  var score = 0;
  for (final stem in wanted) {
    score += (titled.contains(stem) ? 2 : 0) + (listed.contains(stem) ? 1 : 0);
  }
  return score;
}

/// The list [text] fits best, the first of any tied, and how well: -1 when it fits none of them.
({int index, int score}) bestList(List<ListOf> lists, String text) {
  var index = -1;
  var score = 0;
  for (var i = 0; i < lists.length; i += 1) {
    final fit = fitOf(text, heading: lists[i].heading, items: lists[i].items);
    if (fit > score) {
      score = fit;
      index = i;
    }
  }
  return (index: index, score: score);
}

/// Where words that fit no list go: the first to-do list with something still to do, or the last list.
int restingList(List<String> lines, List<ListOf> lists) {
  final open = lists.indexWhere((list) => list.run.style.task && lines.sublist(list.run.first, list.run.last + 1).any((line) => listLead(line)?.done == false));
  return open >= 0 ? open : lists.length - 1;
}

/// The list that [text] belongs in, when a note has more than one: the one whose heading (or "Label:" line) and
/// items share the most with it, the heading counting double; with nothing to go by, [restingList].
Run? _runFor(List<String> lines, List<Run> runs, String? text) {
  if (runs.isEmpty) return null;
  final lists = listsOf(lines, runs);
  final best = text != null && text.isNotEmpty && runs.length > 1 ? bestList(lists, text).index : -1;
  return runs[best >= 0 ? best : restingList(lines, lists)];
}

/// How an item's lead marks its list.
RunStyle styleOf(ListLead lead) {
  final task = lead.done != null;
  // A number's marker is its digits and then its `.` or `)`; a bullet's is the one character.
  if (_digit.hasMatch(lead.marker)) {
    final digits = _digits.firstMatch(lead.marker)?.group(0);
    return RunStyle.number(next: (digits == null ? 0 : int.parse(digits)) + 1, delimiter: lead.marker.substring(lead.marker.length - 1), task: task);
  }
  return RunStyle.bullet(mark: lead.marker, task: task);
}

final RegExp _itemEnd = RegExp(r'(?:\\?[\s.,;:])+$');

/// One item's text as a list line: first letter up, no closing full stop. A stop the model's words carried in
/// escaped (`\.`) goes with its backslash, which alone would end the line.
String itemText(String text) => capitalise(jsTrim(text).replaceFirst(_itemEnd, ''));

/// [body] with [items] on the end of its last list, or of the list [near] belongs in when it has several. [asTasks]
/// shapes a list that has to be started (a note with no list yet). Answers the new body and the lines added. An
/// item's due day, priority and person said at its end are written as its fields (spoken_fields.dart), counted from
/// [today].
({String body, List<String> added}) appendToList(String body, List<String> items, {bool asTasks = false, String? near, String? today}) {
  final day = today ?? isoDay(DateTime.now());
  final texts = items.map(itemText).where((text) => text.isNotEmpty).toList();
  if (texts.isEmpty) return (body: body, added: const <String>[]);
  final lines = body.split('\n');
  final run = _runFor(lines, runsOf(lines), near);

  if (run == null) {
    final added = <String>[for (final text in texts) withSpokenFields('${asTasks ? '- [ ] ' : '- '}$text', day)];
    return (body: appendBlock(body, added.join('\n')), added: added);
  }

  var number = run.style.number ? run.style.next : 0;
  final box = run.style.task ? '[ ] ' : '';
  final added = <String>[
    for (final text in texts)
      withSpokenFields(run.style.number ? '${run.indent}${number++}${run.style.delimiter} $box$text' : '${run.indent}${run.style.mark} $box$text', day),
  ];
  final next = <String>[...lines.sublist(0, run.last + 1), ...added, ...lines.sublist(run.last + 1)];
  return (body: next.join('\n'), added: added);
}

/// What a spoken note starts with that is not the note: "that", "to", "saying".
final RegExp _leadIn = RegExp(
  r'^\s*(?:(?:that\s+says|which\s+says|that\s+reads|to\s+say|saying)\s+)?(?:(?:that|to)\s+(?=\p{L}))?',
  caseSensitive: false,
  unicode: true,
);
final RegExp _quotes = RegExp(r'^["“]+|["”]+$');
final RegExp _space = RegExp(r'\s+');
final RegExp _sentenceBreak = RegExp(r'[.!?]+\s+');
final RegExp _sentenceEnd = RegExp(r'[.!?…]$');

/// A thing to do or a short point, rather than a paragraph: short, and one or two sentences.
bool _itemShaped(String text) {
  final words = text.split(_space).where((word) => word.isNotEmpty).length;
  final sentences = text.split(_sentenceBreak).where((part) => jsTrim(part).isNotEmpty).length;
  return words <= 30 && sentences <= 2;
}

/// [text] put where it belongs in [body]. A note with a list takes it as a new item of that list (the list it fits,
/// when there are several); a long thought, or a note with no list, takes it as its own paragraph at the end.
/// Answers the new body, the lines added and which it was: `into` is `list` or `paragraph`.
({String body, List<String> added, String into}) leaveNote(String body, String text, {bool asParagraph = false}) {
  final words = jsTrim(text.replaceFirst(_leadIn, '').replaceAll(_quotes, ''));
  if (words.isEmpty) return (body: body, added: const <String>[], into: 'paragraph');
  final lines = body.split('\n');
  // A short thing, on a note of lists, is an item; asked for as a paragraph, it is one, list or no list.
  if (!asParagraph && runsOf(lines).isNotEmpty && _itemShaped(words)) {
    final put = appendToList(body, <String>[words], near: words);
    return (body: put.body, added: put.added, into: 'list');
  }
  final sentence = capitalise(words);
  final line = _sentenceEnd.hasMatch(sentence) ? sentence : '$sentence.';
  return (body: appendBlock(body, line), added: <String>[line], into: 'paragraph');
}
