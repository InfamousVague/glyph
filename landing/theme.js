/*
 * The page a visitor picked on ghostmarkdown.com's home page (home.js), put on <html> before anything is drawn, on
 * every page: System follows the device; Light and Dark are the app's pure grays; Dawn, Boreal and Ember are the kit's
 * named themes (site.css). Kept in this browser only, and a page without it simply follows the system.
 */
(function () {
  var themes = { light: ['light'], dark: ['dark'], dawn: ['light', 'dawn'], boreal: ['dark', 'boreal'], ember: ['dark', 'ember'] };
  var picked = null;
  try {
    picked = localStorage.getItem('ghostmd-site-theme');
  } catch (e) {
    picked = null;
  }
  var root = document.documentElement;
  var theme = picked && themes[picked];
  if (!theme) return;
  root.setAttribute('data-theme', theme[0]);
  if (theme[1]) root.setAttribute('data-theme-preset', theme[1]);
})();
