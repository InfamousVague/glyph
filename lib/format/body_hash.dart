/// The hash a kept thing is written against: the home page's gist (format/gist.dart), the AI's marks on a note
/// (ai/marks.dart), and the body a run was written from (format/pipeline.dart `noteHash`). A port of
/// `src/app/format/bodyHash.ts`.
///
/// A thing is kept with a hash of the exact body it came from, not the body's time: the editor saves on a debounce,
/// so "the time the body last changed" and "the body the model read" can name different texts inside the same
/// second. A hash of the text itself cannot.
///
/// What differs: the page works in `BigInt` masked to 64 bits; a Dart `int` on the phone and the desktop is 64 bits
/// and its multiplication wraps, which is the same sum. The answer is the web's number for the same text, bit for
/// bit, and test/format/body_hash_test.dart pins it. (Compiled to JavaScript an `int` is a double and this would
/// not hold; the port does not run there.)
library;

/// FNV-1a over the UTF-16 code units, folded to 52 bits so it survives JSON and an i64 column unchanged. Not
/// cryptographic: it only has to tell two texts apart, and a collision costs one missing "changed since" hint.
int bodyHash(String text) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (var i = 0; i < text.length; i += 1) {
    hash ^= text.codeUnitAt(i);
    hash *= prime;
  }
  return hash & 0xfffffffffffff;
}
