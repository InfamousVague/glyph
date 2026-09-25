import { createServer } from 'node:net';

/**
 * A loopback port nobody is using, for a test that has to name its server's address before the server exists - the
 * hosted server is made with its own URL as the OAuth issuer, so the port cannot be the one it is handed at bind.
 *
 * Asked of the system (listen on 0, read the port, let it go) rather than fixed: a fixed port meets the leftover child
 * of a stopped run, or a second run beside it, and fails as a server that "did not come up". The port is free when
 * this answers, and taken again a moment later by the caller; nothing else on a test machine races for loopback ports
 * in that moment. For the tests only (hosted.test.ts, mcp.e2e.test.ts).
 */
export function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const probe = createServer();
    probe.once('error', reject);
    probe.listen(0, '127.0.0.1', () => {
      const { port } = probe.address() as { port: number };
      probe.close(() => resolve(port));
    });
  });
}
