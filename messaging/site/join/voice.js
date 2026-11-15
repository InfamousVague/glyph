// A Ghost Messaging hangout in a browser (Matt, 2026-11-14: "Make the voice hangouts possible to share via a link so
// people can join to talk anonymously or sign up through the browser similar to a zoom meeting").
//
// The app's own protocol, as lib/voice/voice.dart, lib/voice/rtc.dart, lib/net/hub_carrier.dart and lib/net/crypto.dart
// have it (tool/voicebench/bench.html measured the same against the relay): a key pair, the hub's greeting signed with
// it, the room's name, token and key made from the channel's seed, everything said in the room sealed with that key,
// the newcomer offering, Opus at 510 kb/s stereo and the picture sized by how many are in the call.
//
// The seed comes from the link's fragment (after the #), which a browser never sends to any server: the relay sees
// that someone is in some room, never what is said or which channel it is.

const enc = new TextEncoder(), dec = new TextDecoder();
export const hex = (b) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('');
export const unhex = (h) => new Uint8Array((h.match(/../g) ?? []).map((x) => parseInt(x, 16)));
const b64 = (b) => btoa(String.fromCharCode(...new Uint8Array(b)));
const sha256 = async (b) => new Uint8Array(await crypto.subtle.digest('SHA-256', b));
async function hmac(key, data) {
  const k = await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', k, data));
}
const derive = (key, label) => hmac(key, new Uint8Array([...enc.encode('ghost-net ' + label), 1]));
const AAD = enc.encode('ghost-net-v1');
async function seal(key, clear) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: AAD, tagLength: 128 }, key, clear));
  return new Uint8Array([...iv, ...ct]);
}
async function open(key, sealed) {
  try { return new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: sealed.slice(0, 12), additionalData: AAD, tagLength: 128 }, key, sealed.slice(12))); } catch (_) { return null; }
}

/** The link's fragment: the channel's seed, and its name. Null where it is not one. */
export function readLink(fragment) {
  const m = /^#?([0-9a-f]{64})(?:\.([A-Za-z0-9_-]*))?$/.exec(fragment ?? '');
  if (!m) return null;
  let name = 'Hangout';
  try { if (m[2]) name = dec.decode(Uint8Array.from(atob(m[2].replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0))) || name; } catch (_) {}
  return { seed: m[1], name };
}

// lib/voice/voice.dart highestOpus and videoFor.
export function highestOpus(sdp) {
  const lines = sdp.split('\r\n');
  const opus = /^a=rtpmap:(\d+) opus\/48000/i;
  const pts = new Set(lines.filter((l) => opus.test(l)).map((l) => l.match(opus)[1]));
  if (!pts.size) return sdp;
  const want = { minptime: '10', useinbandfec: '1', stereo: '1', 'sprop-stereo': '1', maxaveragebitrate: '510000', maxplaybackrate: '48000', cbr: '1', usedtx: '0' };
  const out = [];
  for (const l of lines) {
    const f = l.match(/^a=fmtp:(\d+) (.*)$/);
    if (f && pts.has(f[1])) {
      const p = {};
      for (const kv of f[2].split(';')) { const i = kv.indexOf('='); if (i > 0) p[kv.slice(0, i).trim()] = kv.slice(i + 1).trim(); }
      Object.assign(p, want);
      out.push('a=fmtp:' + f[1] + ' ' + Object.entries(p).map(([k, v]) => k + '=' + v).join(';'));
      continue;
    }
    out.push(l);
    const r = l.match(opus);
    if (r && !lines.some((x) => x.startsWith('a=fmtp:' + r[1] + ' '))) out.push('a=fmtp:' + r[1] + ' ' + Object.entries(want).map(([k, v]) => k + '=' + v).join(';'));
  }
  return out.join('\r\n');
}
export const videoFor = (others) => (others <= 1 ? { scale: 1, bitrate: 12000000 } : others === 2 ? { scale: 1.5, bitrate: 4000000 } : others <= 4 ? { scale: 2, bitrate: 2000000 } : { scale: 3, bitrate: 1000000 });

