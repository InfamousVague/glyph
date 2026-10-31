import { copyFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { defineConfig, type Plugin } from 'vite';
import react from '@vitejs/plugin-react';

/**
 * ghost-publish's build (publish/README.md): the CLI (publish/src/cli.ts) and everything it imports - the reader's
 * Rendered.tsx, the app's pure modules, React's server renderer, lezer - bundled into ONE file for Node,
 * publish/dist/ghost-publish.js, with no dependencies to install beside it, so the git plugin can vendor the folder
 * into a library's repository and a workflow can run it with Node alone. The stylesheets and the fonts they name are
 * emitted to dist/assets/, which the build copies into every site it writes, with the search script beside them.
 *
 * From tauri/: `vite build --config publish/vite.config.ts`. The CSS modules the components use are compiled as the
 * app's are, so a published page's class names are the reader's own, hashed.
 */

const root = import.meta.dirname;

/** The client's search script, copied as it is: it is served to browsers, never bundled for Node. */
function searchScript(): Plugin {
  return {
    name: 'ghost-publish-search-script',
    apply: 'build',
    closeBundle() {
      mkdirSync(join(root, 'dist', 'assets'), { recursive: true });
      copyFileSync(join(root, 'client', 'search.js'), join(root, 'dist', 'assets', 'search.js'));
    },
  };
}

export default defineConfig({
  root,
  plugins: [react(), searchScript()],
  define: {
    __GLYPH_BUILD__: JSON.stringify('publish'),
    __GLYPH_VERSION__: JSON.stringify('0.0.0'),
    __GLYPH_SOURCE__: JSON.stringify(''),
    __GLYPH_STAGING__: JSON.stringify(false),
  },
  resolve: {
    // One React: the app's modules under ../src resolve it from tauri/node_modules, and so must everything here.
    dedupe: ['react', 'react-dom'],
  },
  css: {
    modules: {
      // Stable class names across builds, so two sites built a day apart share a look and a diff of their HTML is honest.
      generateScopedName: '_[local]_[hash:base64:5]',
    },
  },
  ssr: {
    // Everything into the one file: a vendored copy has no node_modules.
    noExternal: true,
    target: 'node',
  },
  build: {
    ssr: join(root, 'src', 'cli.ts'),
    outDir: join(root, 'dist'),
    emptyOutDir: true,
    ssrEmitAssets: true,
    cssCodeSplit: false,
    sourcemap: false,
    minify: false,
    target: 'node20',
    rollupOptions: {
      output: { entryFileNames: 'ghost-publish.js', format: 'es', inlineDynamicImports: true },
    },
  },
  clearScreen: false,
});
