# Lists and to-dos

_Bullets, numbered steps and things to do: how to write them, tick them, give them a due date, a priority and a person, find every open one, and turn a list into a board._

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

## When it is due, how much it matters, who it is for

A to-do can carry a due date, a priority and a person, written after its words in the signs Obsidian Tasks reads, so the same line is a task with a due date in Obsidian too.

| Type | You get |
|---|---|
| `📅 2026-10-03` | A due date. Drawn as **Tomorrow**, **Sat 3 Oct**, the year only when it is not this one. Red once it has passed and the box is not ticked, amber on the day, quiet once it is ticked |
| `🔺` `⏫` `🔼` `🔽` `⏬` | A priority, highest to lowest. Drawn as a small mark, chevrons up or down |
| `@sam` | A person. Drawn with their initial in a ring. `@sam-ortiz` is Sam Ortiz |
| `🛫 2026-10-02`, `⏳ 2026-10-05` | A start date and a scheduled date, drawn quieter: **Starts tomorrow**, **Scheduled Mon 5 Oct** |
| `✅ 2026-09-30` | The day it was done, as Obsidian Tasks writes it when you tick one there |
| `🔁 every week` | A repeat, kept with the to-do. Ghost.md does not make the next one yet |
| `[effort:: 3]` | Anything else, by name, as Dataview writes it |

Off the line you are writing, each is a chip; on it, the characters are there to edit. Tags stay tags: `- [ ] Fix the login loop @sam #bug ⏫ 📅 2026-10-03` is a to-do with a person, a tag, a priority and a due date.

- **Tap a due date** for Today, Tomorrow, Next week (its Monday), Pick a date, which opens your phone's own calendar, and Remove. A start or scheduled date offers the same.
- **Tap a priority** for the five and None. **Tap a person** to take them off.
- **Press and hold a to-do** for Due date, Priority and Assign beside its other actions. Assign offers the people this note already names, and Someone new, which writes the @ for you to type a name after.
- **The + has A to-do with a due date** under More: a to-do due tomorrow, its words ready to type over, and the date there to tap for another day.

Ghost.md writes each field where Obsidian Tasks looks for it: at the end of the words, a person before the dates, and all of it before the item's bookmark, its Notion mark, a counter and its anchor, so those still end the line. A to-do's words are what a card on a board, a task sent to Notion, an issue on GitHub and the home page's To do say: the fields are left out of them, and a board card shows the due date, the priority and the people as chips of its own.

## Progress under a heading

A heading with to-dos under it says how many are done, after its words: **3 of 7**, and **All 7 done** when every box is ticked. Nothing is typed and nothing is written into the note. The count runs to the next heading of the same level or higher, so a `##` counts the to-dos in its `###` sections too. A heading with no to-dos under it says nothing.

## Every open to-do, on the home page

The home page gathers every to-do not yet ticked, from all your notes, under **To do** with a count beside it. The note changed most recently comes first, and each note's to-dos come in the order it has them. It shows the first eight, then **and 12 more in your notes**.

- **Tap the box** to tick it there, without opening the note.
- **Tap the words** to open the note, at the item itself when the item has a name (an anchor, `^ship-page`).

The workspace chosen at the top decides which notes it reads. The archive is left out, and so are to-dos inside a block of code, which are examples rather than things to do. When the last one is ticked, the page says **Every to-do is done.**

## By voice

While recording, “Bullet point”, “Check box”, “Remember to …” and a list said in one breath all make lists as you talk ([[Saying the marks]]). Say a field at the end of an item and it is written as one: “Remember to call the plumber due Friday, high priority” is `- [ ] Call the plumber ⏫ 📅` and Friday's date, and “… for Sam” or “… assigned to Sam” puts `@Sam` on it. To add to another note's list without opening it, say it: “Add oat milk and rye bread to Groceries.” The words go into the list they fit, in its own style, bullets, numbers or boxes, as you say them, and the note opens with an Undo when you tap Done. In a note with several lists, a thing goes under the heading that shares its words; a to-do goes to a to-do list ([[Spoken commands]]). A new list can be made by voice too: “Make a new list called Packing with toothbrush, socks and charger”, said first, shows a card at Done, and **Create** makes the note.

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
| `📅 2026-10-03`, `⏫` | A task with a due date and a priority in Obsidian with the Tasks plugin; the signs, as written, elsewhere |
| `@sam`, `[effort:: 3]` | The words as written; Dataview reads `[effort:: 3]` as a field |
| `^ship-page` | A block id in apps that have them, plain words in the rest |
| A board | A block of code naming its columns, above a list that is still all there |
| **3 of 7** after a heading | Nothing: it was never written |

## Read next

- [[Boards made of list items]]
- [[Notion and GitHub]]
- [[Spoken commands]]
