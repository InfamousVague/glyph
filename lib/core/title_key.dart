/// A title as it is matched: what a person said, not what they typed. A port of `src/app/core/titleKey.ts`, one to
/// one.
///
/// Lower case, every run of anything that is not a letter or a digit one space, the ends trimmed - so "The Oaks!" and
/// "the oaks" are one note, and a title said aloud finds the note however it was punctuated. Every place that asks
/// whether two titles are the same note asks it this way: a link and the note it opens, a book's index and its pages
/// (book.dart), the aside's groups, a spoken link and the titles it could mean.
///
/// A leaf with no imports on purpose, so that nothing which needs the key can make a cycle by importing it.
///
/// What differs: nothing. The key is ASCII letters and digits and single spaces, so Dart's `trim` and JavaScript's
/// take the same space off its ends.
library;

final RegExp _notWord = RegExp(r'[^a-z0-9]+');

/// [title] reduced to what is matched: "  The Oaks!  " -> "the oaks". Empty for a title with no letters or digits.
String titleKey(String title) => title.toLowerCase().replaceAll(_notWord, ' ').trim();

/// Whether two titles are one note's: the same key, and a key with something in it.
bool sameTitle(String one, String two) {
  final key = titleKey(one);
  return key != '' && key == titleKey(two);
}
