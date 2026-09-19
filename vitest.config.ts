import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  // The build stamps vite.config.ts defines; tests get fixed stand-ins.
  define: {
    __GLYPH_BUILD__: JSON.stringify('20260101000000'),
    __GLYPH_VERSION__: JSON.stringify('0.0.0-test'),
    __GLYPH_SOURCE__: JSON.stringify('test-source'),
    __GLYPH_STAGING__: JSON.stringify(false),
  },
  test: {
    environment: 'jsdom',
    // The test report's parsers are tested with the page (scripts/testReport).
    include: ['src/**/*.test.{ts,tsx}', 'mcp/**/*.test.ts', 'scripts/**/*.test.mjs'],
    setupFiles: ['src/test/setup.ts'],
    css: false,
  },
});
