/// Someone's add-me link (GMFB-34: "A gogho.st/add/USERNAME link and QR code that opens a friend request"):
/// `https://gogho.st/add/USERNAME#KEY`, shown with its QR code in Profile and shared from there. Opened, the app asks
/// whether to send that person a friend request (lib/main.dart); the site's page (site/add) does the same for someone
/// without the app, leading to it.
///
/// `#KEY` is the first [keyDigits] hex digits of the person's account name (the SHA-256 of their key, as
/// NetCrypto.idOf makes it), after `#` so a browser never sends it to any server (docs/OPEN_NETWORK.md, section 3: the
/// name watch). The app refuses the relay's answer for the username where its key doesn't make a name that begins so
/// (Buddies.add's keyPrefix): a relay that gives the username to someone else can't slip them in through the link.
library;

import '../me/me.dart' show Me;

/// How many hex digits of the account name an add-me link carries.
const keyDigits = 8;

/// [username]'s add-me link, with the first [keyDigits] hex digits of [id] (their account name) after `#` where given.
String addMeLink(String username, {String? id}) => 'https://gogho.st/add/$username${id != null && RegExp(r'^[0-9a-f]{32}$').hasMatch(id) ? '#${id.substring(0, keyDigits)}' : ''}';

/// The username an add-me link names ([addMeLink], or the app's own `ghostmsg://add/NAME`), tidied; null for
/// anything else, or a name that cannot be a username.
String? addLinkUsername(String? text) {
  if (text == null) return null;
  final m = RegExp(r'(?:https?://(?:www\.)?gogho\.st/add/|ghostmsg://add/)@?([A-Za-z0-9._]+)/?(?:[?#].*)?$').firstMatch(text.trim());
  if (m == null) return null;
  final name = m.group(1)!.toLowerCase();
  return Me.goodUsername(name) ? name : null;
}

/// The key digits an add-me link carries after `#` (lower case): [keyDigits] to 32 hex digits; null where it carries
/// none (a link from before), or anything else there.
String? addLinkKey(String? text) {
  if (text == null || addLinkUsername(text) == null) return null;
  final t = text.trim(), at = t.indexOf('#');
  if (at < 0) return null;
  final key = t.substring(at + 1).toLowerCase();
  return RegExp('^[0-9a-f]{$keyDigits,32}\$').hasMatch(key) ? key : null;
}
