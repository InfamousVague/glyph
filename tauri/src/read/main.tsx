import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
// The app's own look, token for token (src/main.tsx), so a shared note reads here as it does in Ghost.md.
import '@glacier/tokens/css/fonts.css';
import '@fontsource-variable/inter/opsz.css';
import '@glacier/tokens/css/tokens.css';
import '@glacier/react/styles.css';
import '../app/app.css';
// The wash on each kit icon's body: made by art/iconWash.test.ts from the icons in use.
import '../app/iconWash.css';
import '../app/art/wisp.css';
import '../app/ink.css';
// The note's face: a shared note is drawn in the app's default, Maple Mono (typefaces.css).
import '../app/typefaces.css';
import '../app/editor/codeThemes.css';
import { readJoinLink } from '../app/core/orgs/joinLinks.ts';
import { JoinPage } from './JoinPage.tsx';
import { Reader } from './Reader.tsx';

// An invite link is the reader page with `#join=<code>` (core/orgs/joinLinks.ts): the invitation, not a shared note.
const join = location.hash.startsWith('#join=') ? readJoinLink(location.hash) : null;

createRoot(document.getElementById('root')!).render(<StrictMode>{join ? <JoinPage code={join} /> : <Reader />}</StrictMode>);
