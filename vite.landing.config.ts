import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

/**
 * The app's own components for ghostmarkdown.com (src/landing/parts.tsx; docs/LANDING.md, docs/DESIGN.md §154):
 * built into landing/parts/ as one script and one stylesheet with fixed names, which landing/index.html loads, so the
 * site stays one directory the deploy tars whole. `npm run build:landing`, and commit what it writes.
 */
export default defineConfig({
  plugins: [react()],
  publicDir: false,
  base: './',
  build: {
    outDir: 'landing/parts',
    emptyOutDir: true,
    cssCodeSplit: false,
    sourcemap: false,
    rollupOptions: {
      input: 'src/landing/parts.tsx',
      output: {
        entryFileNames: 'parts.js',
        chunkFileNames: 'parts-[name].js',
        assetFileNames: 'parts[extname]',
      },
    },
  },
});
