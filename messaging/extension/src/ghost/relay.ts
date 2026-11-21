// The connection to the Ghost Messaging relay's hub (messaging/relay/lib/hub.dart), as a device of the account: the
// same handshake the app makes (sign the hub's nonce with the P-256 identity), then the request/reply `dir` messages
// the app uses. We use only `acct-find` / `acct-get` / `acct-seed` to sign in and `curl-keep` / `curl-kept` to carry
// the captured cookies. The relay holds the cookies only sealed; it cannot read them.
import { b64, identityPublicOf, idOf, signIdentity, unhex, utf8, type Bytes } from './crypto.ts';

const GREETING = 'ghost-hub v1 '; // hub.dart's `greeting`
const DEFAULT_HUB = 'wss://gogho.st/hub';

// Replaced at build time by esbuild's `define` (see build.mjs); the live hub otherwise.
declare const __GHOST_HUB__: string | undefined;

/** The hub endpoint, fixed at build time; falls back to the live one. */
export const HUB_URL: string = (typeof __GHOST_HUB__ !== 'undefined' && __GHOST_HUB__) || DEFAULT_HUB;

export class RelayError extends Error {}

interface Pending {
  dir: string;
  resolve: (m: Record<string, unknown>) => void;
  reject: (e: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

/** A live hub connection under one identity. `connect` resolves once the hub has accepted the handshake. */
export class Hub {
  private ws: WebSocket;
  private readonly pending: Pending[] = [];
  private ready = false;
  private closedWith: Error | null = null;

  private constructor(
    url: string,
    private readonly scalar: Bytes,
    readonly id: string,
    private readonly device: string,
    private readonly onReady: () => void,
    private readonly onError: (e: Error) => void,
  ) {
    this.ws = new WebSocket(url);
    this.ws.binaryType = 'arraybuffer';
    this.ws.onmessage = (e) => this.heard(e.data);
    this.ws.onerror = () => this.fail(new RelayError('The relay could not be reached.'));
    this.ws.onclose = () => this.fail(this.closedWith ?? new RelayError('The relay connection closed.'));
  }

  /** Opens a hub connection as `scalar` (a P-256 identity private key). `device` is shown on the account's device list. */
  static connect(scalar: Bytes, device: string, url: string = HUB_URL): Promise<Hub> {
    return new Promise((resolve, reject) => {
      const id = idOf(identityPublicOf(scalar));
      const hub = new Hub(url, scalar, id, device, () => resolve(hub), reject);
    });
  }

  private fail(e: Error): void {
    if (this.closedWith) return;
    this.closedWith = e;
    for (const p of this.pending.splice(0)) {
      clearTimeout(p.timer);
      p.reject(e);
    }
    if (!this.ready) this.onError(e);
  }

  private heard(data: unknown): void {
    if (typeof data !== 'string') return; // binary packets (presence etc.) are not used here
    let m: Record<string, unknown>;
    try {
      m = JSON.parse(data);
    } catch {
      return;
    }
    if (!this.ready) {
      if (typeof m.hello === 'string') {
        this.sayHello(m.hello);
        return;
      }
      if (m.ok === true) {
        this.ready = true;
        this.onReady();
        return;
      }
      if (m.ok === false) {
        this.closedWith = new RelayError(`${m.err ?? 'The relay refused the connection.'}`);
        return;
      }
      return;
    }
    const dir = m.dir;
    if (typeof dir !== 'string') return;
    if (dir === 'err') {
      const about = m.about;
      const i = this.pending.findIndex((p) => p.dir === about);
      if (i >= 0) {
        const [p] = this.pending.splice(i, 1);
        clearTimeout(p.timer);
        p.reject(new RelayError(`${m.err ?? 'The relay could not do that.'}`));
      }
      return;
    }
    const i = this.pending.findIndex((p) => p.dir === dir);
    if (i >= 0) {
      const [p] = this.pending.splice(i, 1);
      clearTimeout(p.timer);
      p.resolve(m);
    }
  }

  private sayHello(nonceHex: string): void {
    const message = new Uint8Array([...utf8(GREETING), ...unhex(nonceHex)]);
    const sig = signIdentity(this.scalar, message);
    this.ws.send(JSON.stringify({ id: this.id, key: b64(identityPublicOf(this.scalar)), sig: b64(sig), device: this.device }));
  }

  /** Sends `{dir, ...body}` and resolves on the reply whose `dir` matches (or rejects on an `err` about it). */
  ask(dir: string, body: Record<string, unknown> = {}, waitMs = 25000): Promise<Record<string, unknown>> {
    if (this.closedWith) return Promise.reject(this.closedWith);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        const i = this.pending.findIndex((p) => p.resolve === resolve);
        if (i >= 0) this.pending.splice(i, 1);
        reject(new RelayError('The relay did not answer in time.'));
      }, waitMs);
      this.pending.push({ dir, resolve, reject, timer });
      this.ws.send(JSON.stringify({ dir, ...body }));
    });
  }

  close(): void {
    this.closedWith ??= new RelayError('closed');
    try {
      this.ws.close(1000, 'done');
    } catch {
      // already closing
    }
  }
}
