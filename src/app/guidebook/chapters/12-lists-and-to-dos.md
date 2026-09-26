# Lists and to-dos

_Bullets, numbered steps and things to do: how to write them, tick them, find every open one, and turn a list into a board._

## The kinds of list

| Type | You get |
|---|---|
| `- Oat milk` | A bullet. `*` and `+` work too |
| `1. Unplug it` | A numbered step. `1)` works too |
| `- [ ] Book the cabin` | A to-do, with a box to tick |
| `- [x] Call Sam` | A to-do that is done |

Indent a line under an item to nest it. A numbered list can hold to-dos (`1. [ ] Unplug it`), and so can a `*` list.

## Writing one

- **Enter carries a list on.** The next line starts with the next bullet or the next number, and under a `- [ ]` to-do, a new empty box.
- **Enter on an empty item** takes its marker away, which ends the list.
- **Backspace just after a marker** takes the whole marker off at once, a to-do's box and all, not a character at a time.

## Ticking

Tap a to-do's box to tick it, and tap again to clear it. Only the box does this: the words beside it are for writing, and a tap there puts the caret in them. A tick is an ordinary edit, saved like typing, and one Undo takes it back.

If the to-do is a card on a board, ticking it moves the card to Done, and clearing it moves the card back to the first lane.

Choices sit on list lines too: `- ( ) Tent`, a group of them side by side, one of which can be picked. Counters, `[3/8]`, can sit anywhere in a line, a list item's most often: a tap adds one, a hold takes one away. [[Tags, footnotes and the small marks]] has them.

## Progress under a heading

A heading with to-dos under it says how many are done, after its words: **3 of 7**, and **All 7 done** when every box is ticked. Nothing is typed and nothing is written into the note. The count runs to the next heading of the same level or higher, so a `##` counts the to-dos in its `###` sections too. A heading with no to-dos under it says nothing.

## Every open to-do, on the home page

The home page gathers every to-do not yet ticked, from all your notes, under **To do** with a count beside it. The note changed most recently comes first, and each note's to-dos come in the order it has them. It shows the first eight, then **and 12 more in your notes**.

- **Tap the box** to tick it there, without opening the note.
- **Tap the words** to open the note, at the item itself when the item has a name (an anchor, `^ship-page`).

The workspace chosen at the top decides which notes it reads. The archive is left out, and so are to-dos inside a block of code, which are examples rather than things to do. When the last one is ticked, the page says **Every to-do is done.**

## By voice

While recording, “Bullet point”, “Check box”, “Remember to …” and a list said in one breath all make lists as you talk ([[Saying the marks]]). To add to another note's list without opening it, record a command: “Hey Ghost, add oat milk and rye bread to Groceries.” The list keeps its own style, bullets, numbers or boxes, and nothing is added until you tap Add ([[Commands after Hey Ghost]]).

## Linked to Notion or GitHub

A to-do linked to a Notion task or a GitHub issue ends with a small mark, and the two tick together, both ways. Tick the box and the task is marked done, or the issue closed. Finish the task or close the issue, and the box ticks itself the next time the note is open and reads the task back. [[Notion and GitHub]] says how to link a note.

When a note is linked to a Notion board or a GitHub repository, a to-do or a bullet that is not linked yet can be swiped left. The line follows your finger, a tile behind it says **Notion** or **GitHub**, and letting go far enough sends the item. It becomes a task or an issue, and the line gets its mark. Short of that point, the line springs back. The press-and-hold menu offers the same send for the line you are on.

## From a list to a board

A list can become a board, and stays a list while it is one: every item is still a line of the note.

| Where | What it does |
|---|---|
| The More sheet (the three dots) › **Make a board** | Every item in the note becomes a card. A board with **To do**, **Doing** and **Done** goes in under the title, with ticked items already in Done |
| Press and hold › **Board from list** | Only the list you are on, or the lines you have selected, becomes a board, set in just above it |
| Press and hold › **Add to board** | An item not on a board yet joins the board its neighbours are on, or the nearest one above it: in the first lane, or in Done if it is ticked |

Each item is given a name at the end of its line, like `^ship-page`, and the board is a short block that lists those names by column. [[Boards made of list items]] has the whole of it.

## In any other app

A list is plain Markdown, so it reads anywhere.

| In the note | Elsewhere |
|---|---|
| `- [ ] Book the cabin` | A task list, drawn with a box in most Markdown apps |
| `1. Unplug it` | A numbered list |
| `- ( ) Tent` | A bullet that starts with brackets |
| `[3/8]` | The words `[3/8]` |
| `^ship-page` | A block id in apps that have them, plain words in the rest |
| A board | A block of code naming its columns, above a list that is still all there |
| **3 of 7** after a heading | Nothing: it was never written |

## Read next

- [[Boards made of list items]]
- [[Notion and GitHub]]
- [[Commands after Hey Ghost]]
