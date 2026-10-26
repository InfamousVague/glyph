# Lovart

Lovart is a design agent: describe an image and it makes it. The Lovart plugin brings it into your notes. Write `{image: …}` where a picture should go, ask any note for a moodboard, give your notes header images, and let a design meeting come back with inspiration. Lovart makes the images; Ghost.md puts them in your note.

Lovart is a separate service, with its own account, plans and terms. You use your own Lovart account, and every image is made with your Lovart credits.

Works on: Android, iPhone and Mac. Held off while Local only is on.

## Setting it up

1. **Make a key pair in Lovart.** On lovart.ai, open your avatar menu, then **AK/SK Management**, and make an access key and a secret key.
2. **Add the plugin.** Open the Market, find **Lovart** under **AI**, and tap **Add to Ghost.md**. It is off until you add it.
3. **Keep the keys.** Open **Settings › Lovart**. Under **Lovart keys**, paste the access key and the secret key, then tap **Keep them**. They are checked with Lovart first. You see "The keys work.", or "Lovart refused those keys. Copy both again from AK/SK Management in Lovart." If Lovart can't be reached just then, the keys are kept anyway and the page says they couldn't be checked; the first image tells you if they are wrong.

Once kept, the card shows **Keys kept** with the start and end of your access key, and two rows:

- **Check** asks Lovart again whether the keys work.
- **Forget the keys**: tap **Forget**, then **Tap again**. Lovart can no longer be asked from this device. While keys are kept in sync, your other devices forget them too at their next sync.

### Where the keys are kept

The keys are kept in your device's secure storage. They follow your account to your other devices sealed, so the server cannot read them on the way, as long as **Keep keys and connections in sync** is on (Settings › Account › Sync). Only signatures go to Lovart: the secret key never leaves your devices.

## Images in a note: `{image: …}`

Type `{image:` and what you have in mind, and close it with `}`:

```markdown
## Homepage

The hero {image: a misty forest at dawn, soft light} goes on top.

{image: three logo marks for a fox brand, flat colours}
```

A few rules:

- It can go anywhere in a line. `{image:prompt}` without the space works too, and so does `{Image: …}`.
- It counts once the closing `}` is there and the prompt has words. The prompt stays on one line, up to 500 characters.
- It is left alone inside code. A `{` straight after another `{`, a `$` or a `\` does not start one, and `{{image: …}}` in a template stays the template's.
- It never clashes with an AI blank, which starts `{?`. A `{?question}` stays a blank, and only `{image: …}` goes to Lovart.

As soon as the cue is closed, its words get a faint wash and **Lovart's mark appears just after the `}`**. With the plugin off, the cue is plain text.

### Making the picture

There are two ways to make one cue:

- **Press Return at the end of the line**, when the cue is the last thing on it. Lovart starts on it, and your caret goes on to the new line, so you can keep writing.
- **Tap Lovart's mark** beside the cue.

While Lovart works, the mark turns into a turning ring, and a **blurred stand-in** waits under the line, at the picture's size, with Lovart's mark on it. It usually takes a little while.

When the picture arrives it takes the cue's place:

- A cue alone on its line becomes the picture, written as ordinary Markdown: `![a misty forest at dawn](image/lovart-….png)`.
- A cue in the middle of a sentence is taken out of the words, and the picture goes on the line after it. The sentence stays whole.

The picture is kept with your note's other pictures and syncs like them.

### Asking for size, shape and count

There are no settings for these. Lovart's agent picks the model and the size from your words, so say it in the prompt: "a wide banner", "square, flat colours", "make one image".

## Make images

To make every cue in a note at once, tap **More for this note** and choose **Make images**. It shows only when the note has cues, and says how many will become pictures.

They are made in order, and the note says how it is going: "Lovart is making image 2 of 3…", then "Made 3 images with Lovart." If Lovart declines one, that cue stays and the rest go on. If the keys are wrong, your credits run out, or Lovart wants your go-ahead for a costly step, the rest stop.

## Inspiration images

Any note can have a moodboard. Tap **More for this note** and choose **Inspiration images**.

Lovart reads the note's title, and its summary or its opening words, and makes **four images** for the ideas in it, each a different visual direction: style, colour palette, composition. They go under a `## Inspiration` heading at the end of the note. Ask again and the new ones join the ones already there.

## Header images

With Lovart added, a note can have a **header image**: a wide banner across the top of the page, four times as wide as it is tall. It is drawn in Ghost.md's own style, stipple dotwork in full colour on white, with the ghost small on the right doing whatever the note is about, and the left third left white.

### Made as you leave a note

