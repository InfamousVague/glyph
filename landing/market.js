/*
 * ghostmarkdown.com's Market (market.html; Matt, 2026-10-26: "add a browsable marketplace listed under the plugins
 * section on the website that deeplinks to the app"). Plain script, no build, and no server but this site's own
 * files: it reads market.json, which the app's own Market is listed into (lib/market/market_listing.dart), and draws
 * its shelves as the app does - All, Plugins, Themes, Fonts - with a search across them and the plugins' categories.
 *
 * Each thing has a page of its own at its own anchor (#plugin/notion, #theme/dusk, #font/lora), opened over the
 * shelves, and its Open in Ghost.md follows the thing's link into the app (`ghostmd://market/<kind>/<id>`). A browser
 * gives no word on whether anything answered a link, so the page watches for the app taking over instead: if after a
 * moment and a half the page is still here, in front and in focus, it says Ghost.md may not be on this device yet and
 * offers the download (the home page's #download).
 */
(function () {
  'use strict';

  /* How long after Open in Ghost.md the page waits for the app before it offers the download. */
  var WAIT = 1500;

  var $ = function (selector, root) {
    return (root || document).querySelector(selector);
  };

  /*
   * The one door out to the app. A page's link to the app is the browser's to follow; kept here, on window, so a
   * check of the page's own (its pictures, build/feature-shots/web-market/) can stand in for it and follow nothing.
   */
  var market = (window.ghostMarket = window.ghostMarket || {});
  market.launch =
    market.launch ||
    function (link) {
      window.location.href = link;
    };

  var listing = null;
  var state = { shelf: 'all', query: '', category: null };

  // ---- drawing ---------------------------------------------------------------------------------------------------

  function escape(text) {
    return String(text == null ? '' : text).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  /* A Lucide glyph as the app draws it: its shapes on the 24 grid, in the text's own ink. */
  function icon(name, extra) {
    var shapes = (listing && listing.icons[name]) || [];
    var paths = shapes
      .map(function (d) {
        return '<path d="' + escape(d) + '"/>';
      })
      .join('');
    return '<svg class="i' + (extra ? ' ' + extra : '') + '" viewBox="0 0 24 24" aria-hidden="true">' + paths + '</svg>';
  }

  /* A plugin's mark on its tile: the brand's own file where the site ships one (brands/), else its Lucide icon. */
  function mark(plugin) {
    if (plugin.mark) return '<span class="mk-mark" style="--mark: url(\'brands/' + escape(plugin.mark) + '.svg\')" aria-hidden="true"></span>';
    return icon(plugin.icon, 'mk-glyph');
  }

  function tile(plugin, size) {
    var c = plugin.colours;
    return '<span class="mk-tile mk-tile-' + size + '" style="--deep: ' + c[0] + '; --bright: ' + c[1] + '">' + mark(plugin) + '</span>';
  }

  function categoryLabel(id) {
    var found = (listing.categories || []).filter(function (c) {
      return c.id === id;
    })[0];
    return found ? found.label : 'Plugin';
  }

  /* Where it works, in the app's own words ("Mobile · Desktop", "Android only"), with a glyph for each side. */
  function reach(item) {
    var p = item.platforms;
    var phones = p.android || p.iphone;
    return (
      '<span class="mk-reach">' +
      (phones ? icon('smartphone') : '') +
      (p.mac ? icon('laptop') : '') +
      '<span>' +
      escape(item.reach || 'Mobile · Desktop') +
      '</span></span>'
    );
  }

  function pluginCard(plugin, featured) {
    return (
      '<li><a class="mk-card mk-plugin' +
      (featured ? ' mk-featured' : '') +
      '" href="#plugin/' +
      escape(plugin.id) +
      '" style="--deep: ' +
      plugin.colours[0] +
      '; --bright: ' +
      plugin.colours[1] +
      '">' +
      tile(plugin, featured ? 'lg' : 'md') +
      '<span class="mk-card-words"><span class="mk-name">' +
      escape(plugin.name) +
      '</span><span class="mk-line">' +
      escape(plugin.line) +
      '</span>' +
      reach(plugin) +
      '</span></a></li>'
    );
  }

  /* A theme's miniature: a note in its colours, as the app's ThemeMiniature paints it; System split down the middle. */
  function miniature(palette) {
    var p = palette;
    return (
      '<span class="mk-mini" style="--bg: ' + p.background + '; --side: ' + p.sidebar + '; --surface: ' + p.surface + '; --border: ' + p.border + '; --text: ' + p.text + '; --muted: ' + p.muted + '; --accent: ' + p.accent + '">' +
      '<span class="mk-mini-side"><i></i><i></i><i></i><i></i></span>' +
      '<span class="mk-mini-note"><b class="mk-mini-title"></b><i style="--w: 90%"></i><i style="--w: 70%"></i>' +
      '<span class="mk-mini-todo"><em></em><i style="--w: 55%"></i></span>' +
      '<span class="mk-mini-tabs"><em></em><b></b></span></span></span>'
    );
  }

  function themePicture(theme) {
    if (!theme.alternate) return miniature(theme.palette);
    return '<span class="mk-mini-pair">' + miniature(theme.palette) + '<span class="mk-mini-half">' + miniature(theme.alternate) + '</span></span>';
  }

  function themeCard(theme) {
    return (
      '<li><a class="mk-card mk-theme" href="#theme/' +
      escape(theme.id) +
      '"><span class="mk-picture">' +
      themePicture(theme) +
      '</span><span class="mk-card-words"><span class="mk-name">' +
      escape(theme.name) +
      '</span><span class="mk-line">' +
      escape(theme.line) +
      '</span></span></a></li>'
    );
  }

  function fontStyle(font) {
    return "font-family: '" + escape(font.family) + "', " + (font.coding ? 'ui-monospace, monospace' : font.id === 'lora' ? 'ui-serif, Georgia, serif' : 'ui-sans-serif, system-ui, sans-serif');
  }

  function fontCard(font) {
    return (
      '<li><a class="mk-card mk-font" href="#font/' +
      escape(font.id) +
      '"><span class="mk-specimen" style="' +
      fontStyle(font) +
      '"><span class="mk-aa">Aa</span><span class="mk-sample">' +
      escape(listing.samples.note) +
      '</span></span><span class="mk-card-words"><span class="mk-name">' +
      escape(font.name) +
      '</span><span class="mk-line">' +
      escape(font.roles.join(' · ')) +
      '</span></span></a></li>'
    );
  }

  function heading(title, glyph, meta, shelf) {
    var more = shelf && state.shelf === 'all' && !state.query.trim() ? '<button type="button" class="mk-more" data-shelf="' + shelf + '">See all</button>' : '';
    return '<div class="mk-heading"><h2>' + icon(glyph) + '<span>' + escape(title) + '</span></h2>' + (meta ? '<span class="mk-meta">' + escape(meta) + '</span>' : '') + more + '</div>';
  }

  // ---- finding ---------------------------------------------------------------------------------------------------

  /* Every word typed starts a word of what the thing says of itself, as the app's search finds (settings_search.dart `wordsFound`). */
  function found(query, fields) {
    var words = query.toLowerCase().split(/\s+/).filter(Boolean);
    if (!words.length) return true;
    var haystack = fields
      .filter(Boolean)
      .join(' ')
      .toLowerCase()
      .split(/[^a-z0-9]+/)
      .filter(Boolean);
    return words.every(function (word) {
      var bare = word.replace(/[^a-z0-9]/g, '');
      return (
        !bare ||
        haystack.some(function (w) {
          return w.indexOf(bare) === 0;
        })
      );
    });
  }

  function pluginFound(p) {
    return found(state.query, [p.name, p.line, p.description, categoryLabel(p.category), p.adds.join(' '), p.reach, 'plugin plugins add-on extension integration']);
  }
  function themeFound(t) {
    return found(state.query, [t.name, t.line, 'theme themes look colour color palette']);
  }
  function fontFound(f) {
    return found(state.query, [f.name, f.roles.join(' '), 'font fonts typeface type']);
  }

  // ---- the shelves -----------------------------------------------------------------------------------------------

  function drawControls() {
    $('#mk-shelves').innerHTML = listing.shelves
      .map(function (shelf) {
        return '<button type="button" class="mk-seg" data-shelf="' + shelf.id + '" aria-pressed="' + (state.shelf === shelf.id) + '">' + escape(shelf.label) + '</button>';
      })
      .join('');
    var chips = $('#mk-chips');
    chips.hidden = state.shelf !== 'plugins';
    chips.innerHTML = [{ id: null, label: 'All' }]
      .concat(listing.categories)
      .map(function (c) {
        return '<button type="button" class="mk-chip" data-category="' + (c.id || '') + '" aria-pressed="' + (state.category === c.id) + '">' + escape(c.label) + '</button>';
      })
      .join('');
  }

  function draw() {
    drawControls();
    var shelf = state.shelf;
    var searching = !!state.query.trim();
    var plugins = listing.plugins.filter(function (p) {
      return pluginFound(p) && (shelf !== 'plugins' || !state.category || p.category === state.category);
    });
    var themes = listing.themes.filter(themeFound);
    var fonts = listing.fonts.filter(fontFound);
    var showPlugins = shelf === 'all' || shelf === 'plugins';
    var showThemes = shelf === 'all' || shelf === 'themes';
    var showFonts = shelf === 'all' || shelf === 'fonts';
    var html = '';

    if (shelf === 'all' && !searching) {
      var featured = listing.featured
        .map(function (id) {
          return byId('plugin', id);
        })
        .filter(Boolean);
      html += '<section class="mk-section" aria-label="Featured">' + heading('Featured', 'sparkles') + '<ul class="mk-grid mk-grid-featured">' + featured.map(function (p) {
        return pluginCard(p, true);
      }).join('') + '</ul></section>';
    }
    if (showPlugins && plugins.length) {
      html +=
        '<section class="mk-section" id="mk-plugins" aria-label="Plugins">' +
        heading('Plugins', 'puzzle', plugins.length + ' of ' + listing.plugins.length, 'plugins') +
        '<p class="mk-note">Every one is built in: adding one is a switch, and removing one keeps what it kept. None reaches anywhere its page does not say.</p>' +
        '<ul class="mk-grid">' +
        plugins.map(function (p) {
          return pluginCard(p, false);
        }).join('') +
        '</ul></section>';
    } else if (showPlugins && shelf === 'plugins' && state.category && !searching) {
      html += '<p class="mk-note">There is no plugin in ' + escape(categoryLabel(state.category)) + ' yet.</p>';
    }
    if (showThemes && themes.length) {
      html += '<section class="mk-section" id="mk-themes" aria-label="Themes">' + heading('Themes', 'swatch-book', themes.length + ' to choose from', 'themes') + '<ul class="mk-grid mk-grid-looks">' + themes.map(themeCard).join('') + '</ul></section>';
    }
    if (showFonts && fonts.length) {
      html += '<section class="mk-section" id="mk-fonts" aria-label="Fonts">' + heading('Fonts', 'type', 'For your notes, and the app itself', 'fonts') + '<ul class="mk-grid mk-grid-fonts">' + fonts.map(fontCard).join('') + '</ul></section>';
    }
    var any = (showPlugins && plugins.length) || (showThemes && themes.length) || (showFonts && fonts.length);
    if (!any && searching) {
      html =
        '<div class="mk-nothing"><img src="icon.png" width="64" height="64" alt="" /><p class="mk-name">' +
        (searching ? 'Nothing matches &ldquo;' + escape(state.query.trim()) + '&rdquo;' : 'Nothing here yet') +
        '</p><p class="mk-line">Try a plugin&rsquo;s name, a theme or a font.</p><button type="button" class="pill" id="mk-everything">Show everything</button></div>';
    }
    $('#mk-list').innerHTML = html;
  }

  function choose(shelf) {
    state.shelf = shelf;
    if (shelf !== 'plugins') state.category = null;
    draw();
  }

  // ---- a thing's own page ----------------------------------------------------------------------------------------

  function byId(kind, id) {
    var list = { plugin: listing.plugins, theme: listing.themes, font: listing.fonts }[kind] || [];
    return (
      list.filter(function (item) {
        return item.id === id;
      })[0] || null
    );
  }

  /* Open in Ghost.md, and the word that waits under it for a device without the app. */
  function opener(item, kind) {
    var does = { plugin: 'Opens its page in the Market, with Add.', theme: 'Opens it in the Market, with Use this theme.', font: 'Opens it in the Market, with Use for notes.' }[kind];
    return (
      '<div class="mk-open"><a class="pill pill-ink pill-lg" data-open href="' +
      escape(item.link) +
      '">' +
      icon('square-arrow-out-up-right') +
      '<span>Open in Ghost.md</span></a>' +
      '<a class="pill pill-lg" href="/#download">' +
      icon('download') +
      '<span>Get the app</span></a></div>' +
      '<p class="mk-fine">' +
      does +
      ' In Ghost.md for Android, iPhone and the Mac, in Advanced mode.</p>' +
      '<div class="mk-fallback" role="status" hidden><p><b>Ghost.md didn&rsquo;t open.</b> It may not be on this device yet.</p><p class="mk-open-row"><a class="pill pill-ink" href="/#download">' +
      icon('download') +
      '<span>Get the app</span></a><button type="button" class="pill" data-open-again>Try again</button></p></div>'
    );
  }

  function section(title, body) {
    return '<section class="mk-part"><h3>' + escape(title) + '</h3>' + body + '</section>';
  }

  function point(glyph, label, hint) {
    return '<li>' + icon(glyph, 'mk-point-i') + '<span><span class="mk-point">' + escape(label) + '</span>' + (hint ? '<span class="mk-hint">' + escape(hint) + '</span>' : '') + '</span></li>';
  }

  function platforms(item) {
    var p = item.platforms;
    return (
      '<ul class="mk-platforms">' +
      [
        ['Android', p.android, 'smartphone'],
        ['iPhone', p.iphone, 'smartphone'],
        ['Mac', p.mac, 'laptop'],
      ]
        .map(function (each) {
          return '<li' + (each[1] ? '' : ' class="mk-not"') + '>' + icon(each[2]) + '<span>' + each[0] + (each[1] ? '' : ': not yet') + '</span></li>';
        })
        .join('') +
      '</ul>'
    );
  }

  function close() {
    return '<button type="button" class="mk-close" data-close aria-label="Close">' + icon('x') + '</button>';
  }

  function pluginPage(p) {
    var adds = p.adds.map(function (add) {
      return point('sparkles', add);
    });
    if (p.settings) adds.push(point('settings', 'A page of its own in Settings', 'Among Settings’ own pages, once it is added.'));
    var reaches = p.permissions.length
      ? p.permissions.map(function (permission) {
          return point(permission.icon, permission.label, permission.why);
        })
      : [point('shield-check', 'Nothing past the note you are in', 'It asks for nothing: what it does happens in the note as you type it.')];
    return (
      '<header class="mk-head" style="--deep: ' + p.colours[0] + '; --bright: ' + p.colours[1] + '">' +
      '<span class="mk-head-art" aria-hidden="true">' + mark(p) + '</span>' +
      close() +
      tile(p, 'lg') +
      '<h2 id="mk-detail-name">' + escape(p.name) + '</h2>' +
      '<p>' + escape(p.line) + '</p>' +
      '<p class="mk-tags"><span>' + escape(categoryLabel(p.category)) + '</span><span>' + escape(p.reach) + '</span></p>' +
      '</header><div class="mk-body">' +
      opener(p, 'plugin') +
      section('Works on', platforms(p)) +
      section('What it does', '<p>' + escape(p.description) + '</p>') +
      (adds.length ? section('What it adds', '<ul class="mk-points">' + adds.join('') + '</ul>') : '') +
      section('What it needs', '<ul class="mk-points">' + reaches.join('') + '</ul>') +
      '<p class="mk-fine">' + escape(categoryLabel(p.category)) + ' · ' + escape(p.author) + ' · version ' + escape(p.version) + (p.standard ? ' · on from the start' : '') + '</p>' +
      '</div>'
    );
  }

  function themePage(t) {
    var what = t.scheme === 'system' ? 'Light by day and dark by night, as the device is.' : (t.scheme === 'light' ? 'A light theme' : 'A dark theme') + (t.accent ? ', with ' + t.accent.toLowerCase() + ' as its accent.' : ', in pure grey ink.');
    return (
      '<header class="mk-head mk-head-plain">' + close() + '<span class="mk-picture mk-picture-lg">' + themePicture(t) + '</span>' +
      '<p class="mk-kind">Theme</p><h2 id="mk-detail-name">' + escape(t.name) + '</h2><p>' + escape(t.line) + '</p></header>' +
      '<div class="mk-body">' + opener(t, 'theme') +
      section('What it is', '<p>' + escape(what) + ' The notes, the lists, Settings and the dock all wear it; your words stay as they are.</p>') +
      section('Works on', platforms(t)) +
      section('What it needs', '<ul class="mk-points">' + point('shield-check', 'Nothing', 'A theme is a choice in Appearance, built in.') + '</ul>') +
      '</div>'
    );
  }

  function fontPage(f) {
    var uses = ['Your notes’ words' + (f.coding ? ', and their code' : '')];
    if (f.interface) uses.push('The app’s own words: menus, tabs and buttons');
    return (
      '<header class="mk-head mk-head-plain">' + close() +
      '<span class="mk-specimen mk-specimen-lg" style="' + fontStyle(f) + '"><span class="mk-aa">Aa</span><span class="mk-sample">' + escape(listing.samples.note) + '</span>' +
      (f.interface ? '<span class="mk-sample mk-sample-ui">' + escape(listing.samples.interface) + '</span>' : '') + '</span>' +
      '<p class="mk-kind">Font</p><h2 id="mk-detail-name">' + escape(f.name) + '</h2><p>' + escape(f.roles.join(' · ')) + '</p></header>' +
      '<div class="mk-body">' + opener(f, 'font') +
      section('What it sets', '<ul class="mk-points">' + uses.map(function (use) {
        return point('type', use);
      }).join('') + '</ul>') +
      section('Works on', platforms(f)) +
      section('What it needs', '<ul class="mk-points">' + point('shield-check', 'Nothing', 'Every face ships inside the app.') + '</ul>') +
      '</div>'
    );
  }

  var dialog = $('#mk-detail');
  var shown = null;

  function show(kind, id) {
    var item = byId(kind, id);
    if (!item) return hide();
    shown = kind + '/' + id;
    var inner = $('#mk-detail-in');
    // A plugin's page wears its hue throughout (market.css `--mk-tone`); a theme's or a font's the page's ink.
    if (kind === 'plugin') {
      inner.style.setProperty('--deep', item.colours[0]);
      inner.style.setProperty('--bright', item.colours[1]);
    } else {
      inner.style.removeProperty('--deep');
      inner.style.removeProperty('--bright');
    }
    inner.innerHTML = kind === 'plugin' ? pluginPage(item) : kind === 'theme' ? themePage(item) : fontPage(item);
    document.title = item.name + ' · Market · Ghost.md';
    if (!dialog.open) dialog.showModal();
    dialog.scrollTop = 0;
  }

  function hide() {
    shown = null;
    document.title = 'Market · Ghost.md';
    if (dialog.open) dialog.close();
  }

  /* What the address says: a thing's page (#plugin/notion), or a shelf (#plugins, #themes, #fonts). */
  function follow() {
    var hash = decodeURIComponent(location.hash.replace(/^#/, ''));
    var thing = /^(plugin|theme|font)\/([a-z0-9_-]+)$/.exec(hash);
    if (thing) return show(thing[1], thing[2]);
    hide();
    if (hash === 'plugins' || hash === 'themes' || hash === 'fonts') choose(hash);
  }

  /* Back to the shelves, leaving the address as it was before the page was opened. */
  function shut() {
    if (!shown) return;
    if (history.state && history.state.mkFrom === 'shelves') history.back();
    else history.replaceState(null, '', location.pathname + location.search);
    hide();
  }

  // ---- into the app ----------------------------------------------------------------------------------------------

  function openInApp(link, fallback) {
    var left = false;
    function away() {
      left = true;
    }
    function hidden() {
      if (document.visibilityState === 'hidden') left = true;
    }
    window.addEventListener('pagehide', away);
    window.addEventListener('blur', away);
    document.addEventListener('visibilitychange', hidden);
    if (fallback) fallback.hidden = true;
    market.launch(link);
    setTimeout(function () {
      window.removeEventListener('pagehide', away);
      window.removeEventListener('blur', away);
      document.removeEventListener('visibilitychange', hidden);
      // Still here, in front, with the focus: nothing took the link.
      if (!left && document.visibilityState === 'visible' && document.hasFocus() && fallback) fallback.hidden = false;
    }, WAIT);
  }

  // ---- wiring ----------------------------------------------------------------------------------------------------

  document.addEventListener('click', function (event) {
    var target = event.target.closest ? event.target : event.target.parentElement;
    var shelf = target.closest('[data-shelf]');
    if (shelf) {
      choose(shelf.getAttribute('data-shelf'));
      return;
    }
    var shelfLink = target.closest('[data-shelf-link]');
    if (shelfLink) {
      event.preventDefault();
      choose(shelfLink.getAttribute('data-shelf-link'));
      $('.mk-shop').scrollIntoView({ behavior: 'smooth', block: 'start' });
      return;
    }
    var chip = target.closest('[data-category]');
    if (chip) {
      state.category = chip.getAttribute('data-category') || null;
      draw();
      return;
    }
    if (target.closest('#mk-everything')) {
      state = { shelf: 'all', query: '', category: null };
      $('#mk-find').value = '';
      draw();
      return;
    }
    var card = target.closest('a.mk-card');
    if (card) {
      event.preventDefault();
      history.pushState({ mkFrom: 'shelves' }, '', card.getAttribute('href'));
      follow();
      return;
    }
    if (target.closest('[data-close]')) {
      shut();
      return;
    }
    var open = target.closest('[data-open]');
    if (open) {
      event.preventDefault();
      openInApp(open.getAttribute('href'), $('.mk-fallback', dialog));
      return;
    }
    if (target.closest('[data-open-again]')) {
      openInApp($('[data-open]', dialog).getAttribute('href'), $('.mk-fallback', dialog));
      return;
    }
    // A press on the dim around the page shuts it.
    if (target === dialog) shut();
  });

  // Escape shuts the page the way its cross does, so the address follows.
  dialog.addEventListener('cancel', function (event) {
    event.preventDefault();
    shut();
  });

  $('#mk-find').addEventListener('input', function (event) {
    state.query = event.target.value;
    draw();
  });

  window.addEventListener('popstate', follow);
  window.addEventListener('hashchange', follow);

  // ---- the listing -----------------------------------------------------------------------------------------------

  function band() {
    var tiles = listing.featured
      .map(function (id) {
        return byId('plugin', id);
      })
      .concat(
        listing.plugins.filter(function (p) {
          return listing.featured.indexOf(p.id) < 0;
        })
      )
      .filter(Boolean)
      .slice(0, 7);
    $('#mk-band-tiles').innerHTML = tiles
      .map(function (p, i) {
        return '<span class="mk-band-tile mk-band-tile-' + i + '">' + tile(p, 'band') + '</span>';
      })
      .join('');
    $('#mk-count').textContent = listing.plugins.length + ' plugins · ' + listing.themes.length + ' themes · ' + listing.fonts.length + ' fonts';
  }

  fetch('market.json')
    .then(function (response) {
      if (!response.ok) throw new Error('market.json answered ' + response.status);
      return response.json();
    })
    .then(function (data) {
      listing = data;
      band();
      draw();
      follow();
    })
    .catch(function () {
      $('#mk-list').innerHTML = '<p class="mk-note">The Market could not be read just now. Everything on it is in the app: <a href="/#download">get Ghost.md</a>.</p>';
    });
})();
