import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { Tape } from './Tape.tsx';

/**
 * The app's own components on ghostmarkdown.com (landing/index.html; docs/DESIGN.md §154). Matt: "use only real
 * components from the app for things like the tape cassette". Where the site shows a piece of the app that moves, it
 * is the app's code, built for the site (`npm run build:landing`, vite.landing.config.ts, into landing/parts/), not a
 * drawing of it; what does not move is the app's own screens (landing/shots/).
 *
 * Each piece is mounted into an element that names it, `data-part`, and draws in the site's ink, which site.css hands
 * the app's names for (`--app-ink`, `--app-paper`), so it turns with the site's theme as it does with the app's.
 */

for (const host of Array.from(document.querySelectorAll<HTMLElement>('[data-part="tape"]'))) {
  const title = host.dataset.title ?? 'Standup';
  const lengthMs = Number(host.dataset.length ?? 40_000);
  createRoot(host).render(
    <StrictMode>
      <Tape title={title} lengthMs={lengthMs} />
    </StrictMode>,
  );
}
