/// A link's address, shortened for showing: `notion.so/att…b3c`. A port of `src/app/core/shortUrl.ts`, one to one.
///
/// Matt: "don't show the full link path just show the first 3 chars after the tld then a ... and the last 3 chars".
/// Pure, used wherever an address is shown: the editor's links, the recorder's words and the list's titles.
///
/// What differs: nothing.
library;

import 'item_syntax.dart' show jsTrim;

final RegExp _scheme = RegExp(r'^[a-z][a-z0-9+.-]*:\/\/', caseSensitive: false);
final RegExp _www = RegExp(r'^www\.', caseSensitive: false);
final RegExp _pathStart = RegExp(r'[/?#]');
final RegExp _leadingSlashes = RegExp(r'^\/+');
final RegExp _trailingSlashes = RegExp(r'\/+$');

/// The short form of [url]: the host without `www.`, then the first three and the last three characters of what
/// follows the host. A short path is kept whole, since shortening it would save nothing.
String shortUrl(String url) {
  final bare = jsTrim(url).replaceFirst(_scheme, '').replaceFirst(_www, '');
  final cut = bare.indexOf(_pathStart);
  final host = cut < 0 ? bare : bare.substring(0, cut);
  final rest = (cut < 0 ? '' : bare.substring(cut)).replaceFirst(_leadingSlashes, '').replaceFirst(_trailingSlashes, '');
  if (rest.isEmpty) return host;
  if (rest.length <= 9) return '$host/$rest';
  return '$host/${rest.substring(0, 3)}…${rest.substring(rest.length - 3)}';
}

final RegExp _address = RegExp(r'\bhttps?:\/\/[^\s)\]>]+', caseSensitive: false);

/// Every http(s) address in running [text], shortened.
String shortenUrls(String text) => text.replaceAllMapped(_address, (m) => shortUrl(m.group(0)!));
