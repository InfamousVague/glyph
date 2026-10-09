/// What changed a live document's words from elsewhere, in order, and an editor's own change carried over it.
///
/// The web's editor is bound to its `Y.Text` in one thread (y-codemirror): a change that arrives and a key pressed
/// never cross. Here the document is in the Rust core, a call away (lib/team/crdt.dart), so a key can be pressed
/// between an update being handed to the core and its words coming back: the editor's change was made against
/// words the document has already left. So every change from elsewhere is kept here as a [TextSplice] with a
/// number ([TextLog.rev]); an editor says which number its words were at when it made a change, and the change is
/// moved over every splice since ([TextLog.carry]) before the core is given it. The editor is told each splice
/// in turn and maps it over what it has typed meanwhile (lib/live/editor_binding.dart), so the two arrive at the
/// same words; should they ever not, the binding brings the editor to the document's.
///
/// A splice is one stretch: the common head and foot of the words before and after are kept, and what lies between
/// went and came. An update that changed two places far apart is one long stretch here, which is still the same
/// change of the words.
library;

import 'crdt.dart';

/// One change of the words from elsewhere: [removed] code units gone at [at], then [inserted] put there. [rev] is
/// the log's number once it was made.
class TextSplice {
  const TextSplice({required this.rev, required this.at, required this.removed, required this.inserted});

  final int rev;
  final int at;
  final int removed;
  final String inserted;

  @override
  String toString() => 'TextSplice($rev: $removed gone at $at, "$inserted" come)';
}

bool _high(int unit) => unit >= 0xD800 && unit < 0xDC00;
bool _low(int unit) => unit >= 0xDC00 && unit < 0xE000;

/// The one stretch that turns [before] into [after], or null when they are the same words. Never between the two
/// halves of a character, as the core's own diff is not (native/src/crdt.rs `reconcile`).
({int at, int removed, String inserted})? spliceBetween(String before, String after) {
  if (before == after) return null;
  final most = before.length < after.length ? before.length : after.length;
  var head = 0;
  while (head < most && before.codeUnitAt(head) == after.codeUnitAt(head)) {
    head += 1;
  }
  if (head > 0 && _high(before.codeUnitAt(head - 1))) head -= 1;
  var foot = 0;
  while (foot < most - head && before.codeUnitAt(before.length - 1 - foot) == after.codeUnitAt(after.length - 1 - foot)) {
    foot += 1;
  }
  if (foot > 0 && _low(before.codeUnitAt(before.length - foot))) foot -= 1;
  return (at: head, removed: before.length - head - foot, inserted: after.substring(head, after.length - foot));
}

/// How many splices are kept: far more than can pass between a key and the core's answer.
const int _kept = 256;

/// The changes from elsewhere, numbered.
class TextLog {
  final List<TextSplice> _splices = [];

  /// How many changes from elsewhere these words have taken.
  int rev = 0;

  /// The words went from [before] to [after] by a change from elsewhere: the splice, or null when nothing changed.
  TextSplice? record(String before, String after) {
    final found = spliceBetween(before, after);
    if (found == null) return null;
    rev += 1;
    final splice = TextSplice(rev: rev, at: found.at, removed: found.removed, inserted: found.inserted);
    _splices.add(splice);
    if (_splices.length > _kept) _splices.removeAt(0);
    return splice;
  }

  /// [edits], made against the words as they were at [base], as the same change of the words as they are now.
  /// Throws a [StateError] when [base] is older than what is kept, which a bound editor heals by reading the
  /// document's words again.
  List<CrdtEdit> carry(List<CrdtEdit> edits, int base) {
    if (base >= rev) return edits;
    if (_splices.isEmpty || _splices.first.rev > base + 1) throw StateError('That change was made against words too old to carry it over.');
    var carried = edits;
    for (final splice in _splices) {
      if (splice.rev > base) carried = carryOver(carried, splice);
    }
    return carried;
  }
}

/// [edits] moved over [splice], which happened first. Each edit is against the words as the edits before it left
/// them, before and after. A change here at the very place the splice put words stays in front of them.
List<CrdtEdit> carryOver(List<CrdtEdit> edits, TextSplice splice) {
  // The splice, in the words as the edits so far left them.
  var at = splice.at, gone = splice.removed;
  final came = splice.inserted.length;
  final out = <CrdtEdit>[];
  for (final edit in edits) {
    final from = edit.index, to = edit.index + edit.remove, put = edit.insert.length;
    // A place in the edit's words, in the words after the splice. [late]: at the splice's own place, after what it
    // put there.
    int placed(int pos, {required bool late}) {
      if (pos < at || (pos == at && !(late && gone == 0))) return pos;
      if (pos >= at + gone) return pos + came - gone;
      return at + came;
    }

    final start = placed(from, late: edit.remove > 0);
    var end = placed(to, late: false);
    if (end < start) end = start;
    out.add(CrdtEdit(start, remove: end - start, insert: edit.insert));
    // And the splice, in the words after this edit.
    int moved(int pos, {required bool end}) {
      if (pos < from || (pos == from && (end || edit.remove > 0))) return pos;
      if (pos >= to) return pos - edit.remove + put;
      return end ? from : from + put;
    }

    final nextAt = moved(at, end: false);
    var nextEnd = moved(at + gone, end: gone > 0);
    if (nextEnd < nextAt) nextEnd = nextAt;
    at = nextAt;
    gone = nextEnd - nextAt;
  }
  return out;
}
