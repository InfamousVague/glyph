/// "New item for AttackFM": putting spoken items into a note's list, not at the bottom of the note. A port of
/// `src/app/capture/listAppend.ts`.
///
/// A note's list is the last run of list lines in it (a to-do, a bullet or a numbered line, with any indented lines
/// that continue them). New items go on the end of that run in the run's own style: a numbered list the next number,
/// a bullet list its own bullet, and a to-do list a box after either, at the run's indent. A note with no list gets
/// one at its end, as to-dos when the command said "task" or "to-do". Pure, so every shape of note is a test.
///
/// What differs: the shapes. A run's `style` is a sealed [RunStyle] ([RunStyleBullet], [RunStyleNumber]). What the
/// writers answer are records, `(body:, added:)` and `(body:, added:, into:)`, with `into` a [PlacedInto];
/// [bestList] answers `(index:, score:)`. [Placing]'s `how` is a [PlacingHow], [InstructionArea] an enum (null for
/// the web's `null`), and [semanticListKind] answers note_find.dart's `TitleKind`, as the web answers `titleKind`'s
/// own `'task' | 'bullet' | null`. [fitOf] takes the list's `heading` and `items` by name, where the web takes any
/// object that has the two. `Placing` is also the name of place.dart's union: import one of the two with `hide`.
library;

import '../core/days.dart';
import '../core/front_matter.dart';
import '../core/item_syntax.dart';
import '../core/note_text.dart' show noteTitle;
import '../core/text.dart';
import 'append_body.dart';
import 'note_find.dart' show TitleKind, titleKind;
import 'spoken/fields.dart';
import 'spoken/lists.dart';
import 'spoken_list.dart' show spokenSentenceItems;

/// How a run's last top-level item is marked: its bullet or its next number, and whether it is a to-do. A `* [ ]`
/// list grows by `* [ ]` lines and a `1. [ ]` list by numbered to-dos, as every reader of the grammar
/// (core/item_syntax.dart) takes them for to-dos too (`Run['style']`).
sealed class RunStyle {
  const RunStyle({required this.task});
  final bool task;
}

/// A bullet list's (`kind: 'bullet'`).
class RunStyleBullet extends RunStyle {
  const RunStyleBullet({required this.mark, required super.task});
  final String mark;

  @override
  bool operator ==(Object other) => other is RunStyleBullet && other.mark == mark && other.task == task;

  @override
  int get hashCode => Object.hash(mark, task);

  @override
  String toString() => '{kind: bullet, mark: $mark, task: $task}';
}

/// A numbered list's (`kind: 'number'`).
class RunStyleNumber extends RunStyle {
  const RunStyleNumber({required this.next, required this.delimiter, required super.task});
  final int next;
  final String delimiter;

  @override
  bool operator ==(Object other) => other is RunStyleNumber && other.next == next && other.delimiter == delimiter && other.task == task;

  @override
  int get hashCode => Object.hash(next, delimiter, task);

  @override
  String toString() => '{kind: number, next: $next, delimiter: $delimiter, task: $task}';
}

/// One list of a note (`Run`).
class Run {
  const Run({required this.first, required this.last, required this.indent, required this.style});

  /// Index of the run's first and last line.
  final int first;
  final int last;
  final String indent;
  final RunStyle style;

  @override
  bool operator ==(Object other) => other is Run && other.first == first && other.last == last && other.indent == indent && other.style == style;

  @override
  int get hashCode => Object.hash(first, last, indent, style);

  @override
  String toString() => '{first: $first, last: $last, indent: $indent, style: $style}';
}

final RegExp _fenceMarker = RegExp(r'^\s*(`{3,}|~{3,})');
final RegExp _leadingSpace = RegExp(r'^\s+');
final RegExp _indentOf = RegExp(r'^\s*');

