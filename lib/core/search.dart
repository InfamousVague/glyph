/// What a search over the notes finds. A port of the page's one rule for it, `matches` in
/// `src/app/notes/allNotes.ts` (docs/DESIGN.md §115): the search is over the notes' words, not their names, and
/// every word typed must appear somewhere in the note, whatever the case, so "trip packing" finds the note with
/// both.
///
/// Nothing in the Rust core searches (docs/STAGE3.md): the page reads every note's body from `list_notes` and looks
/// through them itself. There is one rule on the web and it is used twice, by the home page (`home/homeLayout.ts`)
/// and by All notes (`notes/allNotes.ts`); the command bar's rows are matched by the kit's palette, over each row's
/// "Open <title>" and its keywords, which is the palette's own (lib/commands/palette.dart).
///
/// What differs: nothing in the rule. It was ported with the home page as lib/core/note_text.dart `matches`, and
/// that is the function here, under the web's name; [searchNotes] is the filter both pages write out by hand. The
/// one known difference is that port's, not this file's: it names a to-do's priority wherever its sign is written,
/// where the web reads the to-dos' fields (`core/taskFields.ts` `fieldsIn`, which comes with the tickets), so a `⏫`
/// inside inline code or a redaction is found as "high" here and not there.
library;

import 'note.dart';
import 'note_text.dart' as text;

/// Whether a note has every word of the query, in its title or its body, whatever the case (`matches`). A blank
/// query finds every note. A filled blank's hidden bracket is not the note's words, and a to-do's priority is found
/// by its name.
bool matches(Note note, String query) => text.matches(note, query);

/// The words of a query as the search reads them: lower case, split at any run of white space.
List<String> searchWords(String query) => [
      for (final word in query.toLowerCase().split(RegExp(r'\s+')))
        if (word.isNotEmpty) word,
    ];

/// Of [notes], those the query finds, in the order they were given; all of them for a blank query.
List<Note> searchNotes(Iterable<Note> notes, String query) {
  if (searchWords(query).isEmpty) return [...notes];
  return [
    for (final note in notes)
      if (text.matches(note, query)) note,
  ];
}
