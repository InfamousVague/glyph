import { defineConfig } from 'vitest/config';

export default defineConfig({
  // The clipper imports the web app's own account, crypto and sync modules from ../tauri, as mcp/ does: outside
  // this folder, which Vite serves only when told it may.
  server: { fs: { allow: ['..'] } },
  // Never the live service: every test that talks to one is handed the fake service's fetcher or a local glyph-api.
  define: { 'import.meta.env.VITE_GLYPH_API': JSON.stringify(process.env.VITE_GLYPH_API ?? 'http://127.0.0.1:1/api') },
  test: {
    environment: 'jsdom',
    include: ['test/**/*.test.ts', 'e2e/**/*.e2e.test.ts'],
    testTimeout: 30_000,
  },
});