/// Every list in [lines], in order, from the end of the note's front matter (core/front_matter.dart): a key's value
/// is never a list to put words in. A block that rule counts as front matter holds keys alone, never a list line, so
/// this is a guard for a looser rule later rather than one a note can reach today.
List<Run> runsOf(List<String> lines) {
  final runs = <Run>[];
  var i = frontMatterEnd(lines);
  String? fence;
  while (i < lines.length) {
    final line = lines[i];
    final marker = _fenceMarker.firstMatch(line)?.group(1);
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
      } else if (line.trim().isNotEmpty && _leadingSpace.hasMatch(line) && (_indentOf.firstMatch(line)?.group(0)?.length ?? 0) > indent.length) {
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
final RegExp _notWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// A text's stems: the first six letters of each word of four or more that says something.
Set<String> _stems(String text) => {
  for (final word in text.toLowerCase().replaceAll(_linkTarget, ' ').split(_notWord))
    if (word.length >= 4 && !_quiet.contains(word)) word.length > 6 ? word.substring(0, 6) : word,
};

final RegExp _headingLine = RegExp(r'^#{1,6}\s+(.+?)\s*#*\s*$');
final RegExp _titleLine = RegExp(r'^#\s');

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
    final marker = _fenceMarker.firstMatch(line)?.group(1);
    if (marker != null) {
      if (fence == null) {
        fence = marker[0];
      } else if (marker[0] == fence) {
        fence = null;
      }
      continue;
    }
    if (fence != null || line.trim().isEmpty) continue;
    final heading = _headingLine.firstMatch(line);
    if (heading != null && !titled && _titleLine.hasMatch(line)) {
      titled = true;
      continue;
    }
    titled = true;
    if (heading != null) current = heading.group(1)!;
  }
  return out;
}

final RegExp _colonAtEnd = RegExp(r':\s*$');

/// A list's heading as its words go: the heading above it, or the "Label:" line just above it.
String? _headingOf(List<String> lines, Run run, List<String?> above) {
  for (var i = run.first - 1; i >= 0; i -= 1) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    if (_colonAtEnd.hasMatch(line) && listLead(line) == null) return line.replaceFirst(_colonAtEnd, '');
    break;
  }
  return run.first < above.length ? above[run.first] : null;
}

/// A note's list, with the words that say what goes in it: its heading and its items.
class ListOf {
  const ListOf({required this.run, required this.heading, required this.items});
  final Run run;
  final String? heading;
  final String items;
}