**Header images for notes**, in **Settings › Lovart › Notes**, is on as soon as you add Lovart. With it on, a note gets its banner when you leave it, never while it is open, so it is drawn from what you wrote. While Lovart works, a stand-in waits where the banner goes.

A note gets one by itself only if:

- it has 25 words or more, past its front matter;
- it isn't a ticket, a meeting (one Ghost was in, or a recording written up), a mail, a notebook or journal, a canvas or a template, and isn't archived;
- it has no banner already.

Each note is asked for once, with your credits. A banner you take off, or one Lovart couldn't make, isn't asked for again by itself. The switch is kept on each device.

### Making one now

To make one for a note now, or a new one in place of the old, tap **More for this note** and choose **Header image**. The note says "Lovart is making a header image…" while it works.

### Banners for your recent notes

To give notes you already have their banners, use **Header images for recent notes**, under the switch, and tap **Make them**. It takes your 100 most recently changed notes that are ones to have a banner and have never had one, and makes three at a time, saying how far it is: "Making 4 of 37… 3 made so far." It carries on if you close Settings. **Stop** stops it after the ones being made.

If Lovart declines one note, the run goes on. If your keys are refused, your credits run out, or Lovart wants your go-ahead for a costly step, the run stops and says why; the note it stopped on is tried again next time.

### In the note

The banner is a line in the note's front matter:

```
---
banner: "![](image/lovart-….png)"
---
```

Its picture is kept with the note's other pictures, so it syncs, reaches your team in a shared note, and goes with an export like any other. To take a banner off, delete the `banner:` line.

A colour banner is drawn in its own colours, on light pages and dark. A black-and-white banner, from before banners were in colour, is drawn in the page's own inks, so it turns light on dark when your theme is dark.

## Inspiration for design meetings

In **Settings › Lovart › Meetings**, switch on **Inspiration for design meetings**. It is off by default.

Once a meeting is written up, if it reads as a design meeting (mockups, a brand, a layout, a logo, wireframes, typography and the like), Lovart makes a moodboard of four from its summary, under **Inspiration** in the meeting's note. One design word in the meeting's title is enough, or two different ones in its summary. A standup that mentions the UI once is left alone.

It happens once per meeting, with your credits, even if the summary is written again. To ask again, use **Inspiration images** on the note. The switch is kept on each device, and each device that writes a meeting up asks for its own. See [[Meetings and the Meet bot]].

## Credits, and costly steps

Every image costs Lovart credits from your plan. Some steps cost more, such as a premium model or a video. **Ghost.md never approves those for you.** It tells you, in words like "Lovart wants your go-ahead before a step costing about … credits. Approve it in Lovart if you want it.", and the cue stays in your note. If you want it, approve it in Lovart.

Which Lovart plans include access keys is Lovart's to say: ask Lovart before relying on it for a team.

## Pictures carry Lovart's mark

A picture Lovart made carries Lovart's mark in its bottom-right corner, wherever it is shown: in a note, a header image, an embedded note or a canvas card. It shows on every device, whether the plugin is on there or not, so a picture Lovart made is never mistaken for a photo you took. A screen reader says "Made with Lovart".

## What goes to Lovart

Only what you ask about: the words of a cue; the title and summary of the note you ask inspiration for, or its first 1,500 characters where it has no summary; or the title and first 900 characters of a note getting its header image. Nothing else of your notes goes there. The images are made in a Lovart project of your own, so you can also find them in Lovart.

## When something goes wrong

| It says | What to do |
|---|---|
| Add your Lovart keys in Settings › Lovart first. | Keep your keys, as above. |
| Lovart didn't accept these keys. | Copy both again from AK/SK Management, and tap **Keep them**. |
| Lovart says your plan or credits don't cover this. | Top up or change plan in Lovart. |
| Lovart wants your go-ahead before a costly step. | Approve it in Lovart, or change the prompt. |
| Lovart is still busy with the last request. | Wait for it to finish, then try again. |
| Lovart is asking this device to slow down. | Try again in a minute. |
| Lovart made no image: … | Lovart declined the prompt, and says why. Change the words. |
| Lovart took more than 5 minutes. | What it made will be in your Lovart project. |
| Lovart couldn't be reached. | Check your connection, and that Local only is off. |
| Lovart took too long to answer. | Try again in a moment. |
| Lovart stopped before it finished. | Try again. |
| The image was made, but its {image: …} was gone from the note. | You deleted or changed the cue while it was made. The picture is in your Lovart project. |

More fixes are in [[Troubleshooting]].

See also: [[Plugins, one by one]] · [[The Market]] · [[Pictures, files and voice memos]] · [[AI on your device]] · [[Accounts, sync and encryption]]
