# Getting markdown out of speech

Research for the question "how do we get whisper.cpp to use markdown more", 2026-09-12. Short
answer: **not from Whisper itself**. Whisper transcribes; the markdown comes from what is said and
what reads the transcript afterwards. The levers, in the order they pay off:

## 1. Whisper will not write markdown, and cannot be told to

- A Whisper prompt is not an instruction. OpenAI's own prompting guide says a prompt like
  "Format lists in Markdown format" is not obeyed, because the model follows the *style* of the
  prompt rather than instructions in it.
- It does imitate style (punctuation, capitalisation, spelling of names) when the prompt shows it,
  but a markdown-shaped prompt is a rare style, and the guide notes rare styles work poorly.
  Worse, it invites the model to invent `#` and `-` the speaker never implied.
- The prompt is capped at 224 tokens, and Glyph already spends that budget on continuity: the tail
  of the committed transcript, passed as tokens (`src-tauri/src/whisper/engine.rs`).
- whisper.cpp can constrain decoding with a GBNF grammar. That suits command vocabularies ("turn on
  the lights"), not free dictation, where a grammar strong enough to force structure also forces
  mistranscription.

So Whisper's job stays "write down exactly what was said, punctuated". Everything below builds on
that.

## 2. Spoken cues, parsed on the phone (what Glyph does)

Deterministic rules in `src/app/capture/markdown.ts` turn cue words into markdown as each phrase is
committed, with no network: title, heading, new paragraph, bullet point, number one, first/second/
finally, to-dos ("remember to", "check box"), quote, important, bold/italic spans, divider, and
spoken lists after a list word ("I need eggs, milk and bread"). A cue can be said on its own and
applies to the next sentence. The rules are high-precision on purpose: a missed list reads fine, a
false one mangles prose. This is how every mature dictation product does formatting (Dragon,
Apple and Google dictation all use spoken commands).

**What makes cues work better is the speaker, not the model**, which is why the guide exists
(`src/app/guide/`): pause before a cue so Whisper starts a sentence there; say the cue at the start
of a sentence; stop for two seconds for a paragraph. The guide renders every example through the
real rules, and `guide.test.ts` fails if a rule stops producing what the guide teaches. It has
already caught one real bug: a paragraph break said on its own was being dropped.

## 3. A cue vocabulary in the prompt (in progress)

Where prompting *does* help is spelling: Whisper follows a glossary. A short line of the cue words
before the continuity text ("Heading. Bullet point. New paragraph. To do. Quote.") biases the
decoder to transcribe them as the parser expects - "bullet point", not "bullet pointed" or "a
bullet point" run into the next word. Kept to about 30 tokens so continuity keeps most of the 224.
The known risk is prompt leakage: on near-silent windows Whisper can echo prompt words. Glyph's
silence gate keeps near-silent windows from the model, and a segment made only of cue words with no
content is dropped. Native change; ships in the next APK.

## 4. Structure nobody said out loud (the formatting model)

> Removed in 0.6.0: Glyph formats from spoken cues and local rules only, and neither the attack.fm
> annotator nor an on-device model is used. See DESIGN section 15 for what was measured.

For notes spoken naturally, with no cues, a language model reading the whole transcript can find the
title, the lists and the to-dos. Glyph has this: the annotator on attack.fm returns only verbatim
spans, so it can restructure but never rewrite. It is currently unavailable (the box's single CPU
Ollama slot is held by AttackFM, so every call answers 503), and nothing user-facing promises it.
When a backend is chosen, it is the lever that makes *uncued* speech come out as markdown; cues
always override it.

## Not worth doing

- Fine-tuning Whisper to emit markdown: needs paired audio/markdown data nobody has, and loses the
  "every word is what you said" property.
- Larger Whisper models for this purpose: accuracy, not formatting, is what they buy.

Sources: [OpenAI Whisper prompting guide](https://developers.openai.com/cookbook/examples/whisper_prompting_guide);
whisper.cpp grammar support (`grammars/` in the whisper.cpp repository); Glyph's own engine and parser.
