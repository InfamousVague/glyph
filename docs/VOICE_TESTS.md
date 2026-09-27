# Voice tests

## The suite: one recording per feature

`voice-tests/suite.json` is the whole list: every spoken cue, command and recording behaviour, one short recording
each, with the notes it must leave. `npm run voice:text` writes it out as a script to record from
(`~/Desktop/Glyph voice tests.txt`), and `python3 scripts/voice-tests/make_audio.py --voice <id>` makes the recordings
with ElevenLabs into `~/Desktop/glyph-voice-tests/` (`--say <voice>` uses macOS's own voice instead, to try it
without a key).

Two runs check it:

- **From the scripts**, always, in `npm test` (`src/app/capture/voiceSuite.test.ts`): each line is one phrase with
  its silence, replayed through the live reader (`src/app/capture/liveRoute.ts`) against the standard notes, on the
  clock the phone would commit it at, and written as the recorder's Done writes (`src/app/capture/liveTake.ts`). This
  is the rules.
- **From the audio**, `npm run voice:suite`, which is `voice:hear` and then `voice:check`. `voice:hear` has Whisper on
  this Mac hear each recording through the phone's streaming path (`src-tauri/src/whisper/suite.rs`, a `cargo test`
  marked ignored), writing what it heard into a `.heard` folder beside the files. `voice:check` is the same Vitest
  file again with `GLYPH_VOICE=1`, checking what was heard. This is the rules against real speech.
  `GLYPH_VOICE_ONLY=051 npm run voice:hear` hears one, and `GLYPH_VOICE_DIR` points both at another folder of
  recordings.

A test's `prefs` can switch on "Stop when I go quiet" (`quietStop`) or switch off the keyword (`commandWord`). Those
are the only two. A test's `choose` answers a card that asks which note, as it comes up: a title to tap, `new` or
`keep`; without it, the card takes its own default, Keep here.

**What the suite drives, and what the app does.** The suite plays what the recorder runs: each phrase through the live
reader, which carries out "Glyph, add … to <note>" and its like as they are said (DESIGN §126), and the writes Done
makes, each note once, the words placed where they fit (`src/app/capture/place.ts`). So its "Commands" group says a
command and is done: there is no "Yes." to confirm it any more. A command the live reader does not carry out is read
once, from the whole recording, at Done (`src/app/ai/instruction.ts`), which `src/app/capture/CaptureScreen.test.tsx`
holds; docs/instruction-voice-commands.md is what each reader can do.

**Cut tests.** The tests of what the recorder no longer does went with it (DESIGN §127), and their numbers are not
used again: 057 (a spoken "no"), 063 to 065 (a table), 068 (a plugin), 070 and 071 (moving a card, making a board),
072 and 073 (a voice memo said aloud). `skip` in `voice-tests/suite.json` still holds a test back under its reason;
none is held back now.

**Matt's cases.** 093 to 100 are the ways "add a note to house to do's, the note is call an electrician…" was said and
came out wrong before §126: in two phrases, with ", the note is", as "house chores", after "Hey, like", after "Hey
goes", with a pause inside the name, into a note with two lists, and as a one-shot mid-take. 101 answers a card
(`choose`). Their audio is still to be made: `python3 scripts/voice-tests/make_audio.py --voice <id> --take 093` and
on.

**Taking it back.** 103 to 110 are the take-backs (DESIGN §130): "scratch that" once and twice, "actually, …" before
the sentence again and before a new one, "scratch that, add it to groceries instead" in one breath and in two, an
item said for a note named and then scratched, and "no wait, four". Their audio is to be made with Matt's cases;
next is 111.

**To record again.** These scripts changed with §126, most of them by losing the "Yes." that confirmed a command, and
058 by gaining "Glyph, new note.", so their recordings still say the old lines. Each carries `rerecord` in
`voice-tests/suite.json`, and the audio pass leaves it out until it is made again (then drop the field): 051, 052,
053, 054, 055, 056, 058, 061, 062, 067 and 069.

The older six-take walkthrough below is for playing into the phone by hand.

## By hand: six recordings, one note

Six scripts to record as audio (ElevenLabs), played into the phone's microphone while Ghost.md listens, to
check that every spoken cue writes the mark it promises and that plain speech stays plain. Together the
first five build one note, **Cabin weekend**, that holds one of everything the capture rules can write; the
sixth is prose that must not format, ending in silence. Each script lists what to say, what the note should
read afterwards, and what to look at on the screen.

