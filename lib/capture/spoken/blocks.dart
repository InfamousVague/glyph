/// The cues that make a sentence a block of its own - "heading", "bullet point", "check box", "quote", "divider",
/// "callout", "option", "calculate", "define … as …", "I need to …" - and how the blocks are written out, with the
/// blank lines between them that markdown reads as where one list ends and the next thing begins. A port of
/// `src/app/capture/spoken/blocks.ts`.
///
/// One sentence at a time ([localBlocks]), then the whole note's blocks together ([renderBlocks]), which is where
/// consecutive items of one kind become one list. capture/markdown.dart `renderNote` decides which sentences get here
/// and holds what spans sentences: a cue said alone, an item phrase waiting for its item, a list announced. Pure.
///
/// What differs: the web's `Block` is a union of object literals told apart by `kind`; here it is one class with a
/// [BlockKind] and the three fields only some kinds carry (`type`, `picked`, `term`, `lang`), since the driver makes a
/// block of a kind it only knows at run time and copies one with new words. The exported patterns are lower camel
/// case: `TITLE_CUE` is [titleCue], `ORDINAL_START` [ordinalStart], `NUMBER_CUE` [numberCue], `STANDALONE_CUE`
/// [standaloneCue].
library;

import '../../core/text.dart';
import 'lists.dart';
import 'numbers.dart';
import 'stand_ins.dart';
import 'words.dart';

final RegExp _headingCue = RegExp(r'^(?:new\s+section|section|heading)[:,.]?\s+(.+)$', caseSensitive: false);
final RegExp _subheadingCue = RegExp(r'^(?:sub[\s-]?heading|sub[\s-]?section|smaller\s+heading)[:,.]?\s+(.+)$', caseSensitive: false);
final RegExp _bulletCue = RegExp(r'^(?:bullet(?:\s+point)?|(?:next|new)\s+(?:point|item|bullet))[:,.]?\s+(.+)$', caseSensitive: false);

/// "Title: …", "call this …": the note's own name, said (`TITLE_CUE`).
final RegExp titleCue = RegExp(r'^(?:title|note\s+title|call\s+(?:this|it)(?:\s+no(?:te|de))?)[:,.]?\s+(.+)$', caseSensitive: false);
final RegExp _importantCue = RegExp(r'^(important|key\s+point|note)[:,]\s*(.+)$', caseSensitive: false);
final RegExp _task = RegExp(
  r"^(?:(?:i|we)\s+(?:really\s+)?(?:need|have|got)\s+to|remember\s+to|don'?t\s+forget\s+to|do\s+not\s+forget\s+to|remind\s+me\s+to|to[\s-]?do[:,]?|task[:,])\s+(.+)$",
  caseSensitive: false,
);
final RegExp _ordinal = RegExp(
  r'^(first(?:ly)?|second(?:ly)?|third(?:ly)?|fourth(?:ly)?|fifth(?:ly)?|next|then|after\s+that|finally|lastly)[,:]?\s+(.+)$',
  caseSensitive: false,
);

/// "First", which makes the "then" and "next" after it in the paragraph list items rather than joins
/// (`ORDINAL_START`).
final RegExp ordinalStart = RegExp(r'^first(?:ly)?\b', caseSensitive: false);

// Cues added for the "how to talk to Glyph" guide. Each one that could be ordinary speech demands the comma or colon
// Whisper writes after a spoken pause, because that pause is the only thing separating a command from a sentence:
// "Number one, book flights" is a list item, "number one priority is sleep" is prose, and only the comma tells them
// apart.
final RegExp _quoteCue = RegExp(r'^quote[:,]\s*(.+)$', caseSensitive: false);

/// "Number three, book flights": a numbered item (`NUMBER_CUE`). Groups: the number, the item.
final RegExp numberCue = RegExp('^number\\s+($smallNumber)[:,]\\s*(.+)\$', caseSensitive: false);
final RegExp _checkboxCue = RegExp(r'^(?:check(?:ed)?\s?box[:,.]?|checklist(?:\s+item)?[:,]|check\s+item[:,])\s*(.+)$', caseSensitive: false);
final RegExp _dividerCue = RegExp(r'^(?:divider|horizontal\s+(?:line|rule)|separator)[.!]?$', caseSensitive: false);

/// "Callout: the gate sticks", "warning callout: mind the step": a GitHub callout (`> [!NOTE]`), a note unless said
/// otherwise.
final RegExp _calloutCue = RegExp(
  r'^(?:(note|tip|important|warning|caution)\s+)?(?:callout[:,.]?|call[\s-]out[:,.]|info\s?box[:,.]?)\s*(.+)$',
  caseSensitive: false,
);

