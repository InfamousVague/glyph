/// The two small measures every spoken-markdown rule takes of a sentence: its words without the stop Whisper put
/// after them, and how many words it has. A port of `src/app/capture/spoken/words.ts`.
///
/// A cue's content is written without its stop ("Heading, groceries." is `## Groceries`), and most rules are held to
/// short sentences, because a long one is prose however it starts.
///
/// What differs: nothing.
library;

final RegExp _end = RegExp(r'[\s.,;:!?]+$');
final RegExp _space = RegExp(r'\s+');

/// [text] without the spaces and stops at its end: "Groceries. " is "Groceries".
String stripEnd(String text) => text.replaceFirst(_end, '');

/// How many words [text] has.
int words(String text) => text.trim().split(_space).where((word) => word.isNotEmpty).length;
