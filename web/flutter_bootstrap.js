// How Ghost.md's page starts (docs/WEB.md). `flutter build web` fills the two lines below with Flutter's loader and
// this build's configuration; the rest is the page's own.
{{flutter_js}}
{{flutter_build_config}}

// No service worker. Flutter's own is deprecated, and one that kept the old files would hand a returning visitor
// last week's app over this week's index: every file is served `no-cache` instead, and revalidated. A worker any
// earlier page left under this address is let go, once, and the page goes on without waiting for it.
if ('serviceWorker' in navigator) {
  const here = new URL('.', document.baseURI).href;
  navigator.serviceWorker.getRegistrations().then((all) => {
    for (const one of all) if (one.scope.startsWith(here)) one.unregister();
  }).catch(() => {});
}

_flutter.loader.load({
  config: {
    // The box serves the page without cross-origin isolation, so skwasm draws on one thread; it says so once, and
    // that is known (docs/WEB.md, "Threads").
    suppressMultithreadingWarning: true,
  },
});