/// "Hidden line: it was the butler": a line kept in smoke until it is tapped (`>|`).
final RegExp _hiddenCue = RegExp(r'^(?:hidden|secret|spoiler)\s+line[:,.]\s*(.+)$', caseSensitive: false);

/// "Option: tent", "picked option: hotel": choices, one of them picked (`- ( )`, `- (x)`).
final RegExp _choiceCue = RegExp(r'^(?:(pick(?:ed)?|pict|chosen|selected)[\s-]*)?(?:option|choice|auction)[:,.]\s*(.+)$', caseSensitive: false);

/// "Calculate: four hundred fifty plus one hundred twenty": a sum, worked out on the page (`= 450 + 120`).
final RegExp _sumCue = RegExp(r'^(?:calculate|sum|add\s+up)[:,.]\s*(.+)$', caseSensitive: false);

/// "Done task: call Sam": a to-do already done (`- [x]`). A bare "done" is a reply, not a cue, and "checked box" is
/// how Whisper hears "check box" often enough that it stays an open one.
final RegExp _doneCue = RegExp(
  r'^(?:ticked\s+(?:box|off|item)|done\s+(?:item|task|to[\s-]?do)|finished\s+(?:item|task|to[\s-]?do))[:,.]?\s+(.+)$',
  caseSensitive: false,
);

/// "Define deposit as what you pay up front": a term and its meaning (`Deposit` / `: What you pay up front`).
final RegExp _defineCue = RegExp(
  r'^(?:define|definition(?:\s+of)?)[:,]?\s+(?!(?:your|my|our|his|her|their|them|it|this|that|what|how|a|an)\b)(.+?)[,]?\s+(?:as|means|is)[:,]?\s+(.+)$',
  caseSensitive: false,
);

/// A cue said on its own, as its own sentence (`STANDALONE_CUE`).
///
/// The way people actually dictate a command is word, pause, content - and Whisper writes the pause as a full stop,
/// so "Heading. Groceries." arrives as two sentences and the cue patterns above, which expect the content in the same
/// sentence, never saw it: the note got the literal word "Heading." Now a sentence that is nothing but a cue is held
/// and applied to the next sentence, across a paragraph break if the pause was long.
///
/// It doubles as the guard against prompt leakage. Whisper is prompted with the cue vocabulary so it spells cue words
/// consistently, and a model prompted with words can echo them on a quiet window. An echoed "Bullet point." with
/// nothing after it is held forever and never rendered, instead of appearing in the note.
final RegExp standaloneCue = RegExp(
  r'^(title|note\s+title|call\s+(?:this|it)(?:\s+no(?:te|de))?|heading|section|new\s+section|sub[\s-]?heading|sub[\s-]?section|call[\s-]?out|info\s?box|hidden\s+line|option|choice|(?:pick(?:ed)?|pict|chosen|selected)[\s-]*option|calculate|checked\s?box|ticked\s+box|done\s+(?:item|task|to[\s-]?do)|bullet(?:\s+point)?|(?:next|new)\s+(?:point|item|bullet)|quote|check\s?box|checklist(?:\s+item)?|check\s+item|to[\s-]?do|task|important|key\s+point|number\s+'
  '$smallNumber'
  r')[.,:!]?$',
  caseSensitive: false,
);

/// What a block is (the web's `Block['kind']`).
enum BlockKind {
  para,
  heading,
  bullet,

  /// One entry of a spoken enumeration: a bullet that belongs to its intro, not to its neighbours.
  item,
  number,
  task,
  intro,
  quote,
  rule,
  subheading,

  /// A line that stands out ("Important: …"): its own paragraph, never run into the next.
  standout,
  callout,
  hidden,
  choice,
  sum,
  done,
  definition,
  fence,
}

/// One block of a spoken note (`Block`).
class Block {
  const Block(this.kind, this.text, {this.type, this.picked, this.term, this.lang});

  final BlockKind kind;
  final String text;

  /// A callout's type, lower case: `note`, `warning`.
  final String? type;

  /// Whether a choice is the one picked.
  final bool? picked;

  /// A definition's term.
  final String? term;

  /// A fence's language, '' for none.
  final String? lang;

  /// The block with other words, as the web's `{ ...block, text }`.
  Block withText(String text) => Block(kind, text, type: type, picked: picked, term: term, lang: lang);

  @override
  bool operator ==(Object other) =>
      other is Block && other.kind == kind && other.text == text && other.type == type && other.picked == picked && other.term == term && other.lang == lang;

  @override
  int get hashCode => Object.hash(kind, text, type, picked, term, lang);

  @override
  String toString() => 'Block(${kind.name}, $text)';
}

