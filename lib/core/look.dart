/// How a note looks (docs/DESIGN.md §144): one flat key in its front matter, `look:`, with two values, `map` and
/// `reading`. The web app's `src/app/core/look.ts`.
///
/// What differs: nothing is written here. The three names were ported with the templates that write them
/// (lib/notes/note_templates.dart, which needed `withFrontMatterValue` first), and this file is where the web's
/// module is, handing them on under its name so the note's screen imports a look from where the page does.
library;

export '../notes/note_templates.dart' show Look, lookOf, withLook;
