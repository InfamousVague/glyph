/// web_opening.dart's in a browser: the page's storage, the browser's core in its worker, the library over both,
/// the old web app's notes carried in, and the account made over the same (its session and keys kept as
/// `deviceSecureStore` keeps them here, lib/web/page_secure.dart).
library;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import '../account/crypto.dart';
import '../core/native/core.dart';
import '../root/account_wiring.dart' show AccountMaking;
import 'idb_shelf.dart';
import 'page_net.dart';
import 'shelf.dart';
import 'web_core.dart';
import 'web_facts.dart';
import 'web_store.dart';
import 'worker_core.dart';

/// What the page opened: its core, its account where the build has a service, and how many of the old web app's
/// notes were carried in this time.
typedef BrowserOpened = ({CoreInvoke core, AccountMaking? account, int carried});

/// Opens the library and the account. A browser that will not open IndexedDB (a private window, storage turned
/// off) opens on a shelf in memory: the page works and keeps nothing, which Settings › About says. Throws
/// [CoreError] where the browser's core will not open: then main.dart opens the invented library, as a phone does
/// whose core will not load.
Future<BrowserOpened> openInBrowser({String? base}) async {
  Shelf shelf;
  try {
    shelf = await IdbShelf.open();
  } catch (failure) {
    debugPrint('[ghost] this browser keeps nothing: $failure');
    shelf = MemoryShelf();
    webKeepsNothing = true;
  }
  final worker = await WorkerCore.open();
  final store = await WebStore.open(shelf, worker.invoke);
  final core = WebCore(store, worker.invoke);
  final carried = await carryOldPage(store, shelf, _oldPageNotes());
  webCarried = carried;
  if (carried > 0) debugPrint('[ghost] carried $carried notes from the old web app');
  final account = base == null
      ? null
      : AccountMaking(
          base: base,
          crypto: CoreCrypto(worker.invoke),
          dataDir: '',
          fetcher: pageFetcher(),
          docsFor: (id) => ShelfTeamDocs(shelf, id),
        );
  return (core: core.invoke, account: account, carried: carried);
}

/// The old web app's notes, as its `store.ts` kept them in this site's `localStorage`; null where there are none or
/// the browser will not say.
String? _oldPageNotes() {
  try {
    return web.window.localStorage.getItem('glyph-notes');
  } catch (_) {
    return null;
  }
}
