/// The hand under the text: which keystrokes are worth a taptic, and which are not. A port of
/// `src/app/editor/feel.ts`.
///
/// The brief asks for feedback "as styles and effects are applied", and the whole difficulty is in the word
/// "applied". A person typing `**bold**` passes through several plausible moments - the first `*`, the second, the
/// closing pair - and only ONE of them is the moment the text actually became bold. Firing on the others is worse
/// than firing on none: the hand learns that the buzz means nothing.
///
/// So the test is structural, not textual. A style was applied when a node exists in the syntax tree AFTER the
/// transaction that did not exist at that position BEFORE it. That is true exactly once per mark, and it is false
/// inside a fenced code block (where `**` is just two asterisks and a regex would happily lie).
///
/// Compositions are skipped entirely. An IME rewrites the same characters over and over as candidates change, and
/// each rewrite would look like new syntax appearing. The rule is simple: nothing is "applied" until the
/// composition commits, and the committing transaction is not itself a compose event.
///
/// What differs: the web asks `syntaxTreeAvailable` and stays silent without a parsed tree at the caret; here the
/// tree is always whole (syntax_tree.dart), so that silence never happens, at the price of a parse of each side of
/// the transaction until the view keeps a tree. [feelTransaction] is handed the two things it fires, `fireFelt` and
/// `fireMicroTick` of core/haptics.ts, which are the app's and not the editor's; [feltAs] is the same vocabulary
/// as a value.
library;

import '../../core/item_syntax.dart';
import '../state/state.dart';
import '../syntax/syntax.dart';
import 'syntax_tree.dart';

/// Inline marks worth a tick when they close.
const Set<String> _inline = <String>{'StrongEmphasis', 'Emphasis', 'Strikethrough', 'InlineCode', 'Link'};

/// Block forms worth a tap when they are created.
final RegExp _block = RegExp(r'^(ATXHeading[1-6]|Blockquote|ListItem|FencedCode|HorizontalRule)$');

/// Every character this transaction inserted, in order.
String _insertedText(Transaction tr) {
  final typed = StringBuffer();
  tr.changes.iterChanges((fromA, toA, fromB, toB, inserted) {
    typed.write(inserted.toString());
  });
  return typed.toString();
}

/// What a transaction is worth (`FeelKind`). `continue` is a keyword, so a list continuing itself is
/// [FeelKind.continued].
enum FeelKind { mark, heading, block, continued }

/// A newline and the marker the markdown keymap writes after it, in a quote or not, with a to-do's box if it had
/// one.
final RegExp _continued = RegExp('^\\n[\\s>]*$markerPattern\\s*(?:$boxPattern\\s*)?\$');

final RegExp _closer = RegExp(r'[*_~`)\]]$');

/// What this transaction is worth, or null. Pure, so the decision can be tested without a Taptic Engine to feel it.
FeelKind? feelOf(Transaction tr) {
  if (!tr.docChanged) return null;
  if (tr.isUserEvent('input.type.compose')) return null;

  final typed = _insertedText(tr);
  if (typed.isEmpty) return null;

  // A list continuing itself onto the next line: the markdown keymap inserted the marker, so the newline arrives
  // with more than just "\n" in it.
  if (typed.startsWith('\n') && typed.length > 1 && _continued.hasMatch(typed)) return FeelKind.continued;

  if (!tr.isUserEvent('input.type')) return null;
  final head = tr.state.selection.main.head;
  final tree = syntaxTree(tr.state);

  // Both branches below need the same thing: where the caret's position in the NEW document sat in the OLD one, so
  // the two trees can be asked about the same spot. `tr.changes.mapPos` is the wrong direction - it maps old to new,
  // and handing it a new-document position throws outright once the document has grown past the old length.
  // `invertedDesc` is the map the other way.
  final toOld = tr.changes.invertedDesc;

  // A closing delimiter was typed: did it actually close something?
  //
  // This check FALLS THROUGH rather than returning when it finds nothing, because the two character sets overlap. A
  // backtick closes inline code and also, as the third of three, opens a fenced block; an early return here meant
  // ``` never registered as a block at all.
  if (_closer.hasMatch(typed)) {
    final closed = enclosing(tree, head, _inline.contains);
    if (closed != null && closed.to == head) {
      final before = enclosing(syntaxTree(tr.startState), toOld.mapPos(head, -1), (name) => name == closed.name);
      if (before == null) return FeelKind.mark;
    }
  }

  // Did this keystroke create a block?
  //
  // Deliberately NOT gated on which character was typed. The obvious gate - a space, because a heading is "# " - is
  // wrong, and measurably so: the grammar promotes the line the moment the MARKER lands, before any space. `#`
  // alone parses as ATXHeading1, `>` as Blockquote, `-` as ListItem, `---` as HorizontalRule, three backticks as
  // FencedCode. Since the text visibly changes size and colour at that same instant, that instant is what the thumb
  // should feel.
  final line = tr.state.doc.lineAt(head);
  // One character in, so an empty line's start does not resolve into the node that precedes it.
  final probe = line.from + 1 < line.to ? line.from + 1 : line.to;
  final after = enclosing(tree, probe, _block.hasMatch);
  if (after == null) return null;
  final before = enclosing(syntaxTree(tr.startState), toOld.mapPos(probe, 1), _block.hasMatch);
  if (before != null && before.name == after.name) return null;
  return after.name.startsWith('ATXHeading') ? FeelKind.heading : FeelKind.block;
}

/// The vocabulary, in one place so it can be read as a sentence: a mark closing is a tick (`selection`), a heading
/// is heavier (`medium`) because it changes the shape of the page, any other block is `light`, and a list
/// continuing itself is texture rather than news (`tick`, the micro tick). Null for nothing.
String? feltAs(FeelKind? kind) => switch (kind) {
  FeelKind.mark => 'selection',
  FeelKind.heading => 'medium',
  FeelKind.block => 'light',
  FeelKind.continued => 'tick',
  null => null,
};

/// Fires what a transaction is worth: `fireFelt` with a haptic's kind, or `fireMicroTick` for a list continuing.
void feelTransaction(Transaction tr, {required void Function(String kind) fireFelt, required void Function() fireMicroTick}) {
  final felt = feltAs(feelOf(tr));
  if (felt == null) return;
  if (felt == 'tick') {
    fireMicroTick();
  } else {
    fireFelt(felt);
  }
}
