/**
 * The example board (docs/BOARDS.md): a note that is a working board, added from Settings.
 *
 * Matt: "make an example note with this functionality". Everything in it is the standard and nothing else - a fence
 * of columns, to-dos with anchors, and ordinary words around them - so the note reads as a plan wherever it is
 * opened, and Glyph draws the board at the top of it with the tasks below as the tasks they are.
 */

export const BOARD_TITLE = 'Launch week';

export function boardNoteBody(): string {
  return `# ${BOARD_TITLE}

A board is two ordinary things: this fence, which lays out the columns, and the to-dos under it, each ending with a
name after a \`^\`. The cards are those tasks. Tick one here and the to-do below is ticked; tap its words and you land
on the line.

\`\`\`board
This week: pricing-page, beta-list
Waiting on Sam: photos
Done: launch-date
\`\`\`

## The work

- [ ] Write the pricing page ^pricing-page
- [ ] Email the beta list ^beta-list
- [ ] Get the photos back from Sam ^photos
- [x] Pick the launch date ^launch-date
- [ ] Book the venue, which is not on the board at all

## How to change it

- Move a card with the chevrons on it; the fence above is rewritten.
- Add a task by writing another to-do with a name at the end, then putting that name in a column.
- Take a card off the board by taking its name out of the fence. The task stays in the note.
- Tap the fence itself to edit the columns as text: rename one, add one, reorder them.

A second board in the same note is another fence, and a task can sit on both.

\`\`\`board
Someday: venue
\`\`\`

- [ ] Find a venue for the party ^venue
`;
}
