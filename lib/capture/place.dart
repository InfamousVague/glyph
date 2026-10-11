/// Where a take's words go inside the note they are for, and the note as it reads with them there: what the
/// recorder's page draws as the words are said, what Done writes, and what the better words write later, so the
/// three agree. A port of `src/app/capture/place.ts`.
///
/// Matt: "when it's found that note, it should look through the note and see what different things I could be
/// talking about adding to. Like if there's a list already." So a note that keeps lists takes the words as items of
/// the one they fit: the only list; the list under a heading that shares their words ("call an electrician" under
/// Electrical, not under Kitchen for sharing "fix"); a to-do list when a to-do was said or the title says to-dos;
/// otherwise the first to-do list with something still to do, or the last list. A note with none starts one when its
/// title says what it holds (House TODOs, Groceries), and otherwise the words go on its end as they always did.
///
/// Three pure steps: [placingFor] decides the kind of place from the note and what was said, [itemsOf] reads the
/// take's markdown as items, and [placeTake] writes them in. [placeTake] depends only on its arguments, so the page,
/// Done and the better words, handed the same note, words and placing, write the same text.
///
/// The end can carry a `lead`: words the note's last line was left open with, which the take goes on from. A
/// journal's entry starts with its time and a space, "**14:05** " (core/template.ts `openEnd`), and a spoken entry is
/// written as that line said on, not a lone bold time with the words in a paragraph under it (docs/DESIGN.md §142).
/// The note is handed over without that line, and every writer puts it back with the take.
///
/// What differs: the shapes. `Placing` is a sealed class with one subclass per `kind` ([PlacingEnd], [PlacingLists],
/// [PlacingLane]), and the list it starts (`fresh`) a [PlacingFresh]; `END` is [end]. A placing is written to and
/// read from the JSON the web keeps it as with `toJson` and [Placing.fromJson], since a Dart class is not its own
/// JSON. `placingFor` takes its options as named parameters. list_append.dart has a
/// `Placing` of its own (how a command's words are placed): import one of the two with `hide`.
library;

import '../core/boards.dart' show Lane, addToLane, lanesOf;
import '../core/item_syntax.dart' show listLead;
import '../core/text.dart' show capitalise;
import 'append_body.dart' show appendBlock, appendBody;
import 'list_append.dart'
    show ListOf, Run, RunStyleBullet, RunStyleNumber, bestList, fitOf, itemText, listsOf, restingList, runsOf, semanticListKind;
import 'note_find.dart' show TitleKind;

/// The list a note with none is started with: to-dos, bullets, or numbers (the web's `'task' | 'bullet' |
/// 'number'`).
enum PlacingFresh { task, bullet, number }

/// Where a take's words go in a note: its end, its lists, or a lane of its board (`Placing`).
sealed class Placing {
  const Placing();

  /// The web's `kind`: `end`, `lists` or `lane`.
  String get kind;

  /// The placing as the web keeps it: the object literal, for JSON.
  Map<String, Object?> toJson();

  /// A placing read back from [toJson]'s map, or null for anything that is not one.
  static Placing? fromJson(Object? raw) {
    if (raw is! Map) return null;
    switch (raw['kind']) {
      case 'end':
        final lead = raw['lead'];
        return PlacingEnd(lead: lead is String ? lead : null);
      case 'lists':
        final heading = raw['heading'];
        final fresh = raw['fresh'];
        PlacingFresh? started;
        for (final each in PlacingFresh.values) {
          if (each.name == fresh) started = each;
        }
        return PlacingLists(task: raw['task'] == true, heading: heading is String ? heading : null, fresh: started);
      case 'lane':
        final lane = raw['lane'];
        return lane is String ? PlacingLane(lane: lane) : null;
    }
    return null;
  }
}

/// The note's end.
final class PlacingEnd extends Placing {
  const PlacingEnd({this.lead});

  /// The note's last line as it was left open, taken off the note and written again before the take: on the same
  /// line when the take starts with a paragraph, on a line of its own above anything else. Absent, the end as it
  /// always was.
  final String? lead;

  @override
  String get kind => 'end';

  @override
  Map<String, Object?> toJson() => {'kind': 'end', if (lead != null) 'lead': lead};

  @override
  bool operator ==(Object other) => other is PlacingEnd && other.lead == lead;

  @override
  int get hashCode => Object.hash(kind, lead);

