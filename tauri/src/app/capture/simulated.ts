import type { CaptureHandlers, CaptureSession } from './engine.ts';

/**
 * A fixed note, spoken on a clock, for exercising the recorder without a microphone: the third engine behind
 * capture/engine.ts's one interface, chosen by `?simulate` in the URL. Each phrase arrives first as growing partials
 * and then as a committed segment, which is the rhythm the Whisper engine produces. It "keeps" audio in the sense that
 * stop answers with a length, so a note's tape can be built against it. Development and test tooling: nothing on the
 * phone reaches it without the query.
 *
 * `?simulate` speaks a note; `?simulate=route` speaks one that moves itself to
 * another note partway ("hey Ghost, move this to shopping list") and then
 * pauses, so routing and the tips in a pause can be watched without a
 * microphone; `?simulate=leave` leaves a note in AttackFM, said in one phrase
 * and then in two; `?simulate=item` speaks "hey Ghost, new item for attack FM"
 * and items for its list; `?simulate=command` is Matt's case, "add a list item
 * to" with the item after a pause, then a one-shot, then a sentence that opens
 * with the app's name; `?simulate=ask` stops with the item said;
 * `?simulate=giveback` says the keyword and names no note;
 * `?simulate=takeback` says a sentence, changes a word in it, corrects one,
 * scratches one and sends it after a breath, and sends one in one breath, to
 * shopping list;
 * `?simulate=say&say=a|b` speaks the phrases given, bar-separated.
 * `?simulate=review&review` says a note with a misheard word and, on Done, runs
 * the review with its models simulated in the note it opens
 * (ai/useNoteReview.ts, ai/reviewSimulation.ts).
 *
 * Each command in them is read as the recorder reads one: the live reader (liveRoute.ts) carries out "hey Ghost,
 * add … to <note>" as it is said, and anything else is read once, from the whole transcript, at Done
 * (CaptureScreen.tsx `finish`). Nothing asks for a yes.
 */
const SCRIPTS: Record<string, string[]> = {
  note: [
    'Weekend trip.',
    'We need to book the cabin by Friday and the deposit is 200 dollars.',
    'For the drive we want snacks, water, a charger and the good playlist.',
    'Remember to ask Sam about the dog.',
    'Separately the car needs an oil change before we leave.',
  ],
  route: ['Oat milk, eggs and the good coffee.', 'Hey Ghost, move this to shopping list.', 'And bin bags.'],
  leave: ['Quick thought before I forget.', 'Hey Ghost, leave a note on the page for attack FM that says the seek bar drifts on two devices.', 'Hey Ghost, leave a note for attack FM.', 'Ship the APK on Friday.'],
  item: ['Quick thought before I forget.', 'Hey Ghost, new item for attack FM.', 'Fix the login bug on Android.', 'Hey Ghost, new tasks for attack FM.', 'Update the readme, ship the APK and tell Sam.'],
  giveback: ['Pick up the parcel.', 'Hey Ghost, that was a long day.'],
  takeback: [
    'Weekend trip.',
    'The meeting is at three.',
    'No wait, four.',
    'We need snacks and water.',
    'Actually, we need snacks and a charger.',
    'Bin bags and oat milk.',
    'Scratch that.',
    'Add it to shopping list instead.',
    'Call Sam about the dog.',
    'Scratch that, add it to shopping list instead.',
  ],
  review: ['Bug bash on Friday.', 'Fix the seat bar on two devices.', 'Downloads get stuck on the discover list.'],
  ask: ['Quick thought before I forget.', 'Hey Ghost, add a list item to the attack FM.', 'Fix the seek bar.'],
  command: ['Quick thought before I forget.', 'Hey Ghost, add a list item to the attack FM.', 'Fix the seek bar.', 'Hey Ghost add ship the APK to attack FM.', 'Ghost is going to need a plugin store.'],
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
