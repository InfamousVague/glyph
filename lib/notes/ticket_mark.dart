/// A ticket says so where it is listed (docs/DESIGN.md §157): its key and its status, small and quiet, the status in
/// its category's colour. The web's `src/app/notes/TicketMark.tsx`.
///
/// The mark itself was ported with the home page, beside the page that draws it: [TicketMark] in
/// lib/home/marks.dart, which the All notes cards draw through lib/home/note_card.dart. This file hands it on under
/// the web's own place, `notes/`, so nothing that lists a ticket has to know where it lives.
///
/// What differs: `TicketStatusButton`, the status as a button in a notebook's own list (docs/DESIGN.md §169), is not
/// here. It is drawn with the editor's `StatusIcon` and `statusLook` (`editor/FieldPicker.tsx`,
/// `editor/fieldPicks.ts`) and opens the sheet of a notebook's workflow, none of which is ported; it comes with the
/// notebook's page.
library;

export '../home/marks.dart' show TicketMark;
