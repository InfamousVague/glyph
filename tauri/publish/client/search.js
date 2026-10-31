/*
 * The site's search (publish/src/search.ts writes the index): the one script a published site carries, its own file,
 * fetched from the site itself. Typing in the bar's box fetches search.json once, matches every word typed against each
 * page's title and words, and lists the pages that have them all over the page, the words marked in a snippet; Escape
 * or an empty box puts the page back. No library, no network beyond the index, nothing kept.
 */
(function () {
  var box = document.querySelector('input[type="search"][data-index]');
  var results = document.getElementById('search-results');
  if (!box || !results) return;
  var index = null;
  var loading = null;
  var root = document.body.getAttribute('data-root') || '';

  function load() {
    if (index) return Promise.resolve(index);
    if (!loading) {
      loading = fetch(box.getAttribute('data-index'))
        .then(function (r) {
          return r.json();
        })
        .then(function (json) {
          index = json;
          return json;
        });
    }
    return loading;
  }

  function escapeHtml(text) {
    return text.replace(/[&<>"]/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c];
    });
  }

  function snippet(text, words) {
    var lower = text.toLowerCase();
    var at = -1;
    for (var i = 0; i < words.length && at < 0; i += 1) at = lower.indexOf(words[i]);
    var start = Math.max(0, at - 60);
    var piece = (start > 0 ? '…' : '') + text.slice(start, start + 160) + (start + 160 < text.length ? '…' : '');
    var html = escapeHtml(piece);
    words.forEach(function (word) {
      var re = new RegExp('(' + word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + ')', 'ig');
      html = html.replace(re, '<mark>$1</mark>');
    });
    return html;
  }

  function show(query) {
    var words = query
      .toLowerCase()
      .split(/\s+/)
      .filter(function (w) {
        return w.length > 0;
      });
    if (!words.length) {
      results.hidden = true;
      results.innerHTML = '';
      return;
    }
    load().then(function (pages) {
      var hits = pages.filter(function (page) {
        var hay = (page.title + ' ' + page.folder + ' ' + page.text).toLowerCase();
        return words.every(function (w) {
          return hay.indexOf(w) >= 0;
        });
      });
      hits.sort(function (a, b) {
        var at = words.every(function (w) {
          return a.title.toLowerCase().indexOf(w) >= 0;
        });
        var bt = words.every(function (w) {
          return b.title.toLowerCase().indexOf(w) >= 0;
        });
        return Number(bt) - Number(at);
      });
      var items = hits.slice(0, 30).map(function (page) {
        return '<li><a href="' + escapeHtml(root + page.href) + '">' + escapeHtml(page.title) + '</a><small>' + escapeHtml(page.folder || 'Library') + '</small>' + '<small>' + snippet(page.text, words) + '</small></li>';
      });
      results.innerHTML = '<p class="quiet">' + (hits.length ? hits.length + (hits.length === 1 ? ' page' : ' pages') : 'Nothing found') + ' for “' + escapeHtml(query) + '”</p><ul>' + items.join('') + '</ul>';
      results.hidden = false;
    });
  }

  box.addEventListener('input', function () {
    show(box.value.trim());
  });
  box.addEventListener('keydown', function (event) {
    if (event.key === 'Escape') {
      box.value = '';
      show('');
    }
  });
  box.form &&
    box.form.addEventListener('submit', function (event) {
      event.preventDefault();
      show(box.value.trim());
    });
  // Arriving at the home page with ?q= from a page's box, before this script ran there.
  var asked = new URLSearchParams(location.search).get('q');
  if (asked) {
    box.value = asked;
    show(asked);
  }
})();
