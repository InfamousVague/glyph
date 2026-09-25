import { ensureWebCrypto } from './webcrypto.ts';
import { hostedApp } from './hosted.ts';
import { VERSION } from './server.ts';

/**
 * The hosted MCP server's entry point (docs/MCP.md, "Hosted"): `glyph-mcp.service` on the box runs this on loopback,
 * and glyph-api proxies /glyph/api/mcp to it.
 *
 *   GLYPH_MCP_BIND     where to listen, `127.0.0.1:18820` (an IPv6 host in brackets, `[::1]:18820`)
 *   GLYPH_MCP_ISSUER   the server's own URL as Claude sees it, `https://attack.fm/glyph/api/mcp`
 *   GLYPH_API          the sync service this process talks to, `http://127.0.0.1:8796/glyph/api`
 *   GLYPH_API_PUBLIC   the sync service as a person's browser reaches it, `https://attack.fm/glyph/api`
 */

const bind = process.env.GLYPH_MCP_BIND || '127.0.0.1:18820';
ensureWebCrypto();

const issuer = process.env.GLYPH_MCP_ISSUER || 'https://attack.fm/glyph/api/mcp';
const api = process.env.GLYPH_API || 'http://127.0.0.1:8796/glyph/api';
const apiPublic = process.env.GLYPH_API_PUBLIC || 'https://attack.fm/glyph/api';

// The port is after the LAST colon, so an IPv6 host keeps its own; its brackets are only for the reader.
const cut = bind.lastIndexOf(':');
const host = (cut < 0 ? bind : bind.slice(0, cut)).replace(/^\[(.*)\]$/, '$1');
const port = cut < 0 ? '18820' : bind.slice(cut + 1);
const { app, sweep } = hostedApp({ issuer, api, apiPublic });
// What has run out goes every ten minutes, so a session nobody uses does not keep its key a day longer than it should.
setInterval(sweep, 10 * 60 * 1000).unref();
app.listen(Number(port), host, () => {
  process.stderr.write(`glyph-mcp ${VERSION}: hosted at ${issuer}, listening on ${bind}, notes from ${api}\n`);
});
