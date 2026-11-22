/// Someone's add-me link (GMFB-34: "A gogho.st/add/USERNAME link and QR code that opens a friend request"):
/// `https://gogho.st/add/USERNAME`, shown with its QR code in Profile and shared from there. Opened, the app asks
/// whether to send that person a friend request (lib/main.dart); the site's page (site/add) does the same for someone
/// without the app, leading to it.
library;

import '../me/me.dart' show Me;

String addMeLink(String username) => 'https://gogho.st/add/$username';

/// The username an add-me link names ([addMeLink], or the app's own `ghostmsg://add/NAME`), tidied; null for
/// anything else, or a name that cannot be a username.
String? addLinkUsername(String? text) {
  if (text == null) return null;
  final m = RegExp(r'(?:https?://(?:www\.)?gogho\.st/add/|ghostmsg://add/)@?([A-Za-z0-9._]+)/?(?:[?#].*)?$').firstMatch(text.trim());
  if (m == null) return null;
  final name = m.group(1)!.toLowerCase();
  return Me.goodUsername(name) ? name : null;
}
