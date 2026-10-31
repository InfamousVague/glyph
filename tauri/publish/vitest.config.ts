import { join } from 'node:path';
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

/**
 * ghost-publish's tests (publish/test): Node, not jsdom, since the publisher renders to strings and reads folders.
 * From tauri/: `vitest run --config publish/vitest.config.ts`. The app's own suite (vitest.config.ts) includes only
 * src/, so these run apart from it and never slow a deploy's test step.
 */
export default defineConfig({
  root: join(import.meta.dirname, '..'),
  plugins: [react()],
  define: {
    __GLYPH_BUILD__: JSON.stringify('test'),
    __GLYPH_VERSION__: JSON.stringify('0.0.0-test'),
    __GLYPH_SOURCE__: JSON.stringify(''),
    __GLYPH_STAGING__: JSON.stringify(false),
  },
  css: { modules: { generateScopedName: '_[local]_[hash:base64:5]' } },
  test: {
    environment: 'node',
    include: ['publish/test/**/*.test.{ts,tsx}'],
    css: { include: [/\.module\.css$/] },
    testTimeout: 30000,
  },
});
