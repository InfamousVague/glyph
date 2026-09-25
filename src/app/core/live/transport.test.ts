import { afterEach, describe, expect, it, vi } from 'vitest';
import { WebSocketTransport, liveUrl, type LiveEvents } from './transport.ts';

/** A socket that records what a device sends and lets the test play the relay. */
class FakeSocket {
  static made: FakeSocket[] = [];
  readyState = 0;
  sent: Record<string, unknown>[] = [];
  onopen: ((event: Event) => void) | null = null;
  onmessage: ((event: MessageEvent) => void) | null = null;
  onclose: ((event: CloseEvent) => void) | null = null;
  onerror: ((event: Event) => void) | null = null;
  constructor(readonly url: string) {
    FakeSocket.made.push(this);
  }
  send(text: string) {
    this.sent.push(JSON.parse(text));
  }
  close() {
    this.readyState = 3;
  }
  // The relay's side.
  opens() {
    this.readyState = 1;
    this.onopen?.(new Event('open'));
  }
  says(frame: object) {
    this.onmessage?.({ data: JSON.stringify(frame) } as MessageEvent);
  }
  drops(code = 1006) {
    this.readyState = 3;
    this.onclose?.({ code } as CloseEvent);
  }
}

function recorder() {
  const heard: string[] = [];
  const events: LiveEvents = {
    ready: (id) => heard.push(`ready ${id}`),
    joined: (room, first, peers) => heard.push(`joined ${room} first=${first} peers=${peers}`),
    peers: (room, peers) => heard.push(`peers ${room} ${peers}`),
    message: (room, from, data) => heard.push(`msg ${room} from=${from} ${data}`),
    down: (why) => heard.push(`down ${why}`),
  };
  return { heard, events };
}

/**
 * Every transport a test made, closed after it: a transport left open still hears the window's online and
 * visibilitychange, and would reconnect in the middle of the next test.
 */
const transports: WebSocketTransport[] = [];
afterEach(() => {
  for (const made of transports.splice(0)) made.close();
});

function transport(events: LiveEvents, token: () => string | null = () => 'tok') {
  FakeSocket.made = [];
  const retries: (() => void)[] = [];
  const t = new WebSocketTransport({
    url: 'wss://example/live',
    token,
    events,
    socket: FakeSocket as never,
    schedule: (run) => retries.push(run),
  });
  transports.push(t);
  return { t, retries, socket: () => FakeSocket.made[FakeSocket.made.length - 1]! };
}

describe('the relay transport', () => {
  it('finds the relay beside the service', () => {
    expect(liveUrl('https://attack.fm/glyph/api')).toBe('wss://attack.fm/glyph/api/v1/live');
    expect(liveUrl('http://127.0.0.1:8796/glyph/api')).toBe('ws://127.0.0.1:8796/glyph/api/v1/live');
  });

  it('signs in with its first frame, and says nothing else until the relay is ready', () => {
    const { heard, events } = recorder();
    const { t, socket } = transport(events);
    t.join('note');
    socket().opens();
    // The join asked for before the relay was ready is not sent early: only the sign-in is.
    expect(socket().sent).toEqual([{ t: 'auth', token: 'tok' }]);
    socket().says({ t: 'ready', id: 7 });
    expect(socket().sent[1]).toEqual({ t: 'join', room: 'note' });
    socket().says({ t: 'joined', room: 'note', first: true, peers: 0 });
    socket().says({ t: 'msg', room: 'note', from: 9, data: 'abc' });
    expect(heard).toEqual(['ready 7', 'joined note first=true peers=0', 'msg note from=9 abc']);
  });

  it('comes back after a drop and rejoins every room it was in', () => {
    const { heard, events } = recorder();
    const { t, retries, socket } = transport(events);
    t.join('a');
    t.join('b');
    socket().opens();
    socket().says({ t: 'ready', id: 1 });
    socket().drops();
    expect(heard).toContain('down network');
    expect(retries).toHaveLength(1);
    retries[0]!();
    const again = socket();
    again.opens();
    again.says({ t: 'ready', id: 2 });
    expect(again.sent).toEqual([{ t: 'auth', token: 'tok' }, { t: 'join', room: 'a' }, { t: 'join', room: 'b' }]);
  });

  it('does not keep knocking once the relay has refused the token', () => {
    const { heard, events } = recorder();
    const { retries, socket } = transport(events);
    socket().opens();
    socket().drops(4401);
    expect(heard).toEqual(['down signIn']);
    expect(retries).toHaveLength(0);
  });

  it('does not connect at all while signed out', () => {
    const { heard, events } = recorder();
    transport(events, () => null);
    expect(FakeSocket.made).toHaveLength(0);
    expect(heard).toEqual(['down signIn']);
  });

  it('sends only into rooms it is in, and nothing while down', () => {
    const { events } = recorder();
    const { t, socket } = transport(events);
    socket().opens();
    socket().says({ t: 'ready', id: 1 });
    t.send('not-joined', 'x');
    t.join('n');
    t.send('n', 'y', 4);
    t.leave('n');
    t.send('n', 'z');
    expect(socket().sent.slice(1)).toEqual([
      { t: 'join', room: 'n' },
      { t: 'msg', room: 'n', data: 'y', to: 4 },
      { t: 'leave', room: 'n' },
    ]);
  });
});