The rules under test are `src/app/capture/markdown.ts` and the rule families it drives in `src/app/capture/spoken/`
(cues), `src/app/capture/finalInstruction.ts` with `src/app/capture/command.ts` and `src/app/capture/route.ts` (a
command read from the finished recording), and `src/app/capture/quiet.ts` (stopping on silence). The guide makes the
same promises: the "say" line beside each mark on its marks page (`src/app/guide/marks.ts`), and the habits on its
Tips page, whose examples `src/app/guide/phrases.ts` keeps. A script here that fails is either a rule to fix or a
promise to correct.

## Recording the audio

- One voice, a plain narrator at ordinary speed. No music, no effects.
- Say the punctuation. A colon after a cue word ("Heading: the plan") makes the voice pause there, and
  Whisper writes that pause back as a colon or a full stop, which is what the cue rules read. Keep the
  colons and full stops exactly as written.
- The pause tags are ElevenLabs break tags: `<break time="1.2s" />`. A pause under two seconds is a
  breath; the note stays in one paragraph. A pause of 2.5 seconds is a paragraph break, and so is saying "New
  paragraph". The rule is a gap of more than 1.5 s between two committed phrases (`PARAGRAPH_GAP_MS`), and the
  streamer turns a spoken pause of about 2.3 to 4 seconds into a gap of 1.7 s, so a pause of a little over two
  seconds is the shortest that breaks.
- Between two cued sentences leave at least 0.8 s, so the engine commits them as separate phrases.
- Play the file from a laptop about 30 cm from the phone, at the loudness of someone talking across a
  table. Start Ghost.md listening (hold the side key, or tap Speak) a beat before the audio starts.
- Numbers may come back as digits ("4417") or words; both are fine unless a script says otherwise.

## Before you start

Two notes must exist for script 5's commands. Record this line first, as its own note:

> Title: groceries. `<break time="1.2s" />` We need eggs, milk, bread and coffee.

Expected note:

```markdown
# Groceries

We need:
- eggs
- milk
- bread
- coffee
```

And a note whose title starts "AttackFM bug bash" should exist (any body). If it doesn't, record
"Title: AttackFM bug bash. `<break time="1.2s" />` Things we found." as a second note.

## The target note

After scripts 1 to 5, **Cabin weekend** should read like this (the exact wording of a number can differ; the
marks cannot). No script makes a table: a recording makes none (docs/instruction-voice-commands.md).

```markdown
# Cabin weekend

We leave on Friday after work and come back Sunday night.

## The plan

Drive up Friday, hike Saturday, lazy Sunday.

The forecast says rain on Saturday afternoon.

Bring the board games in case.

## Packing

- The tent
- The stove
- Two sleeping bags

For the drive we need:
- snacks
- water
- a charger
- the good playlist

## On arrival

1. Unlock the shed
2. Turn the water on
3. Light the stove

## The order of things Saturday

1. Breakfast by eight
2. The ridge walk
3. Back before the rain

## Before we go

- [ ] Book the cabin
- [ ] Call Sam about the keys
- [ ] Fill the car up
- [ ] Pack the first aid kit
- [ ] Buy ice

> The deposit comes back in full if the place is clean.

**Important:** They need the balance by Wednesday.

---

- Firewood from the farm shop

## The house rules

The deadline for the balance is **Wednesday at noon**, not Friday. The owner said the hot tub is _strictly off limits_ after ten. The gate code is ||four four one seven||, don't say it out loud. ==The wifi password is on the fridge==. %%I still think we should have booked the other place%%. The stove is ??gas??, it might be electric. ^^No shoes on the rug^^. Sunday breakfast is ++pancakes++.
```

---

## Script 1: the skeleton

**Tests:** the title cue, the heading cue, "new paragraph", the two-second pause, and a comma sentence that
must stay a sentence.

**Say** (start a new note):

> Title: cabin weekend. `<break time="1.2s" />` We leave on Friday after work and come back Sunday night. `<break time="1.0s" />` New section: the plan. `<break time="1.2s" />` Drive up Friday, hike Saturday, lazy Sunday. `<break time="2.5s" />` The forecast says rain on Saturday afternoon. `<break time="1.0s" />` New paragraph. `<break time="1.0s" />` Bring the board games in case.

**Expected:**

