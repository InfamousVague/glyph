/* The strip at the foot of every version: its number, and a way to the others and the index (explore.css .x-strip). */
(function () {
  var versions = ['01-air', '02-blocks', '03-terminal', '04-bento', '05-readme', '06-palette', '07-shell', '08-slides', '09-feed', '10-specs'];
  var here = (location.pathname.split('/').pop() || '').replace(/\.html$/, '');
  var at = versions.indexOf(here);
  var strip = document.createElement('nav');
  strip.className = 'x-strip';
  strip.setAttribute('aria-label', 'The ten versions');
  var html = '<span class="x-n">' + (at < 0 ? 'Versions' : 'Version ' + (at + 1) + ' of 10') + '</span>';
  html += '<a href="index.html" title="All ten">All</a>';
  if (at >= 0) {
    html += '<a href="' + versions[(at + 9) % 10] + '.html" title="Previous">&larr;</a>';
    html += '<a href="' + versions[(at + 1) % 10] + '.html" title="Next">&rarr;</a>';
  }
  strip.innerHTML = html;
  document.body.appendChild(strip);
})();