  @override
  String toString() => '{kind: end${lead == null ? '' : ', lead: $lead'}}';
}

/// The note's lists.
final class PlacingLists extends Placing {
  const PlacingLists({required this.task, required this.heading, required this.fresh});

  /// A to-do was said, or the title says to-dos: only the to-do lists count, and a new list is one.
  final bool task;

  /// A heading said for it ("under Electrical"): the list under that heading.
  final String? heading;

  /// The note has no list yet: the one to start, or null for none (the words go at the end). Numbered for a journal
  /// whose template ends in an empty numbered item, "1. " (core/template.ts `openEnd`).
  final PlacingFresh? fresh;

  @override
  String get kind => 'lists';

  @override
  Map<String, Object?> toJson() => {'kind': 'lists', 'task': task, 'heading': heading, 'fresh': fresh?.name};

  @override
  bool operator ==(Object other) => other is PlacingLists && other.task == task && other.heading == heading && other.fresh == fresh;

  @override
  int get hashCode => Object.hash(kind, task, heading, fresh);

  @override
  String toString() => '{kind: lists, task: $task, heading: $heading, fresh: ${fresh?.name}}';
}

/// A lane of a board, by name, for "add … to Doing" said on the board's own Speak (core/boards.dart).
final class PlacingLane extends Placing {
  const PlacingLane({required this.lane});

  final String lane;

  @override
  String get kind => 'lane';

  @override
  Map<String, Object?> toJson() => {'kind': 'lane', 'lane': lane};

  @override
  bool operator ==(Object other) => other is PlacingLane && other.lane == lane;

  @override
  int get hashCode => Object.hash(kind, lane);

  @override
  String toString() => '{kind: lane, lane: $lane}';
}

/// The end of the note, byte for byte what `appendBody` writes (`END`).
const Placing end = PlacingEnd();

/// What a command said about the words it sent: a to-do or task, or a paragraph.
class Said {
  const Said({this.task, this.paragraph});

  final bool? task;
  final bool? paragraph;
}

/// The kind of place [base] has for a take's words.
///
/// - A move ("move this to …") or "as a paragraph": the end.
/// - A note's own Speak: the end, as it always was, unless its title says what it holds (House TODOs, Groceries),
///   when what is said is its items.
/// - Otherwise the note's lists, when it has any, or a new one when its title or the command says what kind.
Placing placingFor(String base, {Said said = const Said(), String? heading, String? lane, bool move = false, bool own = false}) {
  if (move || said.paragraph == true) return end;
  if (lane != null && lane.isNotEmpty && lanesOf(base).any((candidate) => candidate.name == lane)) return PlacingLane(lane: lane);
  final kind = semanticListKind(base);
  if (own && kind == null && (heading == null || heading.isEmpty)) return end;
  final task = said.task == true || kind == TitleKind.task;
  if (runsOf(base.split('\n')).isNotEmpty) return PlacingLists(task: task, heading: heading, fresh: null);
  final fresh = task
      ? PlacingFresh.task
      : kind == TitleKind.bullet
      ? PlacingFresh.bullet
      : null;
  return fresh != null ? PlacingLists(task: task, heading: heading, fresh: fresh) : end;
}

// ---- the take as items --------------------------------------------------------------------------------------------

/// One thing a take said, as an item (`TakeItem`).
class TakeItem {
  TakeItem({required this.text, List<String>? more}) : more = more ?? [];

  final String text;

  /// Lines under it: a sentence that carries it on ("because the switch sparks").
  final List<String> more;

