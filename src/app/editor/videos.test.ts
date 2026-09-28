import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { EditorState } from '@codemirror/state';
import { EditorView } from '@codemirror/view';
import { waitUntil } from '../../test/render.tsx';
import { goBack } from '../core/back.ts';
import { isDrawnBlock } from './drawnBlock.ts';
import { inlineImages } from './images.ts';

/**
 * A film's card under its line (editor/videos.ts): what each reader is told, the disc drawn only once the film is
 * known to be here, playing and pausing, one film at a time, full screen and back, and the line folded to its words.
 * Where the film stands is core/videos.ts's to say, and is stood in for.
 */

const where = vi.hoisted(() => ({
  film: 'here' as 'here' | 'missing' | 'update' | 'elsewhere',
  plays: 'phone' as 'phone' | 'update' | 'elsewhere',
  asked: [] as string[],
  gone: [] as string[],
}));
vi.mock('../core/videos.ts', () => ({
  filmHere: async (name: string) => {
    where.asked.push(name);
    return where.film;
  },
  filmsPlay: async () => {
    where.asked.push('(which device)');
    return where.plays;
  },
  filmGone: (name: string) => where.gone.push(name),
  videoUrl: (name: string) => `http://vid.localhost/${name}`,
}));
vi.mock('../core/images.ts', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../core/images.ts')>()),
  imageUrl: (name: string) => `http://img.localhost/${name}`,
}));

const { videoCards, videoWords } = await import('./videos.ts');

const LINE = '[![video 0:12](image/p1.jpg)](video/f1.mp4)';

function mount(doc: string, mode: 'play' | 'still' | 'shared', caret = 0): EditorView {
  return new EditorView({
    state: EditorState.create({ doc, selection: { anchor: caret }, extensions: [inlineImages(), videoCards(mode)] }),
    parent: document.body.appendChild(document.createElement('div')),
  });
}

const cards = (view: EditorView) => [...view.dom.querySelectorAll<HTMLElement>('.cm-videoCard')];
const wordsOf = (card: HTMLElement) => card.querySelector('p')?.textContent ?? '';
const shown = (view: EditorView, number: number) => (view.contentDOM.querySelectorAll('.cm-line')[number - 1] as HTMLElement).textContent;

let played: HTMLMediaElement[] = [];
const tall = window.innerHeight;

beforeEach(() => {
  // A phone's height with the keyboard up: jsdom lays nothing out, and CodeMirror draws only the cards whose estimated
  // heights fit its margin, which two at a 768px window's 60vh do not.
  Object.defineProperty(window, 'innerHeight', { configurable: true, value: 400 });
  Object.assign(where, { film: 'here', plays: 'phone', asked: [], gone: [] });
  played = [];
  // jsdom has no media: a film plays and pauses as a flag, and says so as a real one does.
  vi.spyOn(HTMLMediaElement.prototype, 'play').mockImplementation(function (this: HTMLMediaElement) {
    played.push(this);
    Object.defineProperty(this, 'paused', { configurable: true, value: false });
    this.dispatchEvent(new Event('play'));
    return Promise.resolve();
  });
  vi.spyOn(HTMLMediaElement.prototype, 'pause').mockImplementation(function (this: HTMLMediaElement) {
    Object.defineProperty(this, 'paused', { configurable: true, value: true });
    this.dispatchEvent(new Event('pause'));
  });
  vi.spyOn(HTMLMediaElement.prototype, 'load').mockImplementation(() => undefined);
});

afterEach(() => {
  Object.defineProperty(window, 'innerHeight', { configurable: true, value: tall });
  document.body.innerHTML = '';
  vi.restoreAllMocks();
});

