/* The strip at the foot of every version: its number, and a way to the others and the index (explore.css .x-strip). The versions live at /1/ to /10/. */
(function () {
  var m = location.pathname.match(/\/(\d+)\/(index\.html)?$/);
  var at = m ? parseInt(m[1], 10) : 0;
  var strip = document.createElement('nav');
  strip.className = 'x-strip';
  strip.setAttribute('aria-label', 'The ten versions');
  var html = '<span class="x-n">' + (at ? 'Version ' + at + ' of 10' : 'Versions') + '</span>';
  html += '<a href="/explore/" title="All ten">All</a>';
  if (at) {
    html += '<a href="/' + (at === 1 ? 10 : at - 1) + '/" title="Previous">&larr;</a>';
    html += '<a href="/' + (at === 10 ? 1 : at + 1) + '/" title="Next">&rarr;</a>';
  }
  strip.innerHTML = html;
  document.body.appendChild(strip);
})();
