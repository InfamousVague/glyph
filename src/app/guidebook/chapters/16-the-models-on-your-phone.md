# The models on your phone

_Ghost.md's AI is a handful of files on your phone. They hear you and rewrite your notes right there, and nothing you write or say is sent anywhere to be heard or rewritten._

## Two kinds of model

Ghost.md keeps two kinds of model, and both run on the device.

- **Speech models** turn what you say into words. They are Whisper models.
- **Language models** read a note and write it again: tidied, summarised, fuller, or checked.

Each one is downloaded once, checked, and kept. After that it works with no connection at all.

## The speech models

| Model | Size | What it does |
|---|---|---|
| Whisper base.en | about 60 MB | Hears you live, fast enough to keep up as you talk. |
| Whisper small.en | about 190 MB | Goes over a recording afterwards, for Better words and the review. It is too slow to keep up live, but it mishears less: in the app's own tests it got about 6 words in 100 wrong, where base.en got 10. |

The first is fetched as soon as the app opens, so the first press of the side key does not have to wait for it. While it comes down, the home page says "Downloading the voice model, 12 of 60 MB. Keep Ghost.md open." If the download fails (usually because the phone locked halfway), the home page says "The voice model didn’t download." with **Try again**, and the app tries again by itself each time you come back to it.

The second is fetched the first time it is needed, which is the first recording that Better words or the review goes over. While it comes down, the home page says "Getting the better voice model, 40 of 190 MB." Until it is on the phone, a note keeps the words it was heard with live. Both models are English-only.

In a browser tab there are no speech models. Recording there uses the browser's own recogniser, which only Chrome has, and that recogniser is the browser's, not Ghost.md's.

## The language models

Settings › Formatting › Model lists four. The one you choose rewrites your notes. Bigger is more careful, and slower.

| Model | Download | What Settings says |
|---|---|---|
| Qwen3.5 2B | 1.28 GB | Quick. Good for short notes; it can shorten long ones. |
| Qwen3.5 4B | 2.74 GB | The balance. Careful with facts, fits most phones. |
| Qwen3.5 9B | 5.68 GB | The most careful, and the slowest. Wants 12 GB of memory. |
| Gemma 4 E4B | 4.98 GB | A different voice. Runs like a 4B; the file is bigger. |

The 4B is the default. Settings rounds the sizes to one decimal place, so the 4B shows as 2.7 GB.

The app never fetches a language model without asking you. Asking for a run with no model on the phone does not fetch one either: the note tells you it needs a model. There are two places to get one:

- **Settings › Formatting › Model.** You can choose any model that is on the phone. One that is not has **Get**. The download happens in the open, with a line such as "Getting Qwen3.5 4B, 1.2 GB of 2.7 GB. Keep Ghost.md open." Only one downloads at a time.
- **The welcome guide's "Choose your model" page.** Picking a row sets your choice, and **get it now** under the list starts the download.

If the phone stops a download partway, tap Get again. The last card on the page, **On the phone**, lists what has been downloaded, the storage it takes in all, and **Remove** beside each model. If you remove the model you had chosen, the choice moves to another one that is still on the phone, or back to the default.

## Which one runs

You choose a model, but the app can only run what is on the phone. It picks in this order:

1. The model you chose, if it is here.
2. Otherwise, the biggest one here that is no bigger than your choice.
3. Otherwise, the smallest one here.

So if you chose the 9B and only the 2B and 4B are downloaded, the 4B runs. If you chose the 2B and only the 9B is here, the 9B runs, because nothing smaller is there. One model does the whole of a run. There is no quick draft followed by a careful pass.

Two things choose their own model. The gist, the short line under a note's title on the home page, is always written by the smallest model on the phone: see [[Asking the AI to work on a note]]. The review after a recording thinks with a Qwen: see [[Spoken asks and the review]].

## Every byte is checked

The app has each model's SHA-256 fingerprint built into it. A download is hashed as it arrives, and it only becomes the model if every byte matches. Anything else is thrown away.

The files come from attack.fm/glyph/models first, and from Hugging Face if that fails. An update can tell the app to try a new source first, but it can never change a fingerprint. The source only decides where the bytes come from, never which bytes are accepted.

If the connection drops partway, the download asks for the rest and carries on from where it stopped, so a 5.7 GB model can still arrive over a patchy connection. If the download stops altogether, because the app was closed or the connection stayed dead, the next Get starts again from the first byte.

## Local only

Settings › Formatting › Local only turns off update checks, downloads, link previews and every plugin that uses the network, and sync waits too. Ghost.md then runs from what is already on the phone. Models you have already downloaded keep working, because they need nothing from outside.

With Local only on, nothing is fetched, and the app tells you why:

- If you tap Get in Settings: "Local only is on, so nothing is downloaded. Turn it off in Settings to get a model."
- If the recorder has no voice model yet: "Local only is on, so the voice model was not downloaded. Turn it off in Settings to get it."
- Better words waits quietly until the larger speech model is on the phone.

There is more on this in [[What stays on your phone]].

## Where there is no AI

Everywhere the app offers the AI, it asks the same question first: can it run here? If not, it gives one sentence as a short message when you pick a run.

| Where | What the app says |
|---|---|
| A browser tab | The AI runs on the phone. Install Ghost.md on Android to use it. |
| An iPhone | The AI is not on iOS yet. |
| An app older than the AI | The AI needs the newest Ghost.md. Install it from attack.fm/glyph. |
| No model downloaded yet | The AI needs a model on the phone. It runs here; nothing leaves the phone. |
| No model, and Local only on | No model is on the phone, and Local only is on, so none can be downloaded. Turn it off in Settings to get one. |

For a moment after the app opens, while it is still checking which models are here, it says "Looking for the model." The Mac app runs the models too.

## The AI card

While a model works on a note, a strip under the note's header says what it is doing. Tap the strip while the run is going and the AI card opens. It shows the model's name and size, "On this phone", a line for what the model is doing now, and readings from the phone.

The line moves through the run: "Loading Qwen3.5 4B.", then "Reading the note, 120 of 480.", then "Formatting, 9.4 tokens a second, 0:12." A token is a piece of a word, about four letters of English, so the tokens a second are the model's writing speed.

| Reading | What it shows |
|---|---|
| Cores | How many of the phone's cores the model is running on: "6 of 8". Where the engine does not say, just the phone's count. |
| CPU | How busy the processor is, counted per core, so 640% means six and a half cores are busy. |
| Memory | The memory the app is using, out of the phone's total. |
| Heat | The hottest temperature the phone reports, if it lets an app read one. |
| Battery | The battery level, and whether it is charging. |
| Written | How many tokens the model has written so far. |

The card leaves out anything the phone will not tell it, instead of guessing. On a Mac, and in an app too old to send the engine's own readings, the card shows only what the page can read for itself, such as the cores. The last line of the card is "Nothing leaves the phone."

## No cloud AI

The app's AI has no server behind it. It formats, summarises and reviews on the phone, using the phone's own cores, and once the models are downloaded it works in aeroplane mode. Claude can also read and write your notes, but only if you connect it yourself, and it works separately from the app's own AI: see [[Claude on your notes]].

## Read next

- [[Asking the AI to work on a note]]
- [[What stays on your phone]]
- [[Settings, one section at a time]]