/// Which run a block belongs to, for deciding where blank lines go.
///
/// An enumeration is its own family, separate from spoken bullets and to-dos, because it is a CLOSED list: "for the
/// drive we want snacks, water and a charger" is complete when the sentence ends. Sharing a family let the next
/// sentence's to-do ("ask Sam about the dog") render as a fifth item of the snacks list, which is a claim about the
/// note Matt never made. Spoken bullets and to-dos, by contrast, are open lists that grow a sentence at a time, so
/// consecutive ones do merge.
String _family(Block block) => switch (block.kind) {
  BlockKind.item || BlockKind.intro => 'items',
  BlockKind.bullet || BlockKind.task || BlockKind.done => 'bullets',
  BlockKind.number => 'numbers',
  BlockKind.quote => 'quotes',
  BlockKind.choice => 'choices',
  BlockKind.hidden => 'hidden',
  _ => block.kind.name,
};

/// A group that took part and matched something: JS's `match?.[n]` read as a truth.
String? _said(RegExpMatch? match, int group) {
  final text = match?.group(group);
  return text == null || text.isEmpty ? null : text;
}

/// Blocks for one sentence under the local rules.
///
/// [ordinalRun] is decided per paragraph by the caller, because "then" and "next" only start list items once a
/// "first" has made the run a list; on their own they are just how people join clauses.
List<Block> localBlocks(String text, bool ordinalRun) {
  final heading = _said(_headingCue.firstMatch(text), 1);
  if (heading != null) return [Block(BlockKind.heading, capitalise(stripEnd(heading)))];

  final subheading = _said(_subheadingCue.firstMatch(text), 1);
  if (subheading != null) return [Block(BlockKind.subheading, capitalise(stripEnd(subheading)))];

  final callout = _calloutCue.firstMatch(text);
  final calloutWords = _said(callout, 2);
  if (calloutWords != null) return [Block(BlockKind.callout, capitalise(calloutWords.trim()), type: (callout!.group(1) ?? 'note').toLowerCase())];

  final hidden = _said(_hiddenCue.firstMatch(text), 1);
  if (hidden != null) return [Block(BlockKind.hidden, capitalise(hidden.trim()))];

  final choice = _choiceCue.firstMatch(text);
  final choiceWords = _said(choice, 2);
  if (choiceWords != null) return [Block(BlockKind.choice, capitalise(stripEnd(choiceWords)), picked: _said(choice, 1) != null)];

  final sum = _said(_sumCue.firstMatch(text), 1);
  final worked = sum != null ? spokenSum(sum) : null;
  if (worked != null && worked.isNotEmpty) return [Block(BlockKind.sum, '= $worked')];

  final done = _said(_doneCue.firstMatch(text), 1);
  if (done != null) return [Block(BlockKind.done, itemOf(done) ?? capitalise(stripEnd(done)))];

  final defined = _defineCue.firstMatch(text);
  final term = _said(defined, 1), meaning = _said(defined, 2);
  if (term != null && meaning != null && words(term) <= 3) {
    return [Block(BlockKind.definition, capitalise(meaning.trim()), term: capitalise(stripEnd(term)))];
  }

  final bullet = _said(_bulletCue.firstMatch(text), 1);
  if (bullet != null) return [Block(BlockKind.bullet, itemOf(bullet) ?? capitalise(stripEnd(bullet)))];

  final important = _importantCue.firstMatch(text);
  final label = _said(important, 1), stands = _said(important, 2);
  if (label != null && stands != null) return [Block(BlockKind.standout, '**${capitalise(label)}:** ${capitalise(stands)}')];

  if (_dividerCue.hasMatch(text)) return [const Block(BlockKind.rule, '---')];

  final quote = _said(_quoteCue.firstMatch(text), 1);
  if (quote != null) return [Block(BlockKind.quote, capitalise(quote.trim()))];

  final numbered = _said(numberCue.firstMatch(text), 2);
  if (numbered != null) return [Block(BlockKind.number, itemOf(numbered) ?? capitalise(stripEnd(numbered)))];

  final checkbox = _said(_checkboxCue.firstMatch(text), 1);
  if (checkbox != null) return [Block(BlockKind.task, itemOf(checkbox) ?? capitalise(stripEnd(checkbox)))];

  final task = _said(_task.firstMatch(text), 1);
  if (task != null) return [Block(BlockKind.task, capitalise(stripEnd(task)))];

  if (ordinalRun) {
    final ordinal = _said(_ordinal.firstMatch(text), 2);
    if (ordinal != null) return [Block(BlockKind.number, capitalise(stripEnd(ordinal)))];
  }

  final list = enumeration(text);
  if (list != null) {
    return [Block(BlockKind.intro, '${list.intro}:'), for (final item in list.items) Block(BlockKind.item, item)];
  }

  return [Block(BlockKind.para, text)];
}