describe('a film’s card', () => {
  it('is drawn under a film’s line, in any lead, and its poster is not drawn again as a picture', () => {
    const view = mount(`Harbour\n${LINE}\n- ${LINE}\nLook ${LINE}\n![](image/other.jpg)`, 'play');
    expect(cards(view)).toHaveLength(2);
    expect(cards(view)[0]!.querySelector('img')!.getAttribute('src')).toBe('http://img.localhost/p1.jpg');
    expect(cards(view)[0]!.textContent).toContain('0:12');
    view.destroy();
    // The poster is drawn once, by its card; a film inside a line of words is a picture there, a fair reading of it.
    const alone = mount(LINE, 'play');
    expect([cards(alone).length, alone.dom.querySelectorAll('figure').length]).toEqual([1, 0]);
    const inWords = mount(`Look ${LINE}`, 'play');
    expect([cards(inWords).length, inWords.dom.querySelectorAll('figure').length]).toEqual([0, 1]);
  });

  it('is not drawn in fenced code', () => {
    expect(cards(mount(`\`\`\`\n${LINE}\n\`\`\``, 'play'))).toHaveLength(0);
  });

  it('plays where the film is here: a disc and Full screen, drawn only once the phone has said so', async () => {
    const view = mount(LINE, 'play');
    const card = cards(view)[0]!;
    expect(card.querySelector('button')).toBeNull();
    await waitUntil(() => expect(card.querySelector('button[aria-label="Play the video, 0:12"]')).not.toBeNull());
    expect(card.querySelector('button[aria-label="Full screen"]')).not.toBeNull();
    expect(wordsOf(card)).toBe('');
    expect(where.asked).toEqual(['f1.mp4']);
    expect(isDrawnBlock(card.querySelector('button'))).toBe(true);
    view.destroy();
  });

  it('says the film is not on this phone, with no disc, before anyone taps', async () => {
    where.film = 'missing';
    const card = cards(mount(LINE, 'play'))[0]!;
    await waitUntil(() => expect(wordsOf(card)).toBe('This video isn’t on this phone.'));
    expect(card.querySelector('button')).toBeNull();
  });

  it('says to update on an older binary, and where the film stays on any other device', async () => {
    where.film = 'update';
    const old = cards(mount(LINE, 'play'))[0]!;
    await waitUntil(() => expect(wordsOf(old)).toBe('Update Ghost.md to play this video.'));
    where.film = 'elsewhere';
    const mac = cards(mount(LINE, 'play'))[0]!;
    await waitUntil(() => expect(wordsOf(mac)).toBe('A video of 0:12. It stays on the phone it was added on.'));
    expect(old.querySelector('button')).toBeNull();
    expect(mac.querySelector('button')).toBeNull();
  });

  it('on a shared page says only a still is shared, and asks nothing', async () => {
    const card = cards(mount(LINE, 'shared'))[0]!;
    expect(wordsOf(card)).toBe('A video of 0:12. Only a still from it is shared.');
    await Promise.resolve();
    expect(where.asked).toEqual([]);
    expect(card.querySelector('button')).toBeNull();
  });

  it('as a still asks nothing of the film, and says only what the device says', async () => {
    where.plays = 'update';
    const old = cards(mount(LINE, 'still'))[0]!;
    await waitUntil(() => expect(wordsOf(old)).toBe('Update Ghost.md to play this video.'));
    where.plays = 'phone';
    const phone = cards(mount(LINE, 'still'))[0]!;
    await waitUntil(() => expect(where.asked).toHaveLength(2));
    await Promise.resolve();
    expect(wordsOf(phone)).toBe('');
    expect(where.asked.every((asked) => asked === '(which device)')).toBe(true);
    expect(phone.querySelector('button, video')).toBeNull();
  });

  it('has words for each reader, which say the length where the line does', () => {
    expect(videoWords('play', 'missing', 12_000)).toBe('This video isn’t on this phone.');
    expect(videoWords('still', 'elsewhere', null)).toBe('A video. It stays on the phone it was added on.');
    expect(videoWords('shared', 'quiet', 3_723_000)).toBe('A video of 1:02:03. Only a still from it is shared.');
    expect(videoWords('play', 'quiet', 12_000)).toBe('');
  });
});