/// The lists of [lines] ([runsOf], or some of them), each with its heading and its items' words.
List<ListOf> listsOf(List<String> lines, List<Run> runs) {
  final above = _headingsAbove(lines);
  return [for (final run in runs) ListOf(run: run, heading: _headingOf(lines, run, above), items: lines.sublist(run.first, run.last + 1).join(' '))];
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
/// items share the most with it, the heading counting double ([bestList]); with nothing to go by, [restingList]. The
/// same choice the live reader's words make (place.dart), so a command read at Done puts a thing where one said live
/// would.
Run? _runFor(List<String> lines, List<Run> runs, String? text) {
  if (runs.isEmpty) return null;
  final lists = listsOf(lines, runs);
  final best = text != null && text.isNotEmpty && runs.length > 1 ? bestList(lists, text).index : -1;
  return runs[best >= 0 ? best : restingList(lines, lists)];
}

final RegExp _digit = RegExp(r'\d');
final RegExp _leadingDigits = RegExp(r'^\d+');

RunStyle styleOf(ListLead lead) {
  final task = lead.done != null;
  // A number's marker is its digits and then its `.` or `)`; a bullet's is the one character.
  if (_digit.hasMatch(lead.marker)) {
    return RunStyleNumber(next: int.parse(_leadingDigits.firstMatch(lead.marker)!.group(0)!) + 1, delimiter: lead.marker.substring(lead.marker.length - 1), task: task);
  }
  return RunStyleBullet(mark: lead.marker, task: task);
}

final RegExp _itemEnd = RegExp(r'(?:\\?[\s.,;:])+$');

/// One item's text as a list line: first letter up, no closing full stop. A stop the model's words carried in escaped
/// (instruction_mutation.dart `literalMarkdown` writes `\.`) goes with its backslash, which alone would end the line.
String itemText(String text) => capitalise(text.trim().replaceFirst(_itemEnd, ''));

/// [body] with [items] on the end of its last list, or of the list [near] belongs in when it has several. [asTasks]
/// shapes a list that has to be started (a note with no list yet). Answers the new body and the lines added, for
/// showing them land. An item's due day, priority and person said at its end ("call the plumber due Friday") are
/// written as its fields (spoken/fields.dart, docs/DESIGN.md §158), counted from [today].
({String body, List<String> added}) appendToList(String body, List<String> items, {bool asTasks = false, String? near, String? today}) {
  final day = today ?? isoDay(DateTime.now());
  final texts = items.map(itemText).where((text) => text.isNotEmpty).toList();
  if (texts.isEmpty) return (body: body, added: <String>[]);
  final lines = body.split('\n');
  final run = _runFor(lines, runsOf(lines), near);

  if (run == null) {
    final added = [for (final text in texts) withSpokenFields('${asTasks ? '- [ ] ' : '- '}$text', day)];
    return (body: appendBlock(body, added.join('\n')), added: added);
  }

  final style = run.style;
  var number = style is RunStyleNumber ? style.next : 0;
  final box = style.task ? '[ ] ' : '';
  final added = [
    for (final text in texts)
      withSpokenFields(switch (style) {
        RunStyleNumber() => '${run.indent}${number++}${style.delimiter} $box$text',
        RunStyleBullet() => '${run.indent}${style.mark} $box$text',
      }, day),
  ];
  final next = [...lines.sublist(0, run.last + 1), ...added, ...lines.sublist(run.last + 1)];
  return (body: next.join('\n'), added: added);
}

/// The lines of [body] just above the last `added.length` lines ending at the last of [added], blank ones left out:
/// the list as it was before [appendToList] put the items on its end, for showing them land under it.
List<String> linesAbove(String body, List<String> added, [int keep = 2]) {
  final lines = body.split('\n');
  final end = lines.lastIndexOf(added.isEmpty ? '' : added.last);
  final start = end - added.length + 1;
  final from = start - keep < 0 ? 0 : start - keep, to = start < 0 ? 0 : start;
  if (from >= to || from >= lines.length) return [];
  return lines.sublist(from, to > lines.length ? lines.length : to).where((line) => line.trim().isNotEmpty).toList();
}

/// What a spoken note starts with that is not the note: "that", "to", "saying".
final RegExp _leadIn = RegExp(
  r'^\s*(?:(?:that\s+says|which\s+says|that\s+reads|to\s+say|saying)\s+)?(?:(?:that|to)\s+(?=\p{L}))?',
  caseSensitive: false,
  unicode: true,
);

final RegExp _space = RegExp(r'\s+');
final RegExp _sentenceEnd = RegExp(r'[.!?]+\s+');

/// A thing to do or a short point, rather than a paragraph: short, and one or two sentences.
bool _itemShaped(String text) {
  final words = text.split(_space).where((word) => word.isNotEmpty).length;
  final sentences = text.split(_sentenceEnd).where((part) => part.trim().isNotEmpty).length;
  return words <= 30 && sentences <= 2;
}

/// Title-owned defaults when a list has no items yet, from the note's title as the list reads it (after its front
/// matter): a to-do title ("Todo", "House TODOs", "Chores") takes to-dos, a list title ("Groceries", "Packing list")
/// bullets (note_find.dart `titleKind`). Only a title of a few words: a note that opens with a sentence about
/// shopping is not a shopping list.
TitleKind? semanticListKind(String body) {
  final title = noteTitle(body);
  if (title.isEmpty || title.split(_space).length > 4) return null;
  return titleKind(title);
}

/// Where words were put: into a list, or as a paragraph of their own (the web's `'list' | 'paragraph'`).
enum PlacedInto { list, paragraph }

final RegExp _quotes = RegExp('^["“]+|["”]+\$');
final RegExp _endsInStop = RegExp(r'[.!?…]$');

/// "Leave a note on the page for AttackFM that says the login is broken on Android": [text] put where it belongs in
/// [body]. A note with a list takes it as a new item of that list (the list it fits, when there are several), since a
/// note of lists is a note of items; a long thought, or a note with no list, takes it as its own paragraph at the
/// end. Answers the new body, the lines added and which it was.
({String body, List<String> added, PlacedInto into}) leaveNote(String body, String text, {bool asParagraph = false}) {
  final words = text.replaceFirst(_leadIn, '').replaceAll(_quotes, '').trim();
  if (words.isEmpty) return (body: body, added: <String>[], into: PlacedInto.paragraph);
  final lines = body.split('\n');
  // A short thing, on a note of lists, is an item; asked for as a paragraph (`placeWords`' "paragraph"), it is one,
  // list or no list.
  if (!asParagraph && runsOf(lines).isNotEmpty) {
    // Short sentences one after another are a list said slowly: each is an item, not one item with full stops in it.
    final said = spokenSentenceItems(words);
    if (said != null) {
      final placed = appendToList(body, said, near: said.first);
      return (body: placed.body, added: placed.added, into: PlacedInto.list);
    }
  }
  if (!asParagraph && runsOf(lines).isNotEmpty && _itemShaped(words)) {
    final placed = appendToList(body, [words], near: words);
    return (body: placed.body, added: placed.added, into: PlacedInto.list);
  }
  final sentence = capitalise(words);
  final line = _endsInStop.hasMatch(sentence) ? sentence : '$sentence.';
  return (body: appendBlock(body, line), added: [line], into: PlacedInto.paragraph);
}

/// "leave": where it fits; "item": a list item; "paragraph": its own paragraph, whatever the note holds
/// (`Placing['how']`).
enum PlacingHow { leave, item, paragraph }

/// How a command asked for words to be put into a note (`Placing`).
class Placing {
  const Placing({required this.how, required this.task, required this.many, this.near, this.items});

  final PlacingHow how;
  final bool task;
  final bool many;
  final String? near;

  /// Items already told apart by the command: each is one item, commas and all.
  final List<String>? items;
}

final RegExp _commaSplit = RegExp(r'\s*,\s*');

/// Spoken words put into a note the way a command asked: "leave" where they fit ([leaveNote]), "item" as list items,
/// split on commas or "and" when there are several. What the recorder shows before asking, and what it does after
/// the tap, are both this, so the preview is the result.
({String body, List<String> added, PlacedInto into}) placeWords(String body, String spoken, Placing placing) {
  final how = placing.how, task = placing.task, many = placing.many, near = placing.near, told = placing.items;
  final semantic = semanticListKind(body);
  ({String body, List<String> added, PlacedInto into}) listed(List<String> items) {
    final placed = appendToList(body, items, asTasks: task || semantic == TitleKind.task, near: near);
    return (body: placed.body, added: placed.added, into: PlacedInto.list);
  }

  if (how == PlacingHow.item && told != null && told.isNotEmpty) return listed(told);
  if (how == PlacingHow.paragraph) return leaveNote(body, spoken, asParagraph: true);
  if (how == PlacingHow.leave && semantic == null) return leaveNote(body, spoken);
  // Several said one after another arrive joined with commas: each is an item, two as much as five.
  final explicit = many && spoken.contains(',') ? spoken.split(_commaSplit).where((item) => item.isNotEmpty).toList() : null;
  final found = explicit ?? (many || spoken.contains(',') ? enumeration('Items: $spoken')?.items : null);
  return listed(found != null && found.isNotEmpty ? found : (spokenSentenceItems(spoken) ?? [spoken]));
}

/// The section an instruction named for its words (`InstructionArea`; null is the web's `null`).
enum InstructionArea { bugs, tasks, list, notes }

final RegExp _listArea = RegExp(r'\b(?:list|items?)\b', caseSensitive: false);
final RegExp _bugsArea = RegExp(r'\b(?:bugs?|issues?|defects?)\b', caseSensitive: false);
final RegExp _tasksArea = RegExp(r'\b(?:tasks?|to-?dos?|actions?)\b', caseSensitive: false);
final RegExp _anyHeading = RegExp(r'^(#{1,6})\s+(.+?)\s*$');

/// Places an inferred append inside an explicitly named Markdown section. Only the section slice is rewritten; front
/// matter, other headings, tables, HTML, and fenced code stay byte-for-byte unchanged.
({String body, List<String> added, PlacedInto into}) placeInstruction(String body, String content, InstructionArea? area) {
  if (area == null) {
    final semantic = semanticListKind(body);
    if (semantic != null) {
      final placed = appendToList(body, [content], asTasks: semantic == TitleKind.task, near: content);
      return (body: placed.body, added: placed.added, into: PlacedInto.list);
    }
    return leaveNote(body, content);
  }
  if (area == InstructionArea.notes) return leaveNote(body, content);
  final lines = body.split('\n');
  final wanted = area == InstructionArea.list
      ? _listArea
      : area == InstructionArea.bugs
      ? _bugsArea
      : _tasksArea;
  String? fence;
  var heading = -1;
  var level = 7;
  var end = lines.length;
  for (var i = 0; i < lines.length; i += 1) {
    final line = lines[i];
    final marker = _fenceMarker.firstMatch(line)?.group(1);
    if (marker != null) {
      if (fence == null) {
        fence = marker[0];
      } else if (marker[0] == fence) {
        fence = null;
      }
      continue;
    }
    if (fence != null) continue;
    final match = _anyHeading.firstMatch(line);
    if (match == null) continue;
    final currentLevel = match.group(1)?.length ?? 7;
    if (heading < 0 && wanted.hasMatch(match.group(2) ?? '')) {
      heading = i;
      level = currentLevel;
    } else if (heading >= 0 && currentLevel <= level) {
      end = i;
      break;
    }
  }
  if (heading < 0) {
    final placed = appendToList(body, [content], asTasks: area == InstructionArea.tasks, near: area.name);
    return (body: placed.body, added: placed.added, into: PlacedInto.list);
  }
  final section = lines.sublist(heading + 1, end).join('\n');
  final placed = appendToList(section, [content], asTasks: area == InstructionArea.tasks, near: area.name);
  final replacement = placed.body.split('\n');
  final next = [...lines.sublist(0, heading + 1), ...replacement, ...lines.sublist(end)];
  return (body: next.join('\n'), added: placed.added, into: PlacedInto.list);
}