// --- who this browser is ------------------------------------------------------------------------------------------

/** This browser's key pair: kept (the private half unreadable even to this page) where [keep], else made for now. */
export async function identity(keep) {
  const db = keep ? await new Promise((done) => {
    const r = indexedDB.open('ghost-voice', 1);
    r.onupgradeneeded = () => r.result.createObjectStore('keys');
    r.onsuccess = () => done(r.result);
    r.onerror = () => done(null);
  }) : null;
  const get = (k) => new Promise((done) => { if (!db) return done(null); const q = db.transaction('keys').objectStore('keys').get(k); q.onsuccess = () => done(q.result ?? null); q.onerror = () => done(null); });
  const put = (k, v) => new Promise((done) => { if (!db) return done(); const t = db.transaction('keys', 'readwrite'); t.objectStore('keys').put(v, k); t.oncomplete = done; t.onerror = done; });
  let pair = await get('pair');
  if (!pair) {
    pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
    await put('pair', pair);
  }
  const raw = new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey));
  const pub = new Uint8Array([raw[64] & 1 ? 3 : 2, ...raw.slice(1, 33)]);
  const id = hex((await sha256(pub)).slice(0, 16));
  return { id, pub, sign: async (bytes) => new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, pair.privateKey, bytes)) };
}

// --- the hub ------------------------------------------------------------------------------------------------------

/** A connection to the relay's hub, signed in as [me]. */
export async function connectHub(url, me) {
  const ws = new WebSocket(url);
  ws.binaryType = 'arraybuffer';
  const hub = { ws, me, json: new Set(), bin: new Set(), waiting: new Map() };
  hub.say = (m) => ws.readyState === 1 && ws.send(JSON.stringify(m));
  hub.dir = (m, answer) => new Promise((done, fail) => {
    hub.waiting.set(answer, { done, fail });
    hub.say(m);
    setTimeout(() => { if (hub.waiting.delete(answer)) fail(new Error('The relay server did not answer.')); }, 15000);
  });
  await new Promise((done, fail) => {
    ws.onerror = () => fail(new Error('The relay server can’t be reached.'));
    ws.onclose = () => fail(new Error('The relay server closed the connection.'));
    ws.onmessage = async (e) => {
      if (typeof e.data !== 'string') { for (const f of hub.bin) f(new Uint8Array(e.data)); return; }
      const m = JSON.parse(e.data);
      if (m.hello) {
        const sig = await me.sign(new Uint8Array([...enc.encode('ghost-hub v1 '), ...unhex(m.hello)]));
        hub.say({ id: me.id, key: b64(me.pub), sig: b64(sig) });
      } else if ('ok' in m && !m.room && !hub.up) {
        if (!m.ok) return fail(new Error('The relay server refused this browser.'));
        hub.up = true;
        done();
      } else if (m.dir) {
        const w = hub.waiting.get(m.dir) ?? (m.dir === 'err' ? hub.waiting.get(m.about) : null);
        if (w) { hub.waiting.delete(m.dir === 'err' ? m.about : m.dir); m.dir === 'err' ? w.fail(new Error(m.err)) : w.done(m); }
      } else {
        for (const f of hub.json) f(m);
      }
    };
  });
  ws.onclose = () => { hub.up = false; for (const f of hub.json) f({ closed: true }); };
  return hub;
}

// --- a hangout ----------------------------------------------------------------------------------------------------

/** One channel: who is in it before joining, and being in it. [onChange] is called whenever anything shown changes. */
export class Hangout {
  constructor(hub, seed, onChange) {
    this.hub = hub;
    this.seedHex = seed;
    this.onChange = onChange;
    this.members = new Map(); // id -> { name, muted, video, guest, stream }
    this.peers = new Map();
    this.early = new Map();
    this.here = [];
    this.joined = false;
    this.muted = false;
    this.video = false;
  }