  @override
  bool operator ==(Object other) {
    if (other is! TakeItem || other.text != text || other.more.length != more.length) return false;
    for (var i = 0; i < more.length; i += 1) {
      if (other.more[i] != more[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(text, Object.hashAll(more));

  @override
  String toString() => '{text: $text, more: $more}';
}

/// A sentence that carries the one before it on, rather than being a thing of its own.
final RegExp _continues = RegExp(
  r"^(?:because|'cause|cause|so|but|which|since|i think|i guess|apparently|that's|it's|they're|he's|she's)\b",
  caseSensitive: false,
);

/// Words a person joins items with, which are not the item.
final RegExp _joiner = RegExp(r'^(?:and also|oh and|and|also|plus)[,\s]+', caseSensitive: false);

/// A sentence this long is a thought, not a thing to do.
const int _longWords = 30;

/// A block that is not words to list: a heading, a fence, a table, a quote, a rule, a voice memo's mark.
final RegExp _notItems = RegExp(r'^(?:#{1,6}\s|```|~~~|\||>|---\s*$|\*\*\*\s*$|!\[)');

/// Where one sentence ends and the next begins.
final RegExp _sentence = RegExp(r'''(?<=[.!?…])\s+(?=["'“(]?[\p{Lu}\p{N}])''', unicode: true);

final RegExp _blankLines = RegExp(r'\n{2,}');
final RegExp _spaces = RegExp(r'\s+');
final RegExp _leadingSpace = RegExp(r'^\s+');

/// The take's markdown (capture/markdown.dart `renderNote`, untitled) as items: each list line one, each sentence of
/// a paragraph one, with a sentence that carries the last one on ("Because the switch sparks.") under it, and
/// anything that is not words to list - a heading, a table, a fenced block, a voice memo, a thought over thirty words
/// said first - kept to go after the lists, at the end.
({List<TakeItem> items, List<String> after}) itemsOf(String markdown) {
  final items = <TakeItem>[];
  final after = <String>[];
  for (final block in markdown.split(_blankLines)) {
    final lines = block.split('\n').where((line) => line.trim().isNotEmpty).toList();
    if (lines.isEmpty) continue;
    if (_notItems.hasMatch(lines[0].trimLeft())) {
      after.add(lines.join('\n'));
      continue;
    }
    if (listLead(lines[0]) != null) {
      for (final line in lines) {
        final lead = listLead(line);
        if (lead != null && lead.indent.isEmpty) {
          items.add(TakeItem(text: line.substring(lead.wordsAt)));
        } else if (items.isNotEmpty) {
          items.last.more.add(lead != null ? line.substring(lead.wordsAt) : line.trim());
        } else {
          items.add(TakeItem(text: line.trim()));
        }
      }
      continue;
    }
    for (final sentence in lines.join(' ').split(_sentence)) {
      final text = sentence.trim();
      if (text.isEmpty) continue;
      final long = text.split(_spaces).length > _longWords;
      if ((_continues.hasMatch(text) || long) && items.isNotEmpty) {
        items.last.more.add(text);
      } else if (long) {
        after.add(text);
      } else {
        items.add(TakeItem(text: text.replaceFirst(_joiner, '')));
      }
    }
  }
  return (items: items.where((item) => itemText(item.text).isNotEmpty).toList(), after: after);
}

// ---- writing them in ----------------------------------------------------------------------------------------------

/// A note with a take's words in it (`Placed`).
class Placed {
  const Placed({required this.body, required this.blocks, required this.spot});

  /// The note with the take's words in it.
  final String body;

  /// The pieces of text put in, each as it was written: for Undo to find and take out again.
  final List<String> blocks;

  /// Where they went, in words ("under Electrical", "in its to-do list"), or null for the end of the note.
  final String? spot;

  @override
  bool operator ==(Object other) {
    if (other is! Placed || other.body != body || other.spot != spot || other.blocks.length != blocks.length) return false;
    for (var i = 0; i < blocks.length; i += 1) {
      if (other.blocks[i] != blocks[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(body, Object.hashAll(blocks), spot);

  @override
  String toString() => '{body: $body, blocks: $blocks, spot: $spot}';
}

/// An item as a line of [run]'s list, numbered [n] when the list is numbered.
String _lineIn(Run run, String text, int n) {
  final box = run.style.task ? '[ ] ' : '';
  return switch (run.style) {
    RunStyleNumber(:final delimiter) => '${run.indent}$n$delimiter $box$text',
    RunStyleBullet(:final mark) => '${run.indent}$mark $box$text',
  };
}

/// An item's line and the lines under it.
List<String> _itemLines(String first, TakeItem item, String under) => [first, for (final line in item.more) '$under${capitalise(line.trim())}'];

/// The take with the line it goes on from before it: joined to a first paragraph, and on a line of its own above a
/// list, a heading or anything else that is not words to run on. With nothing said yet, the line alone, so the page
/// shows where the words will start.
String _withLead(String lead, String markdown) {
  final words = markdown.replaceFirst(_leadingSpace, '');
  if (words.isEmpty) return lead.trimRight();
  final first = words.split('\n')[0];
  return _notItems.hasMatch(first) || listLead(first) != null ? '${lead.trimRight()}\n\n$words' : '$lead$words';
}

/// [base] with the take's [markdown] in it, where [placing] says: at the end (`appendBody`), in a lane of the note's
/// board, or as items of its lists, each item in the list it fits and the rest after them at the end.
Placed placeTake(String base, String markdown, Placing placing) {
  if (placing is PlacingEnd) {
    final lead = placing.lead;
    final take = lead != null && lead.isNotEmpty ? _withLead(lead, markdown) : markdown;
    return Placed(body: appendBody(base, take), blocks: markdown.trim().isNotEmpty ? [take] : [], spot: null);
  }
  if (markdown.trim().isEmpty) return Placed(body: base, blocks: const [], spot: null);
  final (:items, :after) = itemsOf(markdown);
  var body = base;
  final blocks = <String>[];
  String? spot;

  if (placing is PlacingLane) {
    for (final item in items) {
      Lane? lane;
      for (final candidate in lanesOf(body)) {
        if (candidate.name == placing.lane) {
          lane = candidate;
          break;
        }
      }
      final added = lane != null ? addToLane(body, lane, itemText(item.text)) : null;
      if (added == null) continue;
      body = added.body;
      blocks.add(added.line);
    }
    spot = 'in ${placing.lane}';
  } else if (placing is PlacingLists && items.isNotEmpty) {
    final lines = body.split('\n');
    final all = runsOf(lines);
    final runs = placing.task && all.any((run) => run.style.task) ? all.where((run) => run.style.task).toList() : all;
    if (runs.isEmpty) {
      final fresh = placing.fresh ?? (placing.task ? PlacingFresh.task : PlacingFresh.bullet);
      String lead(int n) => switch (fresh) {
        PlacingFresh.task => '- [ ] ',
        PlacingFresh.number => '$n. ',
        PlacingFresh.bullet => '- ',
      };
      final block = [
        for (var n = 0; n < items.length; n += 1)
          ..._itemLines('${lead(n + 1)}${itemText(items[n].text)}', items[n], fresh == PlacingFresh.number ? ' ' * lead(n + 1).length : '  '),
      ].join('\n');
      body = appendBlock(body, block);
      blocks.add(block);
      spot = fresh == PlacingFresh.task ? 'in a new to-do list' : 'in a new list';
    } else {
      final lists = listsOf(lines, runs);
      int scoreOf(String text, int index) => fitOf(text, heading: lists[index].heading, items: lists[index].items);
      final heading = placing.heading;
      final named = heading != null && heading.isNotEmpty
          ? lists.indexWhere((ListOf list) => list.heading != null && fitOf(heading, heading: list.heading, items: '') > 0)
          : -1;
      final first = items[0].text;
      var current = named >= 0 ? named : bestList(lists, first).index;
      // Nothing to go by: the first to-do list with something still to do, or the last list, where items always
      // went.
      if (current < 0) current = restingList(lines, lists);
      final firstList = lists[current];
      spot = firstList.heading != null && firstList.heading!.isNotEmpty
          ? 'under ${firstList.heading}'
          : firstList.run.style.task
          ? 'in its to-do list'
          : 'in its list';
      final into = <int, List<TakeItem>>{};
      for (var i = 0; i < items.length; i += 1) {
        final item = items[i];
        if (i > 0) {
          // Related things said together stay together; one that plainly fits another list goes there.
          final other = bestList(lists, item.text);
          if (other.index >= 0 && other.index != current && other.score >= 2 && other.score > scoreOf(item.text, current)) current = other.index;
        }
        (into[current] ??= []).add(item);
      }
      // From the last list up, so the lines of the ones above keep their places.
      final order = into.keys.toList()..sort((a, b) => lists[b].run.last - lists[a].run.last);
      final next = [...lines];
      final written = <int, String>{};
      for (final index in order) {
        final run = lists[index].run;
        final style = run.style;
        var n = style is RunStyleNumber ? style.next : 0;
        final under = '${run.indent}${style is RunStyleNumber ? '   ' : '  '}';
        final added = [
          for (final item in into[index]!) ..._itemLines(_lineIn(run, itemText(item.text), n++), item, under),
        ];
        next.insertAll(run.last + 1, added);
        written[index] = added.join('\n');
      }
      body = next.join('\n');
      for (final index in into.keys) {
        blocks.add(written[index]!);
      }
    }
  }
  for (final block in after) {
    body = appendBlock(body, block);
    blocks.add(block);
  }
  return Placed(body: body, blocks: blocks, spot: spot);
}
