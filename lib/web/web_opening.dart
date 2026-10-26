/// How the web build opens its library and its account (docs/WEB.md): main.dart's `_opened` hands over to
/// [openInBrowser] in a browser, where the phone opens its Rust core over FFI. The page's half is
/// web_opening_page.dart; on a device there is nothing to open here (web_opening_stub.dart).
library;

export 'web_opening_stub.dart' if (dart.library.js_interop) 'web_opening_page.dart';