  async prepare() {
    const s = unhex(this.seedHex);
    this.room = hex((await derive(s, 'voice room')).slice(0, 16));
    this.token = hex(await derive(s, 'voice token'));
    this.key = await crypto.subtle.importKey('raw', await derive(s, 'voice key'), 'AES-GCM', false, ['encrypt', 'decrypt']);
    this.hub.json.add((m) => this.event(m));
    this.hub.bin.add((d) => this.packet(d));
    // Who is in it, without joining.
    this.hub.say({ look: this.room, token: this.token });
  }

  change() { this.onChange?.(); }

  async join({ name, guest, audio = true, video = false }) {
    this.name = name;
    this.guest = guest;
    this.mic = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: false, autoGainControl: false, channelCount: 2, sampleRate: 48000 }, video: false });
    if (!audio) this.setMuted(true);
    if (video) await this.setVideo(true);
    this.hub.say({ join: this.room, token: this.token });
  }

  event(m) {
    if (m.closed) { this.lost = true; return this.change(); }
    if (m.room !== this.room) return;
    if (Array.isArray(m.look)) { this.here = m.look; return this.change(); }
    if ('ok' in m) {
      if (!m.ok) { this.refused = m.err ?? 'refused'; return this.change(); }
      this.joined = true;
      for (const id of m.members) this.members.set(id, this.members.get(id) ?? { name: '' });
      this.sayMe();
      for (const id of m.members) this.offer(id);
      setTimeout(() => this.retune(), 1500);
    } else if (m.came) {
      this.members.set(m.came, this.members.get(m.came) ?? { name: '' });
      this.sayMe();
      setTimeout(() => this.retune(), 1500);
    } else if (m.went) {
      this.members.delete(m.went);
      this.peers.get(m.went)?.close();
      this.peers.delete(m.went);
      this.retune();
    }
    this.change();
  }

  sayMe() { this.say({ t: 'me', n: this.name, m: this.muted, v: this.video, g: this.guest }); }

  async say(what) {
    if (!this.joined && what.t !== 'me') return;
    const sealed = await seal(this.key, enc.encode(JSON.stringify(what)));
    if (this.hub.ws.readyState === 1) this.hub.ws.send(new Uint8Array([2, ...unhex(this.room), ...sealed]));
  }

  async packet(d) {
    if (d[0] !== 2 || d.length < 34 || hex(d.slice(1, 17)) !== this.room) return;
    const from = hex(d.slice(17, 33));
    const clear = await open(this.key, d.slice(33));
    if (!clear) return;
    let m;
    try { m = JSON.parse(dec.decode(clear)); } catch (_) { return; }
    if (m.to && m.to !== this.hub.me.id) return;
    if (m.t === 'me') {
      const had = this.members.get(from) ?? {};
      this.members.set(from, { ...had, name: String(m.n ?? ''), muted: !!m.m, video: !!m.v, guest: !!m.g });
      this.change();
    } else if (m.t === 'offer') {
      const pc = this.pc(from);
      await pc.setRemoteDescription({ type: 'offer', sdp: m.sdp });
      await this.flush(from);
      for (const t of pc.getTransceivers()) {
        const kind = t.receiver.track?.kind;
        if (kind === 'audio') await t.sender.replaceTrack(this.mic.getAudioTracks()[0]);
        if (kind === 'video') await t.sender.replaceTrack(this.cam?.getVideoTracks()[0] ?? null);
        t.direction = 'sendrecv';
      }
      const answer = await pc.createAnswer();
      const sdp = highestOpus(answer.sdp);
      await pc.setLocalDescription({ type: 'answer', sdp });
      await this.highest(pc);
      this.say({ t: 'answer', to: from, sdp });
      this.sayMe();
    } else if (m.t === 'answer') {
      const pc = this.peers.get(from);
      if (!pc) return;
      await pc.setRemoteDescription({ type: 'answer', sdp: m.sdp });
      await this.flush(from);
    } else if (m.t === 'ice' && m.c) {
      const pc = this.pc(from);
      if (pc.remoteDescription) await pc.addIceCandidate(m.c).catch(() => {});
      else (this.early.get(from) ?? this.early.set(from, []).get(from)).push(m.c);
    }
  }

  async flush(from) {
    for (const c of this.early.get(from) ?? []) await this.peers.get(from).addIceCandidate(c).catch(() => {});
    this.early.delete(from);
  }

  pc(id) {
    let pc = this.peers.get(id);
    if (pc) return pc;
    pc = new RTCPeerConnection({ iceServers: [{ urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'] }] });
    pc.onicecandidate = (e) => { if (e.candidate) this.say({ t: 'ice', to: id, c: { candidate: e.candidate.candidate, sdpMid: e.candidate.sdpMid, sdpMLineIndex: e.candidate.sdpMLineIndex } }); };
    pc.ontrack = (e) => {
      const m = this.members.get(id) ?? { name: '' };
      const stream = m.stream ?? e.streams[0] ?? new MediaStream();
      if (!stream.getTracks().includes(e.track)) stream.addTrack(e.track);
      this.members.set(id, { ...m, stream });
      this.change();
    };
    pc.onconnectionstatechange = () => this.change();
    this.peers.set(id, pc);
    return pc;
  }

  async offer(id) {
    const pc = this.pc(id);
    const vf = videoFor(this.members.size);
    pc.addTransceiver(this.mic.getAudioTracks()[0], { direction: 'sendrecv', streams: [this.mic] });
    const v = pc.addTransceiver('video', { direction: 'sendrecv', sendEncodings: [{ maxBitrate: vf.bitrate, maxFramerate: 30, scaleResolutionDownBy: vf.scale }] });
    if (this.cam) await v.sender.replaceTrack(this.cam.getVideoTracks()[0]);
    const offer = await pc.createOffer();
    const sdp = highestOpus(offer.sdp);
    await pc.setLocalDescription({ type: 'offer', sdp });
    await this.highest(pc);
    this.say({ t: 'offer', to: id, sdp });
  }

  async highest(pc) {
    const vf = videoFor(this.members.size);
    for (const s of pc.getSenders()) {
      const p = s.getParameters();
      if (!p.encodings?.length) continue;
      for (const e of p.encodings) {
        e.maxBitrate = s.track?.kind === 'audio' ? 510000 : vf.bitrate;
        if (s.track?.kind === 'video') e.scaleResolutionDownBy = vf.scale;
      }
      if (s.track?.kind === 'video') p.degradationPreference = 'balanced';
      try { await s.setParameters(p); } catch (_) {}
    }
  }

  retune() { for (const pc of this.peers.values()) this.highest(pc); }

  setMuted(on) {
    this.muted = on;
    for (const t of this.mic?.getAudioTracks() ?? []) t.enabled = !on;
    this.sayMe();
    this.change();
  }

  async setVideo(on) {
    if (on && !this.cam) {
      this.cam = await navigator.mediaDevices.getUserMedia({ video: { width: 1920, height: 1080, frameRate: 30, facingMode: 'user' } });
    } else if (!on && this.cam) {
      for (const t of this.cam.getTracks()) t.stop();
      this.cam = null;
    }
    this.video = !!this.cam;
    for (const pc of this.peers.values()) {
      for (const t of pc.getTransceivers()) {
        if (t.receiver.track?.kind === 'video') await t.sender.replaceTrack(this.cam?.getVideoTracks()[0] ?? null);
      }
      await this.highest(pc);
    }
    this.sayMe();
    this.change();
  }

  leave() {
    this.hub.say({ leave: this.room });
    for (const pc of this.peers.values()) pc.close();
    this.peers.clear();
    for (const s of [this.mic, this.cam]) for (const t of s?.getTracks() ?? []) t.stop();
    this.mic = this.cam = null;
    for (const m of this.members.values()) delete m.stream;
    this.members.clear();
    this.joined = false;
    this.change();
  }
}