const Set<BlockKind> _neverSameRun = {
  BlockKind.para,
  BlockKind.intro,
  BlockKind.standout,
  BlockKind.callout,
  BlockKind.sum,
  BlockKind.fence,
  BlockKind.heading,
  BlockKind.subheading,
};

/// [paragraphStarts] holds the index of the first block each spoken paragraph produced. Sentences of one paragraph
/// arrive as separate prose blocks and are joined back into one line; two prose blocks either side of a paragraph
/// break (a spoken "new paragraph", or a long pause) must not be.
String renderBlocks(List<Block> blocks, [Set<int> paragraphStarts = const {}]) {
  final out = <String>[];
  Block? previous;
  var number = 0;

  for (var index = 0; index < blocks.length; index += 1) {
    final block = blocks[index];
    if (block.kind != BlockKind.number) number = 0;
    final joined = previous?.kind == BlockKind.para && block.kind == BlockKind.para && !paragraphStarts.contains(index);
    // An intro always opens a new run. Written straight under a list line, markdown reads "For food we want:" as a
    // lazy continuation of the item above it rather than as the start of a new list - it rendered inside a to-do
    // before this rule existed.
    final sameRun = previous != null && _family(previous) == _family(block) && !_neverSameRun.contains(block.kind);

    if (joined) {
      out[out.length - 1] = '${out[out.length - 1]} ${block.text}';
    } else {
      if (previous != null && !sameRun) out.add('');
      switch (block.kind) {
        case BlockKind.heading:
          out.add('## ${block.text}');
        case BlockKind.bullet || BlockKind.item:
          out.add('- ${block.text}');
        case BlockKind.task:
          out.add('- [ ] ${block.text}');
        case BlockKind.done:
          out.add('- [x] ${block.text}');
        case BlockKind.definition:
          out
            ..add(block.term ?? '')
            ..add(': ${block.text}');
        case BlockKind.fence:
          out
            ..add('```${block.lang ?? ''}')
            ..add(block.text)
            ..add('```');
        case BlockKind.number:
          number += 1;
          out.add('$number. ${block.text}');
        case BlockKind.quote:
          out.add('> ${block.text}');
        case BlockKind.subheading:
          out.add('### ${block.text}');
        case BlockKind.callout:
          out
            ..add('> [!${(block.type ?? '').toUpperCase()}]')
            ..add('> ${block.text}');
        case BlockKind.hidden:
          out.add('>| ${block.text}');
        case BlockKind.choice:
          out.add('- (${block.picked == true ? 'x' : ' '}) ${block.text}');
        case BlockKind.rule:
          // Always behind a blank line (a different family from anything before it): `---` straight under a line of
          // text is a setext underline, which would turn that text into a heading.
          out.add('---');
        case BlockKind.para || BlockKind.intro || BlockKind.standout || BlockKind.sum:
          out.add(block.text);
      }
    }
    previous = block;
  }
  return out.join('\n');
}

/// Marked words, a clip or a picture: something said to be kept as it is, not a name for the note. The stand-ins
/// count too (spoken/stand_ins.dart): a line's name, the bookmark or a break said in the first sentence make it a
/// line, not a title.
final RegExp _keptAsSaid = RegExp(
  r'\*\*|~~|==|%%|\?\?|\^\^|\+\+|\|\||`|!\[|\[\[|\[\^|\]\(|<https?:|[\^~$'
  '$anchorMark$bookmarkMark$breakMark'
  r']|:[a-z_+-]+:|(?:^|\s)_\S',
);

final RegExp _questionAtEnd = RegExp(r'\?$');

/// Whether an opening sentence reads as a title: short, not a question, and not something the local rules would
/// rather make a list item or a to-do. "Grocery run." is a title; "I need to call the bank." is a task that happens
/// to be first.
bool isTitleShaped(String text) {
  if (_questionAtEnd.hasMatch(text.trim())) return false;
  if (_keptAsSaid.hasMatch(text)) return false;
  if (words(text) > 6) return false;
  if (_task.hasMatch(text) ||
      _bulletCue.hasMatch(text) ||
      _headingCue.hasMatch(text) ||
      _quoteCue.hasMatch(text) ||
      numberCue.hasMatch(text) ||
      _checkboxCue.hasMatch(text) ||
      _dividerCue.hasMatch(text) ||
      _importantCue.hasMatch(text) ||
      _subheadingCue.hasMatch(text) ||
      _calloutCue.hasMatch(text) ||
      _hiddenCue.hasMatch(text) ||
      _choiceCue.hasMatch(text) ||
      _sumCue.hasMatch(text) ||
      _doneCue.hasMatch(text) ||
      _defineCue.hasMatch(text) ||
      enumeration(text) != null) {
    return false;
  }
  return true;
}
