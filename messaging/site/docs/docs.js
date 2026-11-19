// gogho.st/docs: the theme switch, the sidebar on a phone, the outline that follows the page, and search over
// search.json (tool/build-docs.mjs writes it). Nothing is sent anywhere; the choice of theme stays in this browser.
(() => {
  const root = document.documentElement;

  // Light or dark: the reader's own setting until they choose here.
  document.querySelector('.theme-btn')?.addEventListener('click', () => {
    const dark = root.dataset.theme ? root.dataset.theme === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
    root.dataset.theme = dark ? 'light' : 'dark';
    try { localStorage.setItem('docs-theme', root.dataset.theme); } catch (_) {}
  });

  // The list of pages, as a drawer on a narrow screen.
  const menu = document.querySelector('.menu-btn');
  menu?.addEventListener('click', () => {
    const open = document.body.classList.toggle('nav-open');
    menu.setAttribute('aria-expanded', String(open));
    // Opened, at the page being read.
    if (open) showCurrent();
  });
  document.querySelectorAll('.sidebar a').forEach((a) => a.addEventListener('click', () => document.body.classList.remove('nav-open')));
  // The page being read, shown in the list: the list scrolled, never the page (scrollIntoView moved the whole page
  // sideways on a phone, where the list waits off to the left).
  function showCurrent() {
    const side = document.querySelector('.sidebar');
    const current = side?.querySelector('[aria-current]');
    if (side && current) side.scrollTop = Math.max(0, current.offsetTop - side.clientHeight / 2);
  }
  showCurrent();

  // On this page: the part being read, marked.
  const links = [...document.querySelectorAll('.toc a')];
  if (links.length && 'IntersectionObserver' in window) {
    const heads = links.map((a) => document.getElementById(a.hash.slice(1))).filter(Boolean);
    const seen = new Set();
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => (e.isIntersecting ? seen.add(e.target) : seen.delete(e.target)));
      const top = heads.find((h) => seen.has(h)) ?? null;
      if (top) links.forEach((a) => a.classList.toggle('on', a.hash === `#${top.id}`));
    }, { rootMargin: '-15% 0px -70% 0px' });
    heads.forEach((h) => io.observe(h));
  }

  // Search: every page's words, matched as they are typed; Enter opens the first, arrows move between them.
  const input = document.getElementById('search');
  const box = document.getElementById('results');
  if (!input || !box) return;
  let index = null;
  let picked = 0;
  const load = () => index ?? (index = fetch('/docs/search.json').then((r) => r.json()).catch(() => []));
  const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
  const mark = (s, words) => words.reduce((t, w) => t.replace(new RegExp(`(${w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})`, 'gi'), '<mark>$1</mark>'), esc(s));
  function excerpt(text, words) {
    const at = words.map((w) => text.toLowerCase().indexOf(w)).filter((i) => i >= 0).sort((a, b) => a - b)[0] ?? 0;
    const from = Math.max(0, at - 40);
    return (from ? '…' : '') + text.slice(from, from + 120) + '…';
  }
  async function run() {
    const q = input.value.trim().toLowerCase();
    if (!q) { box.hidden = true; return; }
    const words = q.split(/\s+/).filter(Boolean);
    const all = await load();
    const scored = all
      .map((p) => {
        const hay = `${p.t} ${p.d} ${p.x}`.toLowerCase();
        if (!words.every((w) => hay.includes(w))) return null;
        let score = 0;
        for (const w of words) score += (p.t.toLowerCase().includes(w) ? 10 : 0) + (p.d.toLowerCase().includes(w) ? 4 : 0) + (p.h.some((h) => h[1].toLowerCase().includes(w)) ? 3 : 0);
        const head = p.h.find((h) => words.some((w) => h[1].toLowerCase().includes(w)));
        return { p, score, head };
      })
      .filter(Boolean)
      .sort((a, b) => b.score - a.score)
      .slice(0, 8);
    picked = 0;
    box.innerHTML = scored.length
      ? scored.map(({ p, head }, i) => `<a role="option" href="${p.u}${head ? `#${head[0]}` : ''}" aria-selected="${i === 0}"><b>${mark(p.t, words)}</b>${head ? ` › ${mark(head[1], words)}` : ''}<small>${esc(p.s)} · ${mark(excerpt(p.x, words), words)}</small></a>`).join('')
      : '<div class="none">Nothing found. Try another word.</div>';
    box.hidden = false;
  }
  input.addEventListener('input', run);
  input.addEventListener('focus', () => { load(); if (input.value) run(); });
  input.addEventListener('keydown', (e) => {
    const items = [...box.querySelectorAll('a')];
    if (e.key === 'Escape') { box.hidden = true; input.blur(); return; }
    if (!items.length) return;
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      picked = (picked + (e.key === 'ArrowDown' ? 1 : items.length - 1)) % items.length;
      items.forEach((a, i) => a.setAttribute('aria-selected', String(i === picked)));
      items[picked].scrollIntoView({ block: 'nearest' });
    } else if (e.key === 'Enter') {
      e.preventDefault();
      location.href = items[picked].href;
    }
  });
  document.addEventListener('click', (e) => { if (!e.target.closest('.search')) box.hidden = true; });
  document.addEventListener('keydown', (e) => {
    if (e.key === '/' && document.activeElement !== input && !/input|textarea/i.test(document.activeElement?.tagName ?? '')) { e.preventDefault(); input.focus(); }
  });
})();
