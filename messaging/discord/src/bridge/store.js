// What the bridge keeps: its own key (its Ghost hub id stays the same across restarts), one seed per bridged Discord
// voice channel, and the webhook it posts Ghost messages through in that channel. In bridges.json beside links.json,
// readable only by the service's user, written whole to a temporary file and renamed over the old one.
//
// A seed is 32 random bytes made once per (server, channel) and never derived from anything public: whoever has it
// can be in the space, so only the app of someone linked to the server (POST /discord/voice/join) is ever told it.
import { randomBytes } from 'node:crypto';
import { closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, renameSync, writeSync } from 'node:fs';
import { dirname, join } from 'node:path';

const SNOWFLAKE = /^\d{15,22}$/;

export class BridgeStore {
  /** file: the JSON file's path, or null to keep everything in memory (tests). random(n): bytes, for tests. */
  constructor(file, { random = randomBytes } = {}) {
    this.file = file;
    this.random = random;
    this.identity = null; // PKCS#8 PEM
    this.channels = new Map(); // "guild:channel" -> { seed, webhook: { id, token } | null }
    if (file && existsSync(file)) {
      const data = JSON.parse(readFileSync(file, 'utf8'));
      if (typeof data.identity === 'string') this.identity = data.identity;
      for (const [key, v] of Object.entries(data.channels ?? {})) {
        if (typeof v?.seed !== 'string' || !/^[0-9a-f]{64}$/.test(v.seed)) continue;
        const webhook = v.webhook && typeof v.webhook.id === 'string' && typeof v.webhook.token === 'string' ? { id: v.webhook.id, token: v.webhook.token } : null;
        this.channels.set(key, { seed: v.seed, webhook });
      }
    }
  }

  static open(dir, options) {
    mkdirSync(dir, { recursive: true, mode: 0o700 });
    return new BridgeStore(join(dir, 'bridges.json'), options);
  }

  static key(guildId, channelId) {
    if (!SNOWFLAKE.test(String(guildId)) || !SNOWFLAKE.test(String(channelId))) throw new Error('not a Discord id');
    return `${guildId}:${channelId}`;
  }

  /** The channel's seed (64 lowercase hex), made the first time it is asked for and the same ever after. */
  seedFor(guildId, channelId) {
    const key = BridgeStore.key(guildId, channelId);
    let entry = this.channels.get(key);
    if (!entry) {
      entry = { seed: Buffer.from(this.random(32)).toString('hex'), webhook: null };
      this.channels.set(key, entry);
      this.save();
    }
    return entry.seed;
  }

  webhook(guildId, channelId) {
    return this.channels.get(BridgeStore.key(guildId, channelId))?.webhook ?? null;
  }

  setWebhook(guildId, channelId, webhook) {
    const key = BridgeStore.key(guildId, channelId);
    const entry = this.channels.get(key) ?? { seed: Buffer.from(this.random(32)).toString('hex'), webhook: null };
    entry.webhook = webhook ? { id: String(webhook.id), token: String(webhook.token) } : null;
    this.channels.set(key, entry);
    this.save();
  }

  /** Every webhook id the bridge posts through: messages from them are never passed back to Ghost. */
  webhookIds() {
    return new Set([...this.channels.values()].map((v) => v.webhook?.id).filter(Boolean));
  }

  /** The bridge's key as PEM, made by [make] (and kept) the first time. */
  identityPem(make) {
    if (!this.identity) {
      this.identity = make();
      this.save();
    }
    return this.identity;
  }

  save() {
    if (!this.file) return;
    mkdirSync(dirname(this.file), { recursive: true, mode: 0o700 });
    const body = JSON.stringify({ version: 1, identity: this.identity, channels: Object.fromEntries(this.channels) }, null, 1);
    const tmp = `${this.file}.${process.pid}.tmp`;
    const fd = openSync(tmp, 'w', 0o600);
    try {
      writeSync(fd, body);
      fsyncSync(fd);
    } finally {
      closeSync(fd);
    }
    renameSync(tmp, this.file);
  }
}
