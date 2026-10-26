/// web_opening.dart's on a device, where main.dart never asks it: the phone's library is its Rust core.
library;

import '../core/native/core.dart';
import '../root/account_wiring.dart' show AccountMaking;

/// What the page opened: its core, and its account where the build has a service.
typedef BrowserOpened = ({CoreInvoke core, AccountMaking? account, int carried});

Future<BrowserOpened> openInBrowser({String? base}) => throw UnsupportedError('Only the web build opens a library in a browser.');
