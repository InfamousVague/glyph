import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  // The build stamps vite.config.ts defines; tests get fixed stand-ins.
  define: {
    __GLYPH_BUILD__: JSON.stringify('20260101000000'),
    __GLYPH_VERSION__: JSON.stringify('0.0.0-test'),
  },
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.{ts,tsx}'],
    setupFiles: ['src/test/setup.ts'],
    css: false,
  },
});
