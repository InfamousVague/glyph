// The bridge as one member of a Ghost space: in the call's room it answers (or makes) a WebRTC connection with each
// member like any app does, says who it is ({t:'me', n:'Discord'}) and who is on the Discord side ({t:'dc', people});
// in the chat room it says hello, passes messages both ways and answers history like any member. The protocol is
// lib/voice/voice.dart's and lib/voice/hangout.dart's (and site/join/voice.js's): everything sealed with the space's
// key, a message with `to` meant for that member alone.
//
// Nothing here knows Discord, and the WebRTC connections come from a factory (rtc.js in the bot, a fake in tests).
import { highestOpus, messageId, openJson, sealJson, spaceKeys } from './protocol.js';

const MAX_TEXT = 4000;
const KEEP = 300;

export class GhostSpace {
  /**
   * hub: Hub; seed: 64 hex; peers: the WebRTC factory; on: { members(list), audio(id, opus), chat({from, name,
   * text}), peerUp(id), peerDown(id) } (any may be left out).
   */
  constructor({ hub, seed, peers, on = {}, name = 'Discord', now = Date.now, log = () => {} }) {
    this.hub = hub;
    this.keys = spaceKeys(seed);
    this.peers = peers;
    this.on = on;
    this.name = name;
    this.now = now;
    this.log = log;
    this.members = new Map(); // id -> { name, peer, up, described }
    this.present = new Map(); // chat room: id -> name
    this.messages = []; // the chat, in memory only: { id, x, at, n, f }
    this.people = [];
    this.inVoice = false;
    this.inChat = false;
    this.closed = false;
    this.offs = [hub.on('event', (m) => this.event(m)), hub.on('packet', (p) => this.packet(p))];
  }

  get me() {
    return this.hub.me.id;
  }

  /** Joins both rooms. Resolves when the call's room has let the bridge in. */
  async open() {
    const chat = this.hub.join(this.keys.chatRoom, this.keys.chatToken).catch((e) => this.log(`chat room: ${e.message}`));
    await this.hub.join(this.keys.voiceRoom, this.keys.voiceToken);
    await chat;
  }

  async close() {
    if (this.closed) return;
    this.closed = true;
    for (const off of this.offs) off();
    this.hub.leave(this.keys.voiceRoom);
    this.hub.leave(this.keys.chatRoom);
    const peers = [...this.members.values()].map((m) => m.peer).filter(Boolean);
    this.members.clear();
    this.present.clear();
    await Promise.all(peers.map((p) => p.close().catch(() => {})));
  }

  /** The Ghost members in the call (not the bridge): [{ id, name }]. */
  list() {
    return [...this.members].map(([id, m]) => ({ id, name: m.name }));
  }

  changed() {
    this.on.members?.(this.list());
  }

  // --- saying things ------------------------------------------------------------------------------------------------

  sayVoice(what) {
    if (!this.inVoice || this.closed) return;
    this.hub.sendRoom(this.keys.voiceRoom, sealJson(this.keys.key, what));
  }

  sayChat(what) {
    if (!this.inChat || this.closed) return;
    this.hub.sendRoom(this.keys.chatRoom, sealJson(this.keys.key, what));
  }

  sayMe() {
    this.sayVoice({ t: 'me', n: this.name, m: false, v: false });
  }

  /** Who is in the Discord channel, said to the call (on every change, and every few seconds by the bridge). */
  setPeople(people) {
    this.people = people;
    this.sayDc();
  }

  sayDc() {
    this.sayVoice({ t: 'dc', people: this.people });
  }

  /** A message into the space's chat, as from [name] (a Discord author). False when there was nothing to send. */
  sendChat({ name, text, at = this.now() }) {
    const x = String(text ?? '').trim().slice(0, MAX_TEXT);
    if (!x || !this.inChat) return false;
    const m = { id: messageId(), x, at, n: String(name ?? '').slice(0, 100) };
    this.keep([{ ...m, f: this.me }]);
    this.sayChat({ t: 'msg', ...m });
    return true;
  }

  keep(list) {
    const have = new Set(this.messages.map((m) => m.id));
    const more = list.filter((m) => m && typeof m.id === 'string' && typeof m.x === 'string' && typeof m.at === 'number' && !have.has(m.id) && have.add(m.id));
    if (!more.length) return [];
    this.messages = [...this.messages, ...more].sort((a, b) => a.at - b.at).slice(-KEEP);
    return more;
  }

  // --- the hub ------------------------------------------------------------------------------------------------------

  event(m) {
    if (this.closed) return;
    if (m.room === this.keys.voiceRoom) this.voiceEvent(m);
    else if (m.room === this.keys.chatRoom) this.chatEvent(m);
  }

  voiceEvent(m) {
    if ('ok' in m) {
      if (!m.ok) return;
      // In (or in again after the hub reconnected): the newcomer offers, so the bridge offers to everyone there.
      this.inVoice = true;
      const there = new Set((m.members ?? []).filter((id) => id !== this.me));
      for (const id of [...this.members.keys()]) if (!there.has(id)) this.drop(id);
      for (const id of there) {
        this.drop(id, false);
        this.members.set(id, { name: '', peer: null, up: false, described: false });
        this.offer(id);
      }
      this.sayMe();
      this.sayDc();
      this.changed();
    } else if (typeof m.came === 'string' && m.came !== this.me) {
      // They offer: they came in.
      this.drop(m.came, false);
      this.members.set(m.came, { name: '', peer: null, up: false, described: false });
      this.sayMe();
      this.sayDc();
      this.changed();
    } else if (typeof m.went === 'string') {
      this.drop(m.went);
    }
  }