```markdown
# Cabin weekend

We leave on Friday after work and come back Sunday night.

## The plan

Drive up Friday, hike Saturday, lazy Sunday.

The forecast says rain on Saturday afternoon.

Bring the board games in case.
```

**Watch for:** the title set large as the first line; "The plan" as a level-two heading with its `##`
dimmed; the Friday, Saturday, Sunday sentence staying one line (no intro word, so no list); the 2.5 s
pause and "New paragraph" each opening a paragraph; the live page's words arriving from smoke.

## Script 2: lists

**Tests:** bullet cues, a list said in one breath, an ordinal run (first, second, finally), and numbers
said out loud.

**Say** (continue the same note, or open it and tap Speak):

> Heading: packing. `<break time="1.2s" />` Bullet point: the tent. `<break time="0.9s" />` Next point: the stove. `<break time="0.9s" />` Bullet point: two sleeping bags. `<break time="1.5s" />` For the drive we need snacks, water, a charger and the good playlist. `<break time="2.5s" />` Heading: on arrival. `<break time="1.2s" />` First, unlock the shed. `<break time="0.9s" />` Second, turn the water on. `<break time="0.9s" />` Finally, light the stove. `<break time="2.5s" />` Heading: the order of things Saturday. `<break time="1.2s" />` Number one: breakfast by eight. `<break time="0.9s" />` Number two: the ridge walk. `<break time="0.9s" />` Number three: back before the rain.

**Expected:**

```markdown
## Packing

- The tent
- The stove
- Two sleeping bags

For the drive we need:
- snacks
- water
- a charger
- the good playlist

## On arrival

1. Unlock the shed
2. Turn the water on
3. Light the stove

## The order of things Saturday

1. Breakfast by eight
2. The ridge walk
3. Back before the rain
```

**Watch for:** the one-breath list keeping its intro line and lower-case items; the ordinal run counting
up rather than repeating "1."; "Number one" needing the pause after it (the colon) to count as a cue.

## Script 3: to-dos, a quote, a callout, a divider

**Tests:** the four to-do phrasings, the checkbox cue, the quote cue, the "Important" callout, the divider,
and a cue said on its own then applied to the next sentence.

**Say:**

> Heading: before we go. `<break time="1.2s" />` Remember to book the cabin. `<break time="0.9s" />` I need to call Sam about the keys. `<break time="0.9s" />` Check box: fill the car up. `<break time="0.9s" />` Don't forget to pack the first aid kit. `<break time="2.5s" />` Quote: the deposit comes back in full if the place is clean. `<break time="2.5s" />` Important: they need the balance by Wednesday. `<break time="2.5s" />` Divider. `<break time="2.5s" />` Bullet point. `<break time="1.2s" />` Firewood from the farm shop.

**Expected:**

```markdown
## Before we go

- [ ] Book the cabin
- [ ] Call Sam about the keys
- [ ] Fill the car up
- [ ] Pack the first aid kit

> The deposit comes back in full if the place is clean.

**Important:** They need the balance by Wednesday.

---

- Firewood from the farm shop
```

**Watch for:** the four to-dos drawn with boxes; the `>` quote set apart; the callout bold with its
colon; the rule on its own line; the lone "Bullet point." held and then applied to "Firewood".

## Script 4: marks inside a sentence

