/*
 * The join page (join.html; docs/TEAMS.md, "Invite by email"): the code from after the #, what it joins asked of the
 * service with the code in the body (never a URL, so it is in no log), and the ways in for this device. Plain script,
 * no build, as home.js is.
 */
(function () {
  'use strict';

  // The stores, as home.js has them (`STORES`): set Play's address there and here once its listing is live.
  var STORES = {
    play: null,
    appStore: 'https://apps.apple.com/app/ghost-markdown/id6818598896',
  };
  var WEB_APP = 'https://attack.fm/glyph/';

  var $ = function (id) {
    return document.getElementById(id);
  };

  // A code is 16 to 64 base64url characters (server/src/orgs.rs `code_of`); the link is /join#<code>, and the reader
  // page's older shape #join=<code> is taken too.
  var hash = (location.hash || '').replace(/^#/, '').replace(/^join=/, '');
  var code = /^[A-Za-z0-9_-]{16,64}$/.test(hash) ? hash : null;
  if (!code) {
    $('join-broken').hidden = false;
    return;
  }

  // ---- the ways in -------------------------------------------------------------------------------------------------

  var link = 'https://ghostmarkdown.com/join#' + code;
  $('join-open').href = 'ghostmd://join/' + code;
  $('join-web').href = WEB_APP + '#join=' + code;
  $('join-steps').hidden = false;

  // The device in hand's download, as the home page picks it (home.js, "the device in hand's way first").
  var ua = navigator.userAgent;
  var ios = /iPhone|iPad|iPod/i.test(ua) || (navigator.maxTouchPoints > 1 && /Macintosh/.test(ua));
  var first = /Android/i.test(ua) ? 'android' : ios ? 'ios' : /Macintosh|Mac OS X/.test(ua) ? 'mac' : /Windows NT/.test(ua) ? 'windows' : null;
  var get = $('join-get');
  var word = $('join-get-word');
  var files = { android: ['/glyph.apk', 'Download for Android'], mac: ['/glyph.dmg', 'Download for Mac'], windows: ['/glyph-setup.exe', 'Download for Windows'] };
  if (first === 'ios' && STORES.appStore) {
    get.href = STORES.appStore;
    word.textContent = 'Get it on the App Store';
  } else if (first === 'android' && STORES.play) {
    get.href = STORES.play;
    word.textContent = 'Get it on Google Play';
  } else if (files[first]) {
    get.href = files[first][0];
    get.setAttribute('download', '');
    word.textContent = files[first][1];
  }
  // A direct download cannot carry the invitation into the app (no store to remember it), so the page says to come
  // back and open it; the app also offers to paste the link when it is opened fresh.
  get.addEventListener('click', function () {
    $('join-after-get').hidden = false;
  });

  // ---- copying the link --------------------------------------------------------------------------------------------

  $('join-copy').addEventListener('click', function () {
    var said = function (words) {
      $('join-copy-word').textContent = words;
      window.setTimeout(function () {
        $('join-copy-word').textContent = 'Copy the invite link';
      }, 2000);
    };
    if (!navigator.clipboard) return said(link);
    navigator.clipboard.writeText(link).then(
      function () {
        said('Copied');
      },
      function () {
        said(link);
      },
    );
  });

  // ---- what it joins -----------------------------------------------------------------------------------------------

  fetch('/api/v1/joins/preview', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code: code }),
    cache: 'no-store',
    referrerPolicy: 'no-referrer',
  })
    .then(function (r) {
      if (r.status === 404) return 'gone';
      return r.ok ? r.json() : null;
    })
    .then(function (answer) {
      if (answer === 'gone') {
        $('join-steps').hidden = true;
        $('join-gone').hidden = false;
        $('join-title').textContent = 'This invitation has ended';
        return;
      }
      if (!answer || !answer.org || typeof answer.org.name !== 'string') return;
      var name = answer.org.name;
      document.title = 'Join ' + name + ' · Ghost.md';
      $('join-title').textContent = 'Join ' + name;
      var members = typeof answer.org.members === 'number' ? answer.org.members : null;
      var parts = [];
      if (answer.by) parts.push('@' + answer.by + ' invited you to their team on Ghost.md');
      else parts.push("You're invited to this team on Ghost.md");
      if (members) parts.push(members === 1 ? '1 member' : members + ' members');
      $('join-kicker').textContent = parts.join(' · ');
    })
    .catch(function () {
      // Offline, or the service is away: the page still offers every way in, without the name.
      return undefined;
    });
})();
