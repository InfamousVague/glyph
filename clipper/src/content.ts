import { ClipRefused, extract, peek, type ClipMode, type Extract, type Peek } from './core/page.ts';

/**
 * The clipper in a page: put there by the background only when the person asks for a clip (`chrome.scripting`, in
 * the extension's own world, not the page's), and asked three things. It reads; it never changes the page, sends
 * nothing anywhere itself, and fetches a picture only as the page itself could, from where the page has it.
 */

export interface PageClipper {
  peek(): Peek;
  extract(mode: ClipMode): { ok: true; extract: Extract } | { ok: false; error: string };
  fetchPicture(url: string, limit: number): Promise<{ type: string; base64: string } | 'too-big' | null>;
}

function base64Of(bytes: Uint8Array): string {
  let text = '';
  for (let i = 0; i < bytes.length; i += 0x8000) text += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(text);
}

const clipper: PageClipper = {
  peek: () => peek(window),
  extract(mode) {
    try {
      return { ok: true, extract: extract(window, mode) };
    } catch (failure) {
      return { ok: false, error: failure instanceof ClipRefused ? failure.message : 'This page could not be read.' };
    }
  },
  async fetchPicture(url, limit) {
    try {
      const response = await fetch(url, { credentials: 'same-origin', referrerPolicy: 'strict-origin-when-cross-origin' });
      if (!response.ok) return null;
      const type = response.headers.get('content-type')?.split(';')[0]?.trim() ?? '';
      if (type && !type.startsWith('image/')) return null;
      if (Number(response.headers.get('content-length') ?? 0) > limit) return 'too-big';
      const bytes = new Uint8Array(await response.arrayBuffer());
      if (bytes.length > limit) return 'too-big';
      return { type: type || 'image/*', base64: base64Of(bytes) };
    } catch {
      return null;
    }
  },
};

(globalThis as { __ghostClipper?: PageClipper }).__ghostClipper = clipper;
