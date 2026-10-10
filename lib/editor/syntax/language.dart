/// The markdown the editor speaks: GFM, with one CommonMark rule taken out, and whatever inline formattings the
/// switched-on plugins add. A port of `src/app/editor/language.ts`.
///
/// In CommonMark a line of dashes or equals signs under a paragraph turns the paragraph into a heading (a "setext"
/// heading). On a phone that rule bites: typing `-` to start a list under a line promoted the line above it, and the
/// person was "stuck in headings". Here `#` is the only way to make a heading; a lone `-` is an empty list item and
/// `---` is a rule.
///
/// A plugin's formatting is a delimiter run that opens and closes a node, parsed the way GFM's `~~` is: the Spoiler
/// mark's `||secret||` becomes a `Spoiler` node holding two `SpoilerMark`s and the words.
///
/// What differs: the web's `glyphMarkdown` answers a CodeMirror `Extension` (`markdown({...})`), with the key
/// bindings and the paste handling in it; here it answers the [MarkdownParser] alone, and those are the editor's
/// (lib/editor/commands, lib/editor/input). A fenced block is not parsed by its own language here, nor an HTML
/// block by HTML: both stay `CodeText` and `HTMLBlock` with nothing inside, and what `codeLanguages` and the HTML
/// parser do on the web is done beside the tree, for the blocks on screen (lib/editor/code/code_highlight.dart).
library;

import 'extension.dart';
import 'markdown.dart';

/// What the parser needs of a plugin's formatting (`plugins/types.ts` `InlineFormat`): its node's name and the run
/// that opens and closes it. The marks' own type (lib/editor/marks) carries a look, a cue and an icon besides, and
/// implements this.
abstract interface class InlineFormatSyntax {
  /// The node's name, and with `Mark` after it the name of each delimiter's node: `Spoiler`, `SpoilerMark`.
  String get name;

  /// The run either side of the words: `||`, `==`, or an emoji twice.
  String get delimiter;
}

/// An [InlineFormatSyntax] with nothing else to it.
class InlineFormat implements InlineFormatSyntax {
  const InlineFormat(this.name, this.delimiter);

  @override
  final String name;

  @override
  final String delimiter;
}

/// `@codemirror/lang-markdown`'s `markdownLanguage`: CommonMark with GFM, subscript, superscript and emoji.
final MarkdownParser markdownLanguage = parser.configure([...gfm, subscript, superscript, emoji]);

/// The parser for a note, with the [formats] the switched-on plugins add.
MarkdownParser glyphMarkdown([Iterable<InlineFormatSyntax> formats = const []]) {
  // GFM: the default `commonmarkLanguage` has no strikethrough and no task lists, both of which a notes app wants.
  return markdownLanguage.configure([
    const MarkdownConfig(remove: ['SetextHeading']),
    for (final format in formats) _inlineFormat(format),
  ]);
}

/// The characters CommonMark counts as punctuation when deciding whether a delimiter opens or closes.
final RegExp _punctuation = RegExp(r'''[!"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|}~\xA1‐-‧]''');

final RegExp _spaceOrEdge = RegExp(r'\s|^$');

/// What a delimiter is a run of: the shortest piece it repeats. `||` is a run of `|`, and `🔥🔥` a run of `🔥`, which
/// is two UTF-16 code units (and `❄️❄️` a run of `❄️`, a character and its variation selector). The parser counts in
/// code units, as the editor's positions do, so the piece is kept as a string and compared whole rather than as one
/// code.
String delimiterUnit(String delimiter) {
  for (var size = 1; size <= delimiter.length ~/ 2; size += 1) {
    if (delimiter.length % size != 0) continue;
    final unit = delimiter.substring(0, size);
    if (unit * (delimiter.length ~/ size) == delimiter) return unit;
  }
  return delimiter;
}

/// The parser's piece for one plugin formatting: `delimiter` opens and closes a `name` node, with the flanking rules
/// GFM's strikethrough uses, so a run next to a space can only open on its far side and only close on its near one.
/// A longer run of the same character is not this formatting.
///
/// The delimiter is a run of one piece ([delimiterUnit]): a character, as `||` is, or an emoji, as the effects'
/// `🔥🔥` is. A longer run of the piece is not this formatting either way, so three flames are three flames.
MarkdownConfig _inlineFormat(InlineFormatSyntax format) {
  final name = format.name, delimiter = format.delimiter;
  final mark = '${name}Mark';
  final type = DelimiterType(resolve: name, mark: mark);
  final unit = delimiterUnit(delimiter);
  final code = delimiter.codeUnitAt(0);
  final length = delimiter.length;
  return MarkdownConfig(
    defineNodes: [NodeSpec(name), NodeSpec(mark)],
    parseInline: [
      InlineParser(
        name: name,
        parse: (cx, next, pos) {
          if (next != code) return -1;
          if (cx.slice(pos, pos + length) != delimiter) return -1;
          // A longer run of the piece, either side, is not this formatting.
          if (cx.slice(pos + length, pos + length + unit.length) == unit ||
              (pos - unit.length >= cx.offset && cx.slice(pos - unit.length, pos) == unit)) {
            return -1;
          }
          final before = cx.slice(pos - 1, pos);
          final after = cx.slice(pos + length, pos + length + 1);
          final spaceBefore = _spaceOrEdge.hasMatch(before);
          final spaceAfter = _spaceOrEdge.hasMatch(after);
          final punctBefore = _punctuation.hasMatch(before);
          final punctAfter = _punctuation.hasMatch(after);
          return cx.addDelimiter(
            type,
            pos,
            pos + length,
            !spaceAfter && (!punctAfter || spaceBefore || punctBefore),
            !spaceBefore && (!punctBefore || spaceAfter || punctAfter),
          );
        },
        after: 'Emphasis',
      ),
    ],
  );
}
