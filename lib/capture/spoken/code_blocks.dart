/// Code said aloud: "code block in bash. npm run build. End code block." is a fenced block, a line for each sentence
/// said, lower case and without the commas Whisper puts at its pauses, as a command is typed. A port of
/// `src/app/capture/spoken/codeBlocks.ts`.
///
/// A code block runs until its "end code block" however long the pauses inside it were, so the paragraphs a pause
/// would have made are put back together first ([withCodeBlocksWhole]), and then each paragraph is cut around the
/// blocks said in it ([codeBlocksIn]). Pure.
///
/// What differs: the web's `Piece` is words or a fence `Block`; here it is a sealed class, [PieceText] for the words
/// and [PieceFence] holding the fence's block.
library;

import '../../core/text.dart';
import 'blocks.dart';

const String _codeLanguages = r'java\s?script|type\s?script|python|rust|bash|shell|json|html|css|sql|swift|kotlin|yaml|ruby|go';

/// "Code block in bash. npm run build. End code block.": a block of code, a line for each sentence said.
final RegExp _codeBlockSaid = RegExp(
  r'\bcode\s?block\b[.,:]?\s*(?:(?:in\s+|and\s+)?('
  '$_codeLanguages'
  r')\b[.,:]?\s*)?([\s\S]*?)[.,;]?\s*\b(?:end|and)\s+code\s?block\b[.,!]?',
  caseSensitive: false,
);
final RegExp _codeBlockOpen = RegExp(r'\bcode\s?block\b', caseSensitive: false);
final RegExp _codeBlockClose = RegExp(r'\b(?:end|and)\s+code\s?block\b', caseSensitive: false);

/// Paragraphs with a spoken code block kept in one, however long the pauses inside it were.
List<String> withCodeBlocksWhole(List<String> paragraphs) {
  final out = <String>[];
  var open = false;
  for (final paragraph in paragraphs) {
    if (open) {
      out[out.length - 1] = '${out[out.length - 1]} $paragraph';
    } else {
      out.add(paragraph);
    }
    final opened = _codeBlockOpen.allMatches(out.last).length;
    final closed = _codeBlockClose.allMatches(out.last).length;
    open = opened > closed;
  }
  return out;
}

/// A stretch of a paragraph: words, or a code block said in it (`Piece`).
sealed class Piece {
  const Piece();
}

/// Words (`kind: 'text'`).
class PieceText extends Piece {
  const PieceText(this.text);
  final String text;
}

/// A code block said (`kind: 'fence'`): the block as it is laid out.
class PieceFence extends Piece {
  const PieceFence(this.block);
  final Block block;
}

final RegExp _afterStop = RegExp(r'(?<=[.;!?])\s+');
final RegExp _lineEnd = RegExp(r'[.;,]+$');
final RegExp _space = RegExp(r'\s+');

/// A paragraph cut around the code blocks said in it.
List<Piece> codeBlocksIn(String paragraph) {
  final pieces = <Piece>[];
  var from = 0;
  for (final found in _codeBlockSaid.allMatches(paragraph)) {
    final code = (found.group(2) ?? '')
        .split(_afterStop)
        .map((line) => line.trim().replaceFirst(_lineEnd, '').replaceAll(',', '').toLowerCase())
        .where((line) => line.isNotEmpty)
        .toList();
    if (code.isEmpty) continue;
    final before = paragraph.substring(from, found.start < from ? from : found.start).trim();
    if (before.isNotEmpty) pieces.add(PieceText(before));
    pieces.add(PieceFence(Block(BlockKind.fence, code.join('\n'), lang: (found.group(1) ?? '').toLowerCase().replaceAll(_space, ''))));
    from = found.end;
  }
  final rest = paragraph.substring(from).trim();
  if (rest.isNotEmpty || pieces.isEmpty) pieces.add(PieceText(capitalise(rest)));
  return pieces;
}
