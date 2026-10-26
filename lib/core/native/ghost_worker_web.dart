/// ghost_worker.dart's names in the web build, which has no `dart:ffi` and no isolates: the page's core is a Web
/// Worker over WebAssembly instead (lib/core/native/web_core.dart, web/core/ghost_core_worker.js; docs/WEB.md).
/// Nothing opens a [GhostCore] in a browser (main.dart opens the web core there); one that tried is told why.
library;

import 'dart:isolate';

/// As ghost_worker.dart's.
typedef GhostWorkerStart = (SendPort answers, String? libraryPath, bool hears);

/// Says, as a library that will not load says, that a browser has no library to load.
void ghostWorkerMain(GhostWorkerStart start) {
  start.$1.send('Ghost.md\'s core is not a library in a browser: the web build opens its worker instead.');
}