describe('playing', () => {
  it('plays with a tap, over the poster, and pauses with another', async () => {
    const card = cards(mount(LINE, 'play'))[0]!;
    await waitUntil(() => expect(card.querySelector('button[aria-label^="Play"]')).not.toBeNull());
    const toggle = card.querySelector<HTMLButtonElement>('button[aria-label^="Play"]')!;
    toggle.click();
    const film = card.querySelector('video')!;
    expect(film.getAttribute('src')).toBe('http://vid.localhost/f1.mp4');
    expect(film.getAttribute('preload')).toBe('metadata');
    expect(film.autoplay || film.loop).toBe(false);
    expect(card.dataset.playing).toBe('');
    expect(toggle.getAttribute('aria-label')).toBe('Pause');
    toggle.click();
    expect(card.dataset.playing).toBeUndefined();
    expect(toggle.getAttribute('aria-label')).toBe('Play the video, 0:12');
    expect(card.querySelector('img')).not.toBeNull();
  });

  it('plays one film at a time', async () => {
    const view = mount(`${LINE}\n\n[![video 0:03](image/p2.jpg)](video/f2.mp4)`, 'play');
    const [first, second] = cards(view);
    await waitUntil(() => expect(second!.querySelector('button[aria-label^="Play"]')).not.toBeNull());
    first!.querySelector<HTMLButtonElement>('button[aria-label^="Play"]')!.click();
    second!.querySelector<HTMLButtonElement>('button[aria-label^="Play"]')!.click();
    expect(first!.dataset.playing).toBeUndefined();
    expect(second!.dataset.playing).toBe('');
    view.destroy();
  });

  it('says the film is gone when it will not play after all', async () => {
    const card = cards(mount(LINE, 'play'))[0]!;
    await waitUntil(() => expect(card.querySelector('button[aria-label^="Play"]')).not.toBeNull());
    card.querySelector<HTMLButtonElement>('button[aria-label^="Play"]')!.click();
    card.querySelector('video')!.dispatchEvent(new Event('error'));
    expect(wordsOf(card)).toBe('This video isn’t on this phone.');
    expect(card.querySelector('video, button')).toBeNull();
    expect(where.gone).toEqual(['f1.mp4']);
  });

  it('goes full screen in a layer of the page, from where it had got to, and back hands the time back', async () => {
    const card = cards(mount(LINE, 'play'))[0]!;
    await waitUntil(() => expect(card.querySelector('button[aria-label="Full screen"]')).not.toBeNull());
    card.querySelector<HTMLButtonElement>('button[aria-label^="Play"]')!.click();
    const film = card.querySelector('video')!;
    film.currentTime = 4;
    card.querySelector<HTMLButtonElement>('button[aria-label="Full screen"]')!.click();
    const layer = document.body.querySelector<HTMLElement>('[role="dialog"]')!;
    expect(layer.getAttribute('aria-label')).toBe('The video, 0:12, full screen');
    const big = layer.querySelector('video')!;
    expect(big.getAttribute('src')).toBe('http://vid.localhost/f1.mp4');
    expect(big.currentTime).toBe(4);
    expect(card.dataset.playing).toBeUndefined();
    expect(played.at(-1)).toBe(big);
    big.currentTime = 9;
    expect(goBack()).toBe(true);
    expect(document.body.querySelector('[role="dialog"]')).toBeNull();
    expect(film.currentTime).toBe(9);
  });

  it('closes full screen with its own close too', async () => {
    const card = cards(mount(LINE, 'play'))[0]!;
    await waitUntil(() => expect(card.querySelector('button[aria-label="Full screen"]')).not.toBeNull());
    card.querySelector<HTMLButtonElement>('button[aria-label="Full screen"]')!.click();
    document.body.querySelector<HTMLButtonElement>('[role="dialog"] button[aria-label="Close"]')!.click();
    expect(document.body.querySelector('[role="dialog"]')).toBeNull();
    expect(goBack()).toBe(false);
  });
});

describe('the film’s line', () => {
  it('reads as its words off the caret’s line, and as written on it while the note is being written', () => {
    const view = mount(`Harbour\n${LINE}`, 'play', 0);
    expect(shown(view, 2)).toBe('video 0:12');
    vi.spyOn(view, 'hasFocus', 'get').mockReturnValue(true);
    view.dispatch({ selection: { anchor: view.state.doc.length } });
    expect(shown(view, 2)).toBe(LINE);
    view.dispatch({ selection: { anchor: 0 } });
    expect(shown(view, 2)).toBe('video 0:12');
    view.destroy();
  });
});