describe('coming back after a drop', () => {
  afterEach(() => {
    vi.restoreAllMocks();
    Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' });
  });

  /** A transport whose retries are kept with the wait each was scheduled for. */
  function timed(events: LiveEvents) {
    FakeSocket.made = [];
    const waits: { run: () => void; ms: number }[] = [];
    const t = new WebSocketTransport({ url: 'wss://example/live', token: () => 'tok', events, socket: FakeSocket as never, schedule: (run, ms) => waits.push({ run, ms }) });
    transports.push(t);
    return { t, waits, socket: () => FakeSocket.made[FakeSocket.made.length - 1]! };
  }

  it('waits twice as long each time from half a second, never past thirty, and from the start again once signed in', () => {
    vi.spyOn(Math, 'random').mockReturnValue(1);
    const { events } = recorder();
    const { waits, socket } = timed(events);
    for (let i = 0; i < 8; i += 1) {
      socket().drops();
      waits.at(-1)!.run();
    }
    expect(waits.map((wait) => wait.ms)).toEqual([500, 1_000, 2_000, 4_000, 8_000, 16_000, 30_000, 30_000]);
    socket().opens();
    socket().says({ t: 'ready', id: 3 });
    socket().drops();
    expect(waits.at(-1)?.ms).toBe(500);
  });

  it('spreads each wait over its second half, so a relay restart is not met by every device at once', () => {
    vi.spyOn(Math, 'random').mockReturnValue(0);
    const { events } = recorder();
    const { waits, socket } = timed(events);
    socket().drops();
    waits.at(-1)!.run();
    socket().drops();
    expect(waits.map((wait) => wait.ms)).toEqual([250, 500]);
  });

  it('tries at once when the network or the page comes back, and not while the page is hidden', () => {
    const { events } = recorder();
    const { waits, socket } = timed(events);
    socket().drops();
    expect(FakeSocket.made).toHaveLength(1);
    Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' });
    window.dispatchEvent(new Event('online'));
    expect(FakeSocket.made).toHaveLength(1);
    Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' });
    document.dispatchEvent(new Event('visibilitychange'));
    expect(FakeSocket.made).toHaveLength(2);
    // Connected again: the waiting retry was dropped, and another wake while connected does nothing.
    window.dispatchEvent(new Event('online'));
    expect(FakeSocket.made).toHaveLength(2);
    expect(waits).toHaveLength(1);
  });

  it('stays down once closed, whatever wakes it', () => {
    const { events } = recorder();
    const { t, socket } = timed(events);
    socket().opens();
    t.close();
    socket().drops();
    window.dispatchEvent(new Event('online'));
    expect(FakeSocket.made).toHaveLength(1);
  });

  it('ignores a frame it cannot read and a refusal, and keeps the socket', () => {
    const { heard, events } = recorder();
    const { socket } = timed(events);
    socket().opens();
    socket().onmessage?.({ data: '{not json' } as MessageEvent);
    socket().says({ t: 'error', message: 'too fast' });
    socket().says({ t: 'ready', id: 4 });
    expect(heard).toEqual(['ready 4']);
  });
});
