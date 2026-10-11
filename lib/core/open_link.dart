/// Hands an address to the phone: its browser, its mail, its dialler, its maps. Ports `openLink` of
/// `src/app/core/linkPreview.ts` and `openUrl` of `src/app/plugins/host.ts`, which both hand the address to Tauri's
/// opener plugin, and the rule that plugin is held to (`src-tauri/capabilities/default.json`: `opener:default`,
/// which lets through `http`, `https`, `mailto` and `tel`, and `geo:*` for a tapped map).
///
/// What differs:
/// - The opener is the phone's half of the channel `ghost_md/open` (Kotlin): `open {url}`, which starts an
///   `ACTION_VIEW` for the address and answers whether anything took it.
/// - The rule is kept here, before the channel, and not only in a capability file: nothing but those five schemes
///   reaches the phone ([canOpenLink]), so never `javascript:`, `file:`, `content:` or `intent:`.
/// - A refused address, a phone with nothing to open it, and a run with no phone half (a desktop, a test) all end
///   quietly, where the plugin's promise rejects: every caller on the page drops that rejection (`void openLink`,
///   `.catch(() => undefined)`), and a [LinkOpener] here is called from taps that do the same.
library;

import 'package:flutter/services.dart';

/// The channel the phone's opener answers on.
const MethodChannel openLinkChannel = MethodChannel('ghost_md/open');

/// The schemes the phone is handed: the opener plugin's own four, and `geo` for a place.
const Set<String> openableSchemes = <String>{'http', 'https', 'mailto', 'tel', 'geo'};

final RegExp _unprintable = RegExp(r'[\x00-\x20\x7f]');

/// Whether [url] is an address the phone may be handed: one of [openableSchemes], a web address with a host, and
/// no space or control character in it.
bool canOpenLink(String url) {
  if (url.isEmpty || _unprintable.hasMatch(url)) return false;
  final uri = Uri.tryParse(url);
  if (uri == null || !openableSchemes.contains(uri.scheme)) return false;
  if (uri.scheme == 'http' || uri.scheme == 'https') return uri.host.isNotEmpty;
  // `mailto:`, `tel:` and `geo:` say something after the colon.
  return url.length > uri.scheme.length + 1;
}

/// Opens [url] on the phone (`openLink`): a `LinkOpener`. Opens nothing for an address the phone may not be
/// handed, and fails quietly where no phone half is listening or nothing can open it.
Future<void> openLink(String url) async {
  if (!canOpenLink(url)) return;
  try {
    await openLinkChannel.invokeMethod<bool>('open', <String, Object?>{'url': url});
  } on MissingPluginException {
    // A desktop run, a test: no phone half.
  } on PlatformException {
    // The phone refused it, or nothing there opens such an address.
  }
}