**Tests:** bold and italic said mid-sentence, and six of the Marks plugin's own said the same way: spoiler,
highlight, aside, unsure, shout, added. Each cue word opens, "end" plus the word closes. (The five effects, "heated …
end heated" and the rest, are said the same way; neither this script nor the suite covers them yet.)

**Say:**

> Heading: the house rules. `<break time="1.2s" />` The deadline for the balance is bold Wednesday at noon end bold, not Friday. `<break time="1.2s" />` The owner said the hot tub is italic strictly off limits end italic after ten. `<break time="1.2s" />` The gate code is spoiler four four one seven end spoiler, don't say it out loud. `<break time="1.2s" />` Highlight the wifi password is on the fridge end highlight. `<break time="1.2s" />` Aside I still think we should have booked the other place end aside. `<break time="1.2s" />` The stove is unsure gas end unsure, it might be electric. `<break time="1.2s" />` Shout no shoes on the rug end shout. `<break time="1.2s" />` Sunday breakfast is added pancakes end added.

**Expected:**

```markdown
## The house rules

The deadline for the balance is **Wednesday at noon**, not Friday. The owner said the hot tub is _strictly off limits_ after ten. The gate code is ||four four one seven||, don't say it out loud. ==The wifi password is on the fridge==. %%I still think we should have booked the other place%%. The stove is ??gas??, it might be electric. ^^No shoes on the rug^^. Sunday breakfast is ++pancakes++.
```

**Watch for:** every pair of marks visible and dimmed around its words; the gate code in smoke until the
caret is put in it; the wash behind the wifi line; the aside smaller and leaning; the dotted line under
"gas"; the small caps; the underline. Whisper may write "end bold" as "and bold": the rule accepts that only
when it heard a pause after the opening word, so keep the 1.2 s breaks. Digits for the code are fine.

## Script 5: commands, one recording each

**Tests:** a command carried out as it is said: "Hey Ghost" (or "Glyph"), adding to another note's list, adding a
task to a note, adding a paragraph to a note, and making a new list with its items. Each is its own short recording.
The first three switch the page to the note as they are said and write the words into it; Done writes it and opens
it, with Undo. The last is read once, from the whole recording, when Done is pressed, and a card says what it will do
before anything is written. Needs the Groceries and AttackFM bug bash notes from "Before you start".

**Say**, pressing Done after each:

> Hey Ghost, add oat milk to the groceries note.

> Hey Ghost, add a task to cabin weekend: buy ice.

> Hey Ghost, add to AttackFM bug bash the login is still broken on Android.

> Hey Ghost, make a new list called firewood and add kindling, logs and matches.

Then tap the card to confirm the last.

**Expected:**

- None of the commands lands anywhere as words: a recording that is a command is not a note.
- Groceries gains `- Oat milk` at the end of its list, one item. An item a command adds is capitalised, although the
  items the list was made with are not.
- Cabin weekend gains `- [ ] Buy ice` at the end of "Before we go", and the chip says "under Before we go": a task
  goes to the note's to-do list, in that list's own style, not to the bullets after the divider.
- AttackFM bug bash gains "The login is still broken on Android." (as an item if the note has a list, else as a
  paragraph).
- A new note, Firewood, holds the three as a list.

**Watch for:** the top line saying Adding to "Groceries" and the page switching to it as the command is said, the
words arriving in its list, nothing stored until Done, and the note opening afterwards with "Added to Groceries" and
Undo. A command naming a note that does not exist keeps the words in the recording's own note and says so.

Tables, books, a board made and a card moved by voice are not in this script, because a recording does not do them
(docs/instruction-voice-commands.md, DESIGN §127).

## Script 6: prose that must stay prose, then silence

**Tests:** cue words used as ordinary words, which must not format; "then" outside an ordinal run;
"quote" mid-sentence; a comma sentence with no intro word; and the recording stopping on its own after
the voice stops.

**Say** (a new note):

> Title: a few notes. `<break time="1.2s" />` It was a bold move to book a cabin with no signal. `<break time="1.0s" />` Number one priority is sleep. `<break time="1.0s" />` The new item for the trip is a proper coffee grinder. `<break time="1.0s" />` We had a quote from the plumber last year and it was fine. `<break time="1.0s" />` Then we drove home, tired, happy. `<break time="2.5s" />` That's all for now. `<break time="3.0s" />` `<break time="3.0s" />` `<break time="3.0s" />`

**Expected:**

```markdown
# A few notes

It was a bold move to book a cabin with no signal. Number one priority is sleep. The new item for the trip is a proper coffee grinder. We had a quote from the plumber last year and it was fine. Then we drove home, tired, happy.

That's all for now.
```

**Watch for:** no bold, no numbered item, no to-do, no quote, no list; "Then" staying a word because no
"First" opened a run; the recorder ending the recording by itself during the nine seconds of silence at
the end, and the note saved with everything said.

## Not a script: the app open and not recording

Nothing listens while no recording runs. The microphone is opened by the recorder alone, so "Hey Ghost" said to the
app on its home page does nothing. The in-app wake-word listener this section once tested was removed.

## Keeping score

For each script note what came out against what was expected, in three columns: the cue, what the note
shows, and whether the fault is the rule (fix `src/app/capture/markdown.ts` and add the phrase to its test) or the
transcription (a word Whisper mishears: change the cue or its vocabulary). A miss in the guide's own
examples is already covered by `src/app/guide/guide.test.ts`, which renders each spoken example in
`src/app/guide/phrases.ts` through the real rules.
