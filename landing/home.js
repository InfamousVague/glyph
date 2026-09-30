/*
 * ghostmarkdown.com's home page (index.html; docs/DESIGN.md §153): the ways to get the app, the recorder drawn at work,
 * the review's changes to keep or revert, the marks to try, and the page's themes. Plain script, no build: the site is
 * one directory the deploy tars whole (docs/LANDING.md).
 */
(function () {
  'use strict';

  /*
   * The stores. Null until a listing is live, and the button says "Coming soon"; set a listing's address here and it
   * is a link. Google Play is docs/store/PLAY_STORE.md's; the App Store is docs/store/APP_STORE.md's, waiting on voice
   * notes for iOS.
   */
  var STORES = {
    play: null, // 'https://play.google.com/store/apps/details?id=com.mattssoftware.glyph'
    appStore: null,
  };

  var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var $ = function (selector, root) {
    return (root || document).querySelector(selector);
  };
  var $$ = function (selector, root) {
    return Array.prototype.slice.call((root || document).querySelectorAll(selector));
  };

  // ---- the stores ------------------------------------------------------------------------------------------------

  $$('[data-store]').forEach(function (badge) {
    var url = STORES[badge.getAttribute('data-store')];
    if (!url) return;
    var link = document.createElement('a');
    link.className = badge.className;
    link.href = url;
    link.setAttribute('data-store', badge.getAttribute('data-store'));
    link.innerHTML = badge.innerHTML;
    var soon = link.querySelector('em');
    if (soon) soon.remove();
    badge.replaceWith(link);
  });

  // ---- the device in hand's way first ----------------------------------------------------------------------------

  var ua = navigator.userAgent;
  var ios = /iPhone|iPad|iPod/i.test(ua) || (navigator.maxTouchPoints > 1 && /Macintosh/.test(ua));
  var first = /Android/i.test(ua) ? 'android' : ios ? 'web' : /Macintosh|Mac OS X/.test(ua) ? 'mac' : null;
  if (first) {
    $('#' + first).setAttribute('data-first', '');
    var get = $('#hero-get');
    var word = $('#hero-get-word');
    if (first === 'android') {
      get.href = '/glyph.apk';
      get.setAttribute('download', '');
      word.textContent = 'Download for Android';
    } else if (first === 'mac') {
      get.href = '/glyph.dmg';
      get.setAttribute('download', '');
      word.textContent = 'Download for Mac';
    }
  }
  if (first === 'mac') $('#mac-note').hidden = false;

  // The version and size of what each button downloads, from the manifests the apps themselves update from.
  var size = function (bytes) {
    return Math.round(bytes / 1e6) + ' MB';
  };
  [
    ['apk.json', 'apk'],
    ['desktop.json', 'dmg'],
  ].forEach(function (pair) {
    fetch('/' + pair[0], { cache: 'no-store' })
      .then(function (r) {
        return r.ok ? r.json() : null;
      })
      .then(function (manifest) {
        if (!manifest || !manifest.version) return;
        var meta = $('[data-meta="' + pair[1] + '"]');
        if (meta) meta.textContent = manifest.version + ' · ' + size(manifest.bytes);
      })
      .catch(function () {
        return undefined;
      });
  });

  // ---- the recorder, drawn at work -------------------------------------------------------------------------------

  // What is said, and which of the page's lines it writes (index.html `#live-page`, in order).
  var hearing = [
    { said: 'Title: weekend trip', lines: [0] },
    { said: 'Heading, before we go', lines: [1] },
    { said: 'Remember to book the cabin', lines: [2] },
    { said: 'We need snacks, water, a charger and the good playlist', lines: [3, 4, 5, 6, 7] },
    { said: 'Important: leave by ten', lines: [8] },
  ];
  var page = $('#live-page');
  var said = $('#said');
  var clock = $('#live-clock');
  if (page && said && !reduced) {
    var lines = $$('.md', page);
    var timers = [];
    var seconds = 0;
    var running = false;
    var later = function (fn, ms) {
      timers.push(window.setTimeout(fn, ms));
    };
    var tick = function () {
      seconds += 1;
      clock.textContent = Math.floor(seconds / 60) + ':' + String(seconds % 60).padStart(2, '0');
      if (running) later(tick, 1000);
    };
    var play = function () {
      if (running) return;
      running = true;
      seconds = 0;
      clock.textContent = '0:00';
      lines.forEach(function (line) {
        line.hidden = true;
        line.classList.remove('arriving');
      });
      var at = 400;
      hearing.forEach(function (step) {
        later(function () {
          said.textContent = step.said;
        }, at);
        step.lines.forEach(function (index, n) {
          later(function () {
            var line = lines[index];
            line.hidden = false;
            line.classList.add('arriving');
          }, at + 1100 + n * 260);
        });
        at += 1100 + step.lines.length * 260 + 1300;
      });
      later(tick, 1000);
      later(function () {
        running = false;
        timers.forEach(window.clearTimeout);
        timers = [];
        play();
      }, at + 3200);
    };
    var stop = function () {
      running = false;
      timers.forEach(window.clearTimeout);
      timers = [];
    };
    // Only while it is on screen and the tab is in front: a page left open does not run the demo for nobody.
    var visible = true;
    var inView = false;
    var decide = function () {
      if (visible && inView) play();
      else stop();
    };
    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (entries) {
        inView = entries[0].isIntersecting;
        decide();
      }).observe(page);
    } else {
      inView = true;
      decide();
    }
    document.addEventListener('visibilitychange', function () {
      visible = document.visibilityState === 'visible';
      decide();
    });
  }

  // ---- the review's changes, to keep or revert -------------------------------------------------------------------

  var foot = $('#review-left');
  var changes = $$('[data-change]');
  var countLeft = function () {
    var left = changes.filter(function (change) {
      return !change.hasAttribute('data-settled');
    }).length;
    if (!foot) return;
    if (left) {
      foot.textContent = left === 1 ? 'One change left.' : left === 2 ? 'Two changes left.' : 'Three changes to keep or revert. Try them.';
      return;
    }
    foot.textContent = 'All settled. In the app, Undo puts the whole note back. ';
    var again = document.createElement('button');
    again.type = 'button';
    again.className = 'pill';
    again.textContent = 'Show them again';
    again.addEventListener('click', function () {
      changes.forEach(function (change) {
        change.removeAttribute('data-settled');
      });
      countLeft();
      var firstKeep = $('[data-keep]', changes[0]);
      if (firstKeep) firstKeep.focus();
    });
    foot.appendChild(again);
  };
  changes.forEach(function (change, index) {
    $$('button', change).forEach(function (button) {
      button.addEventListener('click', function () {
        change.setAttribute('data-settled', button.hasAttribute('data-keep') ? 'keep' : 'revert');
        countLeft();
        // The buttons pressed are gone: the keyboard goes on to the next change's Keep, or to what is left to say.
        var next = changes.slice(index + 1).concat(changes.slice(0, index)).find(function (other) {
          return !other.hasAttribute('data-settled');
        });
        var target = next ? $('[data-keep]', next) : $('button', foot);
        if (target) target.focus();
      });
    });
  });

  // ---- the marks -------------------------------------------------------------------------------------------------

  $$('.spoiler').forEach(function (spoiler) {
    spoiler.addEventListener('click', function () {
      var shown = spoiler.getAttribute('aria-pressed') === 'true';
      spoiler.setAttribute('aria-pressed', shown ? 'false' : 'true');
      spoiler.setAttribute('aria-label', shown ? 'A spoiler: tap to show it' : 'A spoiler, shown: tap to hide it');
    });
  });

  // A wave moves letter by letter, each a beat behind the one before; its words are still one word to a reader.
  $$('.fx-wave').forEach(function (wave) {
    var words = wave.textContent;
    wave.setAttribute('aria-label', words);
    wave.textContent = '';
    Array.prototype.forEach.call(words, function (letter, n) {
      var ch = document.createElement('span');
      ch.className = 'ch';
      ch.setAttribute('aria-hidden', 'true');
      ch.style.setProperty('--n', String(n));
      ch.textContent = letter === ' ' ? '\u00a0' : letter;
      wave.appendChild(ch);
    });
  });

  // ---- the page's theme ------------------------------------------------------------------------------------------

  var THEMES = { light: ['light'], dark: ['dark'], dawn: ['light', 'dawn'], boreal: ['dark', 'boreal'], ember: ['dark', 'ember'] };
  var root = document.documentElement;
  var swatches = $$('[data-theme-pick]');
  var current = function () {
    try {
      return localStorage.getItem('ghostmd-site-theme') || 'system';
    } catch (e) {
      return 'system';
    }
  };
  var show = function (pick) {
    swatches.forEach(function (swatch) {
      var on = swatch.getAttribute('data-theme-pick') === pick;
      swatch.setAttribute('aria-checked', on ? 'true' : 'false');
      swatch.tabIndex = on ? 0 : -1;
    });
  };
  var choose = function (pick) {
    var theme = THEMES[pick];
    root.removeAttribute('data-theme-preset');
    if (theme) {
      root.setAttribute('data-theme', theme[0]);
      if (theme[1]) root.setAttribute('data-theme-preset', theme[1]);
    } else {
      root.removeAttribute('data-theme');
    }
    try {
      if (theme) localStorage.setItem('ghostmd-site-theme', pick);
      else localStorage.removeItem('ghostmd-site-theme');
    } catch (e) {
      /* Kept for this visit only. */
    }
    show(pick);
  };
  show(current());
  swatches.forEach(function (swatch, index) {
    swatch.addEventListener('click', function () {
      choose(swatch.getAttribute('data-theme-pick'));
    });
    swatch.addEventListener('keydown', function (event) {
      var by = event.key === 'ArrowRight' || event.key === 'ArrowDown' ? 1 : event.key === 'ArrowLeft' || event.key === 'ArrowUp' ? -1 : 0;
      if (!by) return;
      event.preventDefault();
      var next = swatches[(index + by + swatches.length) % swatches.length];
      choose(next.getAttribute('data-theme-pick'));
      next.focus();
    });
  });
})();
