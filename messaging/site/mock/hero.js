/* The hero's conversation (site-src/hero3d/views/thread.html, the phone's outer screen), played in order across its
   layers. Needs mock.js (window.GM) first.

   It is a short scene (Matt, 2026-11-27: "make it reply then animate in the next message and the reactions"). As it
   opens, the conversation ends on Maya's "Bring the projector cable if you still have it", with the quick replies
   under it. Then:
     - a reply is typed into the composer and sent: it rises in UNDER what it answers (never above it), the quick
       replies go, your laugh lands on her message and the receipt under yours says Sent;
     - it is delivered; her next message comes; her heart lands on your reply; it is read.
   site/hero3d.js, whose clock everything on the phone keeps, says when: it sends this pane `h3:cue` events, with
   `play` (type the reply and send it), `finish` (the scene's end at once, for a moment held still) and `reset` (as it
   opened, while the screen is dark). Someone may also do it themself: what they type and send, or a quick reply they
   tap, is the reply, and the rest follows; a bubble double-tapped has its reaction bounce and be theirs or not. */
(() => {
  'use strict';
  const GM = window.GM;
  if (!GM) return;
  const REPLY = 'Found the cable!';
  const emojiOnly = (s) => /^(\p{Extended_Pictographic}|\p{Emoji_Modifier}|️|‍|\s)+$/u.test(s);

  function setUp(root) {
    if (root.__hero) return; root.__hero = 1;
    const q = (name) => root.querySelector(`[data-mock="${name}"]`);
    const reply = q('x-out2'), ticks = q('x-ticks'), heart = q('x-heart'), laugh = q('x-laugh'), next = q('x-emoji'), chips = q('x-chips'), compose = q('x-compose');
    if (!reply || !compose) return;
    const form = compose.querySelector('.gm-composer'), input = form.querySelector('.gm-composer__input');
    const msg = reply.querySelector('.gm-msg'), meta = ticks && ticks.querySelector('.gm-meta');
    const came = next && next.querySelector('.gm-msg'), row = chips && chips.querySelector('.gm-chips');
    const react = (box) => box && box.querySelector('.gm-react');
    let state = 'open', run = 0, steps = [];
    const clear = () => { steps.forEach(clearTimeout); steps = []; };
    const later = (fn, ms) => steps.push(setTimeout(fn, ms));

    // The receipt under your reply: words, one tick or two, read or not.
    function receipt(words, icon, read, now) {
      if (!meta) return;
      const line = meta.querySelector('.hero-state'), svg = meta.querySelector('.gm-ticks');
      const set = () => {
        line.textContent = words;
        svg.querySelector('use').setAttribute('href', '/mock/icons.svg#' + icon);
        svg.classList.toggle('is-read', !!read);
        line.classList.remove('is-fading');
      };
      if (now || meta.classList.contains('is-away')) { set(); meta.classList.remove('is-away'); return; }
      line.classList.add('is-fading');
      later(set, 180);
    }
    const arrive = (el, now) => { el.classList.remove('is-away', 'is-new'); if (!now) { el.offsetWidth; el.classList.add('is-new'); } };
    const land = (em, now) => { if (!em) return; em.classList.remove('is-gone'); if (!now) GM.pop(em); };

    // As the scene opens: nothing sent yet.
    function reset() {
      clear(); run++;
      state = 'open';
      msg.classList.remove('is-new'); msg.classList.add('is-away');
      if (came) { came.classList.remove('is-new'); came.classList.add('is-away'); }
      if (meta) meta.classList.add('is-away');
      for (const em of [react(heart), react(laugh)]) if (em) { em.classList.add('is-gone'); em.classList.remove('is-mine', 'is-pop'); }
      if (row) row.classList.remove('is-away');
      input.value = ''; input.dispatchEvent(new Event('input'));
    }

    // The reply is sent, and the rest follows: all at once where `now` is set.
    function sent(text, now) {
      clear(); run++;
      state = 'sent';
      msg.innerHTML = emojiOnly(text) ? '<div class="gm-jumbo"></div>' : '<div class="gm-bubble"></div>';
      msg.firstElementChild.textContent = text;
      arrive(msg, now);
      if (row) row.classList.add('is-away');
      receipt('Sent · now', 'check', false, true);
      const then = (fn, ms) => (now ? fn() : later(fn, ms));
      then(() => land(react(laugh), now), 380);
      then(() => receipt('Delivered · now', 'check-check', false, now), 850);
      then(() => came && arrive(came, now), 1350);
      then(() => land(react(heart), now), 1950);
      then(() => receipt('Read · now', 'check-check', true, now), 2500);
    }
    form.addEventListener('gm:send', (e) => sent(e.detail.text, false));

    // Typed into the composer, then sent. Given up if the scene has moved on meanwhile.
    async function say(text) {
      if (state !== 'open') return;
      state = 'typing';
      const mine = ++run;
      input.value = ''; input.dispatchEvent(new Event('input'));
      for (const ch of text) {
        if (run !== mine) return;
        input.value += ch; input.dispatchEvent(new Event('input'));
        await GM.sleep(42 * (ch === ' ' ? 1.6 : 0.6 + Math.random() * 0.8));
      }
      await GM.sleep(320);
      if (run !== mine) return;
      // Sending it is the form's own doing (mock.js), which says gm:send; `sent` above takes it from there.
      if (form.requestSubmit) form.requestSubmit(); else form.dispatchEvent(new Event('submit', { cancelable: true }));
      if (run === mine && state === 'typing') state = 'open';
    }

    root.addEventListener('h3:cue', (e) => {
      if (e.detail === 'reset') reset();
      else if (e.detail === 'finish') { if (state !== 'sent') sent(REPLY, true); }
      else if (e.detail === 'play') { if (GM.still.matches) sent(REPLY, true); else say(REPLY); }
    });

    // A quick reply: typed in, then sent.
    if (chips) chips.addEventListener('click', (e) => {
      const chip = e.target.closest('.gm-chip');
      if (!chip || state !== 'open') return;
      GM.pop(chip);
      say(chip.textContent.trim());
    });

    // A double tap: the reaction that is that message's layer, not a new row inside a box too small for it.
    root.addEventListener('dblclick', (e) => {
      const b = e.target.closest && e.target.closest('.gm-bubble, .gm-jumbo');
      if (!b || !root.contains(b)) return;
      e.stopPropagation(); e.preventDefault();
      const layer = b.closest('[data-mock]').dataset.mock;
      const em = react(layer === 'x-in' ? laugh : layer === 'x-out2' ? heart : null);
      if (!em) return;
      em.classList.remove('is-gone');
      em.classList.toggle('is-mine');
      GM.pop(em);
    }, true);
  }

  function wireHero(doc = document) {
    for (const c of doc.querySelectorAll('[data-mock="x-compose"]')) {
      const root = c.closest('.stack, [data-hero]');
      if (root) setUp(root);
    }
  }
  window.GM.hero = wireHero;
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => wireHero());
  else wireHero();
})();
