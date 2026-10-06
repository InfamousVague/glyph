/*
 * ghostmarkdown.com's home page (index.html; docs/DESIGN.md §153, §154): the ways to get the app, the connector's
 * address to copy, and the site's page to choose. Plain script, no build; the app's own moving parts are parts/.
 */
(function () {
  'use strict';

  /*
   * The stores. Null until a listing is live, and the button says "Coming soon"; set a listing's address here and it
   * is a link. Google Play is docs/store/PLAY_STORE.md's; the App Store waits on voice notes for iOS
   * (docs/store/APP_STORE.md).
   */
  var STORES = {
    play: null, // 'https://play.google.com/store/apps/details?id=com.mattssoftware.glyph'
    appStore: null,
  };

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
  var first = /Android/i.test(ua) ? 'android' : ios ? 'web' : /Macintosh|Mac OS X/.test(ua) ? 'mac' : /Windows NT/.test(ua) ? 'windows' : null;
  if (first) {
    var way = $('#' + first);
    way.setAttribute('data-first', '');
    // First in the page, not only drawn first, so the keyboard and a screen reader meet it first as well.
    way.parentNode.insertBefore(way, way.parentNode.firstChild);
    var get = $('#hero-get');
    var word = $('#hero-get-word');
    var gets = { android: ['/glyph.apk', 'Download for Android'], mac: ['/glyph.dmg', 'Download for Mac'], windows: ['/glyph-setup.exe', 'Download for Windows'] };
    if (gets[first]) {
      get.href = gets[first][0];
      get.setAttribute('download', '');
      word.textContent = gets[first][1];
    }
  }
  // The Open Anyway note is shown only while the Mac app on offer is not notarised (desktop.json says), below: a
  // notarised one opens on the first try, and the note would only tell a person to do something they need not.

  // The version and size of what each button downloads, from the manifests the apps themselves update from.
  [
    ['apk.json', 'apk'],
    ['desktop.json', 'dmg'],
    ['windows.json', 'exe'],
  ].forEach(function (pair) {
    fetch('/' + pair[0], { cache: 'no-store' })
      .then(function (r) {
        return r.ok ? r.json() : null;
      })
      .then(function (manifest) {
        if (!manifest || !manifest.version) return;
        var meta = $('[data-meta="' + pair[1] + '"]');
        if (meta) meta.textContent = manifest.version + ' · ' + Math.round(manifest.bytes / 1e6) + ' MB';
        if (pair[1] === 'dmg' && first === 'mac' && manifest.notarized === false) $('#mac-note').hidden = false;
        // And the Run anyway note only while the Windows app on offer is unsigned (windows.json says).
        if (pair[1] === 'exe' && first === 'windows' && manifest.signed === false) $('#windows-note').hidden = false;
      })
      .catch(function () {
        return undefined;
      });
  });

  // ---- copying the connector's address ---------------------------------------------------------------------------

  $$('[data-copy]').forEach(function (button) {
    button.addEventListener('click', function () {
      var text = ($(button.getAttribute('data-copy')) || {}).textContent || '';
      var said = function (words) {
        button.textContent = words;
        window.setTimeout(function () {
          button.textContent = 'Copy';
        }, 1600);
      };
      if (!navigator.clipboard) return said('Select it to copy');
      navigator.clipboard.writeText(text.trim()).then(
        function () {
          said('Copied');
        },
        function () {
          said('Select it to copy');
        },
      );
    });
  });

  // ---- the site's page -------------------------------------------------------------------------------------------

  var THEMES = { light: ['light'], dark: ['dark'], dawn: ['light', 'dawn'], boreal: ['dark', 'boreal'], ember: ['dark', 'ember'] };
  var root = document.documentElement;
  var swatches = $$('[data-theme-pick]');
  var bar = $('meta[name="theme-color"]');
  var saved = function () {
    try {
      return localStorage.getItem('ghostmd-site-theme') || 'system';
    } catch (e) {
      return 'system';
    }
  };
  /** The browser's own bar in the page's paper, whichever page is on. */
  var paintBar = function () {
    if (bar) bar.setAttribute('content', getComputedStyle(document.body).backgroundColor);
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
    paintBar();
  };
  show(saved());
  paintBar();
  if (window.matchMedia) window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', paintBar);
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
