/// Spell-check in the note's editor (docs/PARITY.md, Missing 11): the phone's checker asked about the words near
/// the caret, and a red wave under each it would have otherwise.
///
/// - spell_check.dart: the checker as a seam ([SpellChecker]) and the phone's own ([PhoneSpellChecker]);
/// - spell_marks.dart: the misspellings on the state, their wave, and what a menu needs to offer a word's
///   suggestions ([misspellingAt], [replaceMisspelling]);
/// - spell_watch.dart: what is asked and when ([spellCheck], the extension an editor takes).
///
/// An editor has it by taking [spellCheck] among its extensions; lib/root/note_desk.dart gives it to a note's.
library;

export 'spell_check.dart';
export 'spell_marks.dart';
export 'spell_watch.dart';