  chatEvent(m) {
    if ('ok' in m) {
      if (!m.ok) return;
      this.inChat = true;
      for (const id of m.members ?? []) if (!this.present.has(id)) this.present.set(id, '');
      this.hi();
    } else if (typeof m.came === 'string') {
      this.present.set(m.came, '');
      this.hi();
    } else if (typeof m.went === 'string') {
      this.present.delete(m.went);
    }
  }

  hi() {
    this.sayChat({ t: 'hi', n: this.name, a: true });
  }

  /** A member gone: their connection closed, their sound dropped. */
  drop(id, tell = true) {
    const had = this.members.get(id);
    if (!had) return;
    this.members.delete(id);
    if (had.peer) had.peer.close().catch(() => {});
    if (had.up) this.on.peerDown?.(id);
    if (tell) this.changed();
  }

  peerFor(id) {
    const m = this.members.get(id);
    if (!m) return null;
    if (m.peer) return m.peer;
    const peer = this.peers(id, {
      onCandidate: (c) => this.sayVoice({ t: 'ice', to: id, c }),
      onAudio: (opus) => this.on.audio?.(id, opus),
      onState: (state) => {
        const cur = this.members.get(id);
        if (!cur || cur.peer !== peer) return;
        if (state === 'connected' && !cur.up) {
          cur.up = true;
          this.on.peerUp?.(id);
        } else if ((state === 'failed' || state === 'closed') && cur.up) {
          cur.up = false;
          this.on.peerDown?.(id);
        }
      },
    });
    m.peer = peer;
    return peer;
  }

  async offer(id) {
    try {
      const sdp = await this.peerFor(id)?.makeOffer();
      if (sdp && this.members.has(id)) this.sayVoice({ t: 'offer', to: id, sdp: highestOpus(sdp) });
    } catch (e) {
      this.log(`offer failed: ${e?.message ?? e}`);
    }
  }

  packet(p) {
    if (this.closed) return;
    if (p.room === this.keys.voiceRoom) this.voicePacket(p.from, openJson(this.keys.key, p.sealed));
    else if (p.room === this.keys.chatRoom) this.chatPacket(p.from, openJson(this.keys.key, p.sealed));
  }

  async voicePacket(from, m) {
    if (!m || from === this.me) return;
    if (m.to && m.to !== this.me) return;
    try {
      if (m.t === 'me') {
        const had = this.members.get(from) ?? { name: '', peer: null, up: false, described: false };
        const name = String(m.n ?? '').slice(0, 100);
        const was = this.members.has(from) ? had.name : null;
        this.members.set(from, { ...had, name });
        if (was !== name) this.changed();
      } else if (m.t === 'offer' && typeof m.sdp === 'string') {
        let had = this.members.get(from);
        const name = had?.name ?? '';
        if (had?.described) {
          // A second offer: they started over (an app that came back). A fresh connection.
          this.drop(from, false);
          had = null;
        }
        if (!had) {
          this.members.set(from, { name, peer: null, up: false, described: false });
          this.changed();
        }
        const cur = this.members.get(from);
        cur.described = true;
        const answer = await this.peerFor(from).takeOffer(m.sdp);
        if (this.members.get(from) !== cur) return;
        this.sayVoice({ t: 'answer', to: from, sdp: highestOpus(answer) });
        // Said again for the newcomer, who may have joined after it was said.
        this.sayMe();
        this.sayDc();
      } else if (m.t === 'answer' && typeof m.sdp === 'string') {
        const cur = this.members.get(from);
        if (!cur?.peer) return;
        cur.described = true;
        await cur.peer.takeAnswer(m.sdp);
      } else if (m.t === 'ice' && m.c && typeof m.c === 'object') {
        if (!this.members.has(from)) return;
        await this.peerFor(from)?.addCandidate(m.c);
      }
    } catch (e) {
      this.log(`signalling (${m.t}) failed: ${e?.message ?? e}`);
    }
  }

  chatPacket(from, m) {
    if (!m || from === this.me) return;
    if (m.to && m.to !== this.me) return;
    if (m.t === 'hi') {
      this.present.set(from, String(m.n ?? '').slice(0, 100));
    } else if (m.t === 'msg') {
      const msg = { id: m.id, x: String(m.x ?? '').trim().slice(0, MAX_TEXT), at: m.at, n: String(m.n ?? '').slice(0, 100), f: from };
      if (!msg.x) return;
      for (const added of this.keep([msg])) this.on.chat?.({ from, name: added.n, text: added.x, id: added.id });
    } else if (m.t === 'hist') {
      // Old messages, for the bridge's own history only: never passed on to Discord again.
      this.keep((Array.isArray(m.m) ? m.m : []).filter((x) => x && typeof x.f === 'string').map((x) => ({ id: x.id, x: String(x.x ?? ''), at: x.at, n: String(x.n ?? ''), f: x.f })));
    } else if (m.t === 'sync?') {
      if (this.answers(from)) {
        const since = typeof m.since === 'number' ? m.since : 0;
        const missed = this.messages.filter((x) => x.at > since);
        if (missed.length) this.sayChat({ t: 'hist', to: from, m: missed.map((x) => ({ id: x.id, x: x.x, at: x.at, n: x.n, f: x.f })) });
      }
    } else if (m.t === 'del') {
      this.messages = this.messages.filter((x) => !(x.id === m.id && x.f === from));
    }
  }

  /** Whether the bridge is the one to answer [asker]'s history question: the lowest id of those here besides them. */
  answers(asker) {
    return [this.me, ...[...this.present.keys()].filter((id) => id !== asker)].sort()[0] === this.me;
  }

  /** The bridge's mix for one member (20 ms of Opus). */
  sendAudio(id, opus) {
    const m = this.members.get(id);
    if (m?.up && m.peer) m.peer.send(opus);
  }
}
