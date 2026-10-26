import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
// The app's own look, as the reader page has it (src/read/main.tsx), so the docs read as a note does in Ghost.md.
import '@glacier/tokens/css/fonts.css';
import '@fontsource-variable/inter/opsz.css';
import '@glacier/tokens/css/tokens.css';
import '@glacier/react/styles.css';
import '../app/app.css';
import '../app/iconWash.css';
import '../app/art/wisp.css';
import '../app/ink.css';
import '../app/typefaces.css';
import '../app/editor/codeThemes.css';
import './docs.css';
import { Docs } from './Docs.tsx';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <Docs />
  </StrictMode>,
);
