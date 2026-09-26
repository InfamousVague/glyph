---
title: "Ghost.md: The Guide"
book: true
---
# Ghost.md: The Guide

_Everything Ghost.md does, and how it is made, in 44 short chapters. Parts I to VI need no technical background; Parts VII to XI are for someone who can read code._

Each chapter takes a few minutes. Tap Read straight through to go from the first page to the last, or open any chapter below; Previous and Next at the foot of each page carry on from there.

## Part I · Writing a note

1. [[The first five minutes]] — start here
2. [[A note is a Markdown file]]
3. [[Finding your way around]]
4. [[The marks you can type]]
5. [[Effects on words]]
6. [[Links between notes]]
7. [[Tags, footnotes and the small marks]]
8. [[Pictures and voice memos]]

## Part II · Speaking a note

9. [[Recording a note]]
10. [[Saying the marks]]
11. [[Commands after Hey Ghost]] — why every command asks first
12. [[Lists and to-dos]]

## Part III · Notes that are something else

13. [[Boards made of list items]]
14. [[Books, and reading one through]]
15. [[Canvases, cards and lines]]

## Part IV · The AI on your phone

16. [[The models on your phone]]
17. [[Asking the AI to work on a note]]
18. [[Spoken asks and the review]]

## Part V · Your notes, everywhere

19. [[Accounts, sync and the key you hold]]
20. [[Live typing]]
21. [[Sharing a note or a book]]

## Part VI · Making it yours

22. [[Notion and GitHub]]
23. [[Claude on your notes]]
24. [[Settings, one section at a time]]
25. [[The side key, the Fold and the Mac]]
26. [[What stays on your phone]]

## Part VII · The shape of the code

27. [[Ghost.md in one page]] — start here if you read code
28. [[No router, five screens]]
29. [[The native half]]

## Part VIII · Inside a note

30. [[The editor and its language]]
31. [[Formats that stay Markdown]]
32. [[The plugin seam]]

## Part IX · From voice to note

33. [[From microphone to Markdown]]
34. [[Reading a command, writing it safely]] — the guards between a voice and a write
35. [[The engines on the device]]

## Part X · Where notes live and travel

36. [[The library on disk]]
37. [[Sync and the end-to-end keys]]
38. [[Live typing over a relay]]
39. [[glyph-api, the server]]
40. [[The Claude connector, inside]]

## Part XI · Shipping and working on it

41. [[Over the air, and releases]] — the part that can lock a phone out
42. [[Tests, and the report that ships]]
43. [[Working on Ghost.md]]
44. [[Where the docs and the code disagree]]

## Five things worth knowing before you start

1. **A spoken command is read once, from the whole recording, after you tap Done.** Nothing heard mid-sentence can change a note, a card shows exactly what will be written before anything is, and, besides the asks for the AI, a finished recording today carries out two commands: adding to a note you name, and making a new list ([[Commands after Hey Ghost]]).
2. **The side key starts a note over the lock screen**, because Ghost.md takes the phone's digital-assistant role, and at Done a locked phone goes back behind its lock without showing the note to whoever is holding it ([[The side key, the Fold and the Mac]]).
3. **Your password never leaves the phone as itself.** It becomes two keys and only one is sent. Notes, pictures, recordings, settings and live keystrokes are sealed on the device before they go, and a share link carries its own key after the #, which a browser never sends, so the server keeps only what it cannot read ([[Accounts, sync and the key you hold]]).
4. **The AI signs its work.** A finished run adds "Ghost" to the note's authors, and every change it made stays marked in the note until you keep it, revert it or type over it ([[Asking the AI to work on a note]]).
5. **Every release carries its own test results.** A deploy runs all three suites first and refuses to ship a failure, and the report is built into the app: at 1.8.0-12, 3,046 of 3,169 tests passed, 123 were skipped and none failed, under Settings › Test results in Developer mode ([[Tests, and the report that ships]]).

## How this was made

This guide was written from Ghost.md's own source, at commit `a2a12e6` on main, and every chapter was then read against the code by a second pass. Where a doc and the code disagree, the code wins: the chapters say what the code does, and [[Where the docs and the code disagree]] lists each place that was found.
