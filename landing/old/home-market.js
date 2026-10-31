/*
 * The home page's Market band (index.html #market; Matt, 2026-10-27: "also show the market page high on the list of
 * the website with the dedicated market page that opens plugins in the app"): a handful of plugins from market.json,
 * the listing market.html reads, each a card to its own page there, where Open in Ghost.md takes it into the app. The
 * featured first, as the Market shows them, then the meeting ones. "Open it in Ghost.md" opens the app's Market, and
 * goes to market.html when nothing took the link.
 */
(function () {
  'use strict';

  var PICKS = 8;
  var FIRST = ['google-meet', 'zoom', 'discord', 'slack'];
  /* How long the page waits for the app to take a link before it goes to the site's Market instead. */
  var WAIT = 1500;

  function escape(text) {
    return String(text == null ? '' : text).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function glyph(listing, name) {
    var shapes = (listing.icons && listing.icons[name]) || [];
    return (
      '<svg class="i" viewBox="0 0 24 24" aria-hidden="true">' +
      shapes.map(function (d) { return '<path d="' + escape(d) + '"/>'; }).join('') +
      '</svg>'
    );
  }

  function tile(listing, plugin) {
    var c = plugin.colours || ['#555', '#888'];
    var inner = plugin.mark
      ? '<span class="mp-mark" style="--mark: url(\'../brands/' + escape(plugin.mark) + '.svg\')" aria-hidden="true"></span>'
      : glyph(listing, plugin.icon);
    return '<span class="mp-tile" style="--deep: ' + escape(c[0]) + '; --bright: ' + escape(c[1]) + '">' + inner + '</span>';
  }

  function render(listing) {
    var list = document.getElementById('market-picks');
    if (!list || !listing || !listing.plugins) return;
    var byId = {};
    listing.plugins.forEach(function (p) { byId[p.id] = p; });
    var order = [].concat(listing.featured || [], FIRST, listing.plugins.map(function (p) { return p.id; }));
    var seen = {};
    var picks = [];
    order.forEach(function (id) {
      if (picks.length < PICKS && byId[id] && !seen[id]) {
        seen[id] = true;
        picks.push(byId[id]);
      }
    });
    list.innerHTML = picks
      .map(function (p) {
        return (
          '<li><a class="mp-card" href="../market.html#plugin/' + encodeURIComponent(p.id) + '">' +
          tile(listing, p) +
          '<span class="mp-words"><b>' + escape(p.name) + '</b><span>' + escape(p.line) + '</span>' +
          '<small>' + escape(p.reach || '') + '</small></span></a></li>'
        );
      })
      .join('');
    var count = document.getElementById('market-count');
    if (count) {
      var n = function (k) { return (listing[k] || []).length; };
      count.innerHTML =
        n('plugins') + ' plugins, ' + n('themes') + ' themes, ' + n('fonts') + ' fonts and ' + n('iconPacks') +
        ' icon packs. <a href="../market.html">See them all</a>.';
    }
  }

  function openApp(event) {
    var link = event.currentTarget.getAttribute('href');
    event.preventDefault();
    var left = false;
    function away() { left = true; }
    window.addEventListener('pagehide', away);
    window.addEventListener('blur', away);
    window.location.href = link;
    setTimeout(function () {
      window.removeEventListener('pagehide', away);
      window.removeEventListener('blur', away);
      // Still here and in front: nothing took the link, so the site's own Market.
      if (!left && document.visibilityState === 'visible' && document.hasFocus()) window.location.href = '../market.html';
    }, WAIT);
  }

  var open = document.getElementById('market-open-app');
  if (open) open.addEventListener('click', openApp);

  fetch('../market.json')
    .then(function (r) { return r.ok ? r.json() : null; })
    .then(render)
    .catch(function () {
      /* Without the listing the band keeps its two ways in. */
    });
})();
