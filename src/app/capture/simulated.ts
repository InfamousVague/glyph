import type { CaptureHandlers, CaptureSession } from './engine.ts';

/**
 * A fixed note, spoken on a clock, for exercising the recorder without a microphone: the third engine behind
 * capture/engine.ts's one interface, chosen by `?simulate` in the URL. Each phrase arrives first as growing partials
 * and then as a committed segment, which is the rhythm the Whisper engine produces. It "keeps" audio in the sense that
 * stop answers with a length, so a note's tape can be built against it. Development and test tooling: nothing on the
 * phone reaches it without the query.
 *
 * `?simulate` speaks a note; `?simulate=route` speaks one that sends itself to
 * another note partway ("Glyph, move this to shopping list", yes) and then
 * pauses, so routing and the tips in a pause can be watched without a
 * microphone; `?simulate=leave` leaves a note in AttackFM, said in one phrase
 * and then in two; `?simulate=item` speaks "Glyph, new item for attack FM" and
 * items for its list; `?simulate=command` is Matt's case, "add a list item to"
 * with the item after a pause, answered yes, then one answered no, then the
 * keyword with no command after it; `?simulate=ask` stops at the question;
 * `?simulate=table` builds a table in AttackFM by answering its questions, and
 * `?simulate=tableask` stops at the table's yes; `?simulate=say&say=a|b` speaks
 * the phrases given, bar-separated. `?simulate=review&review`
 * says a note with a misheard word and, on Done, runs the review with its
 * models simulated in the note it opens (ai/useNoteReview.ts, ai/reviewSimulation.ts).
 *
 * The scripts that say commands were written for the live reading of commands a phrase at a time. Since PR #1 the
 * recorder only shows each phrase and reads the one command in the whole transcript at Done (CaptureScreen.tsx
 * `finish`), so what they show now is what that reading makes of them.
 */
const SCRIPTS: Record<string, string[]> = {
  note: [
    'Weekend trip.',
    'We need to book the cabin by Friday and the deposit is 200 dollars.',
    'For the drive we want snacks, water, a charger and the good playlist.',
    'Remember to ask Sam about the dog.',
    'Separately the car needs an oil change before we leave.',
  ],
  route: ['Oat milk, eggs and the good coffee.', 'Hey Ghost, move this to shopping list.', 'Yes.', 'And bin bags.'],
  leave: ['Quick thought before I forget.', 'Hey Ghost, leave a note on the page for attack FM that says the seek bar drifts on two devices.', 'Yes.', 'Hey Ghost, leave a note for attack FM.', 'Ship the APK on Friday.', 'Yes.'],
  item: ['Quick thought before I forget.', 'Hey Ghost, new item for attack FM.', 'Fix the login bug on Android.', 'Yes.', 'Hey Ghost, new tasks for attack FM.', 'Update the readme, ship the APK and tell Sam.', 'Yes.'],
  table: ['Bug bash on Friday.', 'Hey Ghost, add a table to attack FM.', 'Bug, owner and status.', 'Seek bar drift, Matt, open.', 'Downloads stuck, Sam, fixed.', "That's it.", 'Yes.'],
  giveback: ['Pick up the parcel.', 'Hey Ghost, that was a long day.'],
  review: ['Bug bash on Friday.', 'Fix the seat bar on two devices.', 'Downloads get stuck on the discover list.'],
  tableask: ['Bug bash on Friday.', 'Hey Ghost, add a table to attack FM.', 'Bug, owner and status.', 'Seek bar drift, Matt, open.', 'Downloads stuck, Sam, fixed.', "That's it."],
  ask: ['Quick thought before I forget.', 'Hey Ghost, add a list item to the attack FM.', 'Fix the seek bar.'],
  command: ['Quick thought before I forget.', 'Hey Ghost, add a list item to the attack FM.', 'Fix the seek bar.', 'Yes.', 'Hey Ghost add ship the APK to attack FM.', 'No.', 'Ghost is going to need a plugin store.'],
};

export function simulated(handlers: CaptureHandlers): CaptureSession {
  const params = new URLSearchParams(window.location.search);
  // `?simulate=say&say=First phrase.|Second phrase.` speaks whatever is given, a phrase per bar: any command can be tried without a microphone.
  const said = params.get('say');
  const script = said ? said.split('|').map((phrase) => phrase.trim()).filter(Boolean) : (SCRIPTS[params.get('simulate') ?? ''] ?? SCRIPTS.note!);
  type Cue = { at: number; run: () => void };
  const cues: Cue[] = [];
  let at = 0;
  script.forEach((phrase, index) => {
    const words = phrase.split(' ');
    const startMs = at;
    words.forEach((_, w) => cues.push({ at: (at += 180), run: () => handlers.onPartial(words.slice(0, w + 1).join(' ')) }));
    const endMs = (at += 350);
    cues.push({
      at: endMs,
      run: () => {
        handlers.onPartial('');
        handlers.onSegment({ text: phrase, startMs, endMs });
      },
    });
    at += index === 3 ? 2600 : 300; // one long pause, to show a paragraph break
  });

  let clock = 0;
  let next = 0;
  let last = performance.now();
  let finished: () => void = () => undefined;
  const done = new Promise<void>((resolve) => {
    finished = resolve;
  });
  const timer = window.setInterval(() => {
    const now = performance.now();
    clock += now - last;
    last = now;
    while (next < cues.length && (cues[next]?.at ?? Infinity) <= clock) cues[next++]?.run();
    if (next >= cues.length) finished();
  }, 40);

  return {
    kind: 'simulated',
    wantsSamples: false,
    keepsAudio: true,
    push: () => undefined,
    positionMs: () => clock,
    stop: async () => {
      await Promise.race([done, new Promise((resolve) => window.setTimeout(resolve, 50))]);
      window.clearInterval(timer);
      return { recordedMs: Math.round(clock), transcript: null };
    },
    cancel: () => window.clearInterval(timer),
  };
}
