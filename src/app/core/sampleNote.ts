import { imageMarkdown } from './images.ts';
import smokeUrl from '../assets/sample-smoke.jpg';

/**
 * The sample note: every kind of mark a note can hold, in one note, so a
 * person can see them all in one place and learn them by looking (Matt: "add
 * a default note with every kind of markdown formatting and table and image
 * and everything we support"). A fresh library gets it once (seed.ts), and
 * Settings > About makes another whenever wanted.
 *
 * The words are the note's own explanation of itself, in the app's voice.
 * The picture is a photograph of smoke by Jocelyn Morales, from Unsplash
 * under the Unsplash License (docs/THIRD_PARTY.md), bundled with the app
 * and copied into the library's pictures the way a pasted picture is
 * (core/images.ts), so the note holds a real `![…](image/…)` line and not a
 * special case. (An ink cassette drawn in SVG came first; Matt: "quite ugly".)
 * Where the picture can't be fetched (a test) the note has no picture and
 * says nothing of one.
 */

export const SAMPLE_TITLE = 'Everything a note can hold';

/** The note's body, with the picture line when there is a picture to show. */
export function sampleNoteBody(image: string | null): string {
  const picture = image
    ? `## A picture

${imageMarkdown(image, 'A wisp of smoke, by Jocelyn Morales')}

A picture pasted or picked lands under its own line like this one, and the line stays, so you can see what it is.

`
    : '';
  return `# ${SAMPLE_TITLE}

A note is plain Markdown, said or typed. The marks stay on the page, a little dimmed, so what you see is what you wrote. This note holds one of everything.

## Headings

Six sizes, from one \`#\` to six.

### Three hashes

#### Four

##### Five

###### Six

## Words

**Bold** for weight, _italic_ for a lean, ***both at once***, ~~struck~~ when a thought is gone, and \`code\` in its own face. A mark you mean as itself is escaped: \\*not italic\\*.

A secret between pairs of pipes goes to smoke until you put the caret in it: ||the cabin key is under the third stone||.

## Glyph's own marks

==Highlight== the line you will want again. An aside is a note to yourself, %%smaller and quieter%%. Mark a fact to check as ??unsure??, and say why in brackets after it: ??the deposit??(Sam said 400, the email says 450) — tap the words for the note. ^^Shout^^ without going bold. Show what was ++added++ beside what was ~~struck~~. Each has a word to say while recording: "highlight", then "end highlight".

## Lists

- Milk
- Bread
  - Rye, if they have it
- Eggs

1. Wake up
2. Coffee
3. Write it down

- [ ] Book the cabin
- [x] Call Sam

## A quote

> The note you make on the way is the one you keep.

## Links

A link with words: [Glyph](https://attack.fm/glyph). A bare address is shortened on the page: https://attack.fm/glyph

A line that is nothing but a link gets a card under it, with the page's title and site:

https://attack.fm/glyph

- [The Tauri handbook](https://tauri.app/)

A link in the middle of a sentence, like https://example.com here, stays a link and draws no card.

## A table

| What | Where | Packed |
| :--- | :---: | ---: |
| Tent | Garage | Yes |
| Stove | Loft | No |

Tap a drawn table to see its pipes and change it.

## Code

A fence with its language named is coloured by that language, in the code colours chosen in Settings > Theme.

\`\`\`rust
use std::collections::HashMap;

/// A note, and the words that were said to make it.
#[derive(Debug, Clone)]
struct Note<'a> {
    title: &'a str,
    words: Vec<&'a str>,
}

impl<'a> Note<'a> {
    fn new(title: &'a str) -> Self {
        Self { title, words: Vec::new() }
    }

    // Counts each word, ignoring case.
    fn counts(&self) -> HashMap<String, usize> {
        let mut seen = HashMap::new();
        for word in &self.words {
            *seen.entry(word.to_lowercase()).or_insert(0) += 1;
        }
        seen
    }
}

fn main() {
    let mut note = Note::new("Groceries");
    note.words.extend(["Oat", "milk", "and", "oat", "bread"]);
    let total: usize = note.counts().values().sum();
    println!("{} has {} words, {:.1}% unique", note.title, total, 60.0);
}
\`\`\`

## A rule

Three dashes on a line of their own:

---

${picture}## And the rest

Say "Glyph, add a table to this note" and the phone asks what goes in it. The cog at the top links a note to a Notion board or a repo. Press and hold on any words and choose Style to put one of these marks on them.
`;
}

/** The bundled photograph as a JPEG blob; null where it can't be fetched. */
export async function sampleImageBlob(): Promise<Blob | null> {
  if (typeof fetch !== 'function') return null;
  const response = await fetch(smokeUrl).catch(() => null);
  if (!response?.ok) return null;
  return response.blob();
}
