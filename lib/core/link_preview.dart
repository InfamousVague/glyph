/// What a linked page is called, for the card under a link (lib/editor/media/link_cards.dart; Matt: "add link
/// preview cards"). Ports `src/app/core/linkPreview.ts`, and the read itself, `src-tauri/src/link_preview.rs`.
///
/// The page's own HTML is read by the app ([linkPreviewFetch]; `link_preview`, native generation 17 on the page).
/// What comes back is kept, so a card shows its title at once the next time and the site is asked once a week at
/// most. Asking is a request to the linked site, so it only happens for a card on screen, with Link previews on and
/// "Nothing leaves the phone" off.
///
/// What differs:
/// - The module's state (what is kept, what is being asked) is a [KeptLinkPreviews] object, and
///   `LINK_PREVIEW_READY` on `window` is its `notifyListeners`. The cards are written against [LinkPreviewer], so
///   a note drawn where nothing may be asked is given [noLinkPreviews], which knows nothing and asks nothing: the
///   card then says the site and the path, as the page's does in a browser.
/// - The gate (`isTauri`, the two switches, the generation) is still a seam given to [KeptLinkPreviews]: `canAsk`.
///   Local only and the Link previews switch are honoured there, as the page honours them in `canAsk`; the read
///   below knows nothing of either. The read is [linkPreviewFetch], a [LinkPreviewFetch] over `dart:io`.
/// - `openLink` (the opener plugin, or `window.open`) is the seam [LinkOpener]: lib/core/open_link.dart is one.
/// - `siteOf` and `pathOf` read the address with Dart's `Uri`, where the page used `URL`. An address with no
///   scheme and host is "not a URL" to both.
/// - THE READ REFUSES PRIVATE ADDRESSES, which the Rust does not: a note's link must not make the phone ask a
///   router, a printer or itself ([isPublicAddress]). The name is resolved here, every address it answers is
///   checked, and the socket is opened to the address that was checked, so a second lookup cannot answer
///   differently. That is done at every hop, so redirects are followed by hand (five, as `Policy::limited(5)`
///   follows; the sixth is a failure), and no `Referer` is sent on the way, where reqwest sends one.
/// - The Rust reads no icon and no charset: the bytes are read as UTF-8 with the bad ones replaced
///   (`from_utf8_lossy`), whatever the page says it is written in. So does this.
/// - `dart:io` asks for gzip and unpacks it, where the Rust's reqwest is built without it; the half megabyte is
///   counted after unpacking. The address answered is Dart's `Uri` as text, which leaves a bare site without the
///   `/` reqwest's `Url` adds; nothing reads it.
/// - An entity is looked for in the next twelve UTF-16 units, where the Rust looks in twelve bytes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'stored.dart';

/// What is known of a linked page.
@immutable
class LinkPreview {
  const LinkPreview({required this.url, this.title, this.site, this.description});

  final String url;
  final String? title;
  final String? site;
  final String? description;

  @override
  bool operator ==(Object other) => other is LinkPreview && other.url == url && other.title == title && other.site == site && other.description == description;

  @override
  int get hashCode => Object.hash(url, title, site, description);

  @override
  String toString() => 'LinkPreview($url, $title, $site, $description)';
}

/// Reads a page's title, site and description (`invoke('link_preview', {url})`). Throws when the site did not
/// answer.
typedef LinkPreviewFetch = Future<LinkPreview> Function(String url);

/// Opens a web address in the phone's browser (`openLink`).
typedef LinkOpener = Future<void> Function(String url);

/// What a link card asks: what is known now, and to be told more. A `Listenable`: it tells its listeners when a
/// preview arrives (`LINK_PREVIEW_READY`).
abstract class LinkPreviewer implements Listenable {
  /// What is known about [url] now, without asking (`previewFor`).
  LinkPreview? previewFor(String url);

  /// Asks for [url]'s preview if it isn't known and fresh, and tells the listeners when it arrives
  /// (`wantPreview`).
  void wantPreview(String url);
}

class _NoLinkPreviews implements LinkPreviewer {
  const _NoLinkPreviews();

  @override
  LinkPreview? previewFor(String url) => null;

  @override
  void wantPreview(String url) {}

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// Knows nothing and asks nothing: a browser's previews, and an older app's.
const LinkPreviewer noLinkPreviews = _NoLinkPreviews();

const String _key = 'glyph-link-previews';
const int _keep = 300;
const int _freshMs = 7 * 24 * 60 * 60000;
const int _retryMs = 24 * 60 * 60000;

final RegExp _www = RegExp(r'^www\.');

Uri? _parsed(String url) {
  final uri = Uri.tryParse(url);
  // `new URL` throws for an address with no scheme; one with a scheme and no host has an empty hostname.
  if (uri == null || !uri.hasScheme) return null;
  return uri;
}

/// A web address's site as a person reads it: `airbnb.com`, without `www.`.
String siteOf(String url) {
  final uri = _parsed(url);
  return uri == null ? url : uri.host.replaceFirst(_www, '');
}

/// The address after the site, short: `/rooms/1234…`, or nothing for a home page.
String pathOf(String url) {
  final uri = _parsed(url);
  if (uri == null) return '';
  final pathname = uri.path.isEmpty ? '/' : uri.path;
  final rest = '${pathname == '/' ? '' : pathname}${uri.hasQuery && uri.query.isNotEmpty ? '?${uri.query}' : ''}';
  return rest.length > 32 ? '${rest.substring(0, 31)}…' : rest;
}

class _Kept {
  _Kept({required this.at, this.title, this.site, this.description, this.failed = false});

  final int at;
  final String? title;
  final String? site;
  final String? description;
  final bool failed;

  Map<String, Object?> toJson() => <String, Object?>{
    if (title != null) 'title': title,
    if (site != null) 'site': site,
    if (description != null) 'description': description,
    'at': at,
    if (failed) 'failed': true,
  };

  static _Kept? from(Object? json) {
    if (json is! Map) return null;
    final at = json['at'];
    if (at is! num) return null;
    String? text(String key) => json[key] is String ? json[key] as String : null;
    return _Kept(at: at.toInt(), title: text('title'), site: text('site'), description: text('description'), failed: json['failed'] == true);
  }
}

/// The previews kept on this device: the page's module, as an object.
class KeptLinkPreviews extends ChangeNotifier implements LinkPreviewer {
  /// [stored] is where they are kept; [fetch] reads a page, or null where nothing can (a browser, an older app);
  /// [canAsk] is the gate, read at each ask: Link previews on and "Nothing leaves the phone" off; [now] is the
  /// clock, in milliseconds.
  KeptLinkPreviews(this._stored, {LinkPreviewFetch? fetch, FutureOr<bool> Function()? canAsk, int Function()? now})
    : _fetch = fetch,
      _canAsk = canAsk ?? (() => true),
      _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Stored _stored;
  final LinkPreviewFetch? _fetch;
  final FutureOr<bool> Function() _canAsk;
  final int Function() _now;

  Map<String, _Kept>? _kept;
  final Set<String> _asking = <String>{};
  bool _disposed = false;

  Map<String, _Kept> _all() => _kept ??= _stored.read<Map<String, _Kept>>(_key, <String, _Kept>{}, (value) {
    if (value is! Map) return null;
    final read = <String, _Kept>{};
    value.forEach((key, entry) {
      final kept = _Kept.from(entry);
      if (key is String && kept != null) read[key] = kept;
    });
    return read;
  });

  /// Not kept, the card still shows the site, and the title is asked again next time.
  void _save() {
    final entries = _all().entries.toList();
    // The most recently asked first; a stable sort, as JavaScript's is.
    final order = <int>[for (var i = 0; i < entries.length; i++) i]
      ..sort((a, b) {
        final by = entries[b].value.at - entries[a].value.at;
        return by != 0 ? by : a - b;
      });
    final kept = <String, _Kept>{for (final i in order.take(_keep)) entries[i].key: entries[i].value};
    _kept = kept;
    _stored.write(_key, <String, Object?>{for (final entry in kept.entries) entry.key: entry.value.toJson()});
  }

  @override
  LinkPreview? previewFor(String url) {
    final entry = _all()[url];
    if (entry == null || entry.failed) return null;
    return LinkPreview(url: url, title: entry.title, site: entry.site, description: entry.description);
  }

  @override
  void wantPreview(String url) {
    final entry = _all()[url];
    if (entry != null && _now() - entry.at < (entry.failed ? _retryMs : _freshMs)) return;
    if (_asking.contains(url)) return;
    _asking.add(url);
    unawaited(_ask(url).whenComplete(() => _asking.remove(url)));
  }

  Future<void> _ask(String url) async {
    final fetch = _fetch;
    if (fetch == null || !await _canAsk()) return;
    try {
      final preview = await fetch(url);
      _all()[url] = _Kept(title: preview.title, site: preview.site, description: preview.description, at: _now());
    } catch (_) {
      _all()[url] = _Kept(at: _now(), failed: true);
    }
    _save();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

// ---- the read itself (src-tauri/src/link_preview.rs) ---------------------------------------------------------------

/// How much of a page is read looking for its head.
const int linkPreviewMaxBytes = 512 * 1024;

/// The longest title or summary kept, in characters.
const int linkPreviewMaxChars = 300;

/// How long the whole read may take: every hop, and the head.
const Duration linkPreviewTimeout = Duration(seconds: 8);

/// How many redirects are followed; one more is a failure.
const int linkPreviewMaxRedirects = 5;

const String linkPreviewUserAgent = 'Mozilla/5.0 (compatible; GlyphLinkPreview/1.0)';
const String linkPreviewAccept = 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.1';

const String _unreached = "The page couldn't be reached.";

/// Why a page was not read, in the Rust's words.
class LinkPreviewError implements Exception {
  const LinkPreviewError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A name's addresses (`InternetAddress.lookup`).
typedef HostResolver = Future<List<InternetAddress>> Function(String host);

/// Whether the read may connect to [address] on [port]. The app's is [isPublicAddress]; a test admits its own
/// server on 127.0.0.1.
typedef AddressAllow = bool Function(InternetAddress address, int port);

bool _publicV4(int a, int b, int c) {
  if (a == 0 || a == 10 || a == 127) return false; // "this network" and unspecified, private, loopback
  if (a == 100 && (b & 0xc0) == 64) return false; // 100.64/10, a carrier's shared space
  if (a == 169 && b == 254) return false; // link-local
  if (a == 172 && b >= 16 && b <= 31) return false; // private
  if (a == 192 && b == 168) return false; // private
  if (a == 192 && b == 0 && c == 0) return false; // 192.0.0/24, protocol assignments
  if (a == 198 && (b == 18 || b == 19)) return false; // 198.18/15, benchmarking
  if (a >= 224) return false; // multicast, reserved, broadcast
  return true;
}

/// Whether [address] is somewhere on the internet, and not this device, its network or nowhere: not loopback,
/// private (10/8, 172.16/12, 192.168/16), link-local (169.254/16, fe80::/10), unique-local (fc00::/7), unspecified
/// or multicast, and not an IPv6 form carrying one of those IPv4 addresses (mapped, compatible, NAT64, 6to4).
bool isPublicAddress(InternetAddress address) {
  final raw = address.rawAddress;
  if (address.type == InternetAddressType.IPv4 && raw.length == 4) return _publicV4(raw[0], raw[1], raw[2]);
  if (address.type != InternetAddressType.IPv6 || raw.length != 16) return false;
  bool zero(int from, int to) {
    for (var i = from; i < to; i++) {
      if (raw[i] != 0) return false;
    }
    return true;
  }

  // ::ffff:a.b.c.d (mapped) and ::a.b.c.d (compatible, which takes in :: and ::1).
  if (zero(0, 10) && ((raw[10] == 0xff && raw[11] == 0xff) || (raw[10] == 0 && raw[11] == 0))) return _publicV4(raw[12], raw[13], raw[14]);
  // 64:ff9b::/96, NAT64 to an IPv4 address, and 64:ff9b:1::/48, its local-use kin.
  if (raw[0] == 0 && raw[1] == 0x64 && raw[2] == 0xff && raw[3] == 0x9b) {
    return zero(4, 12) && _publicV4(raw[12], raw[13], raw[14]);
  }
  // 2002::/16, 6to4: the IPv4 address is the next four bytes.
  if (raw[0] == 0x20 && raw[1] == 0x02) return _publicV4(raw[2], raw[3], raw[4]);
  // 2001::/32, Teredo: a tunnel to an address that is not the one written.
  if (raw[0] == 0x20 && raw[1] == 0x01 && raw[2] == 0 && raw[3] == 0) return false;
  if (raw[0] == 0xfe && (raw[1] & 0x80) == 0x80) return false; // fe80::/10 link-local, fec0::/10 site-local
  if ((raw[0] & 0xfe) == 0xfc) return false; // fc00::/7 unique-local
  if (raw[0] == 0xff) return false; // multicast
  return true;
}

/// The address a preview is asked of: `http` or `https`, with a host. Throws a [LinkPreviewError] in the Rust's
/// words.
Uri linkPreviewAddress(String url) {
  final parsed = Uri.tryParse(url.trim());
  if (parsed == null || !parsed.hasScheme) throw const LinkPreviewError("That isn't a web address.");
  if (parsed.scheme != 'http' && parsed.scheme != 'https') throw const LinkPreviewError('Only web pages have previews.');
  if (parsed.host.isEmpty) throw const LinkPreviewError("That isn't a web address.");
  return parsed;
}

Future<List<InternetAddress>> _lookup(String host) => InternetAddress.lookup(host);

bool _allowPublic(InternetAddress address, int port) => isPublicAddress(address);

const List<int> _redirects = <int>[301, 302, 303, 307, 308];
const List<int> _headClose = <int>[0x3c, 0x2f, 0x68, 0x65, 0x61, 0x64, 0x3e]; // </head>

bool _containsCi(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var same = true;
    for (var j = 0; j < needle.length && same; j++) {
      final byte = haystack[i + j];
      same = (byte >= 0x41 && byte <= 0x5a ? byte + 0x20 : byte) == needle[j];
    }
    if (same) return true;
  }
  return false;
}

/// A [LinkPreviewFetch] over `dart:io`: the page's title, site name and summary, as `link_preview` in Rust reads
/// them. Only `http` and `https`, [maxRedirects] redirects, [timeout] for all of it, and at most the first
/// [maxBytes] of the page, stopping where the head closes. Throws a [LinkPreviewError].
///
/// [resolve] finds a name's addresses and [allow] says which may be connected to; the app leaves both alone
/// (`InternetAddress.lookup`, [isPublicAddress]). Every address a name answers must be allowed, and the socket is
/// opened to the first of them, not to the name.
LinkPreviewFetch linkPreviewFetch({
  HostResolver? resolve,
  AddressAllow? allow,
  Duration timeout = linkPreviewTimeout,
  int maxBytes = linkPreviewMaxBytes,
  int maxRedirects = linkPreviewMaxRedirects,
}) {
  final find = resolve ?? _lookup;
  final may = allow ?? _allowPublic;

  return (url) async {
    var at = linkPreviewAddress(url);
    final clock = Stopwatch()..start();
    Duration left() {
      final rest = timeout - clock.elapsed;
      if (rest <= Duration.zero) throw const LinkPreviewError(_unreached);
      return rest;
    }

    for (var followed = 0; ; followed++) {
      final client = HttpClient();
      try {
        // The address first: the name's own, every one of them somewhere the read may go.
        final literal = InternetAddress.tryParse(at.host);
        final found = literal != null ? <InternetAddress>[literal] : await find(at.host).timeout(left());
        if (found.isEmpty || !found.every((address) => may(address, at.port))) throw const LinkPreviewError(_unreached);
        final checked = found.first;
        // Never through a proxy (dart:io reads the environment's by default): it would do the connecting.
        client.findProxy = (_) => 'DIRECT';
        // To the address that was checked, never to the name again. TLS is made over that socket for the name the
        // address was written with, so the server is named (SNI) and its certificate is held to that name.
        client.connectionFactory = (uri, proxyHost, proxyPort) async {
          final task = await Socket.startConnect(checked, uri.port);
          if (uri.scheme != 'https') return task;
          return ConnectionTask.fromSocket<Socket>(task.socket.then<Socket>((socket) => SecureSocket.secure(socket, host: uri.host)), task.cancel);
        };
        final request = await client.getUrl(at).timeout(left());
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, linkPreviewUserAgent);
        request.headers.set(HttpHeaders.acceptHeader, linkPreviewAccept);
        final response = await request.close().timeout(left());

        final location = response.headers[HttpHeaders.locationHeader]?.first;
        if (_redirects.contains(response.statusCode) && location != null) {
          if (followed >= maxRedirects) throw const LinkPreviewError(_unreached);
          final next = at.resolve(location);
          if ((next.scheme != 'http' && next.scheme != 'https') || next.host.isEmpty) throw const LinkPreviewError(_unreached);
          at = next;
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) throw LinkPreviewError('The page answered ${response.statusCode}.');

        final type = response.headers[HttpHeaders.contentTypeHeader]?.first;
        var preview = LinkPreview(url: at.toString());
        if (type == null || type.contains('html')) {
          preview = readHead(await _head(response, maxBytes, () => timeout - clock.elapsed), at.toString());
        }
        if (preview.site != null) return preview;
        var site = at.host.contains(':') ? '[${at.host}]' : at.host;
        while (site.startsWith('www.')) {
          site = site.substring(4);
        }
        return LinkPreview(url: preview.url, title: preview.title, site: site, description: preview.description);
      } on LinkPreviewError {
        rethrow;
      } catch (_) {
        // No such name, no route, a refused connection, a certificate that is not the site's, or too slow.
        throw const LinkPreviewError(_unreached);
      } finally {
        client.close(force: true);
      }
    }
  };
}

/// The start of a page, as text: up to [maxBytes] of it, or to where the head closes, or to where the time ran out
/// or the connection broke; what had come by then is read.
Future<String> _head(HttpClientResponse response, int maxBytes, Duration Function() left) async {
  final body = BytesBuilder(copy: true);
  var tail = const <int>[];
  final chunks = StreamIterator<List<int>>(response);
  try {
    while (body.length < maxBytes) {
      final rest = left();
      if (rest <= Duration.zero || !await chunks.moveNext().timeout(rest)) break;
      final chunk = chunks.current;
      body.add(chunk);
      // The head is all that's wanted: stop once it has closed. The close may lie across two chunks.
      final seam = <int>[...tail, ...chunk];
      if (_containsCi(seam, _headClose)) break;
      tail = seam.length > _headClose.length - 1 ? seam.sublist(seam.length - (_headClose.length - 1)) : seam;
    }
  } catch (_) {
    // As the Rust's `Err(_) => break`.
  }
  unawaited(chunks.cancel().catchError((Object _) {}));
  final bytes = body.takeBytes();
  return utf8.decode(bytes.length > maxBytes ? Uint8List.sublistView(bytes, 0, maxBytes) : bytes, allowMalformed: true);
}

int? _findCi(String haystack, String needle, [int from = 0]) {
  for (var i = from; i + needle.length <= haystack.length; i++) {
    var same = true;
    for (var j = 0; j < needle.length && same; j++) {
      final unit = haystack.codeUnitAt(i + j);
      same = (unit >= 0x41 && unit <= 0x5a ? unit + 0x20 : unit) == needle.codeUnitAt(j);
    }
    if (same) return i;
  }
  return null;
}

/// Rust's `char::is_whitespace`: Unicode's White_Space.
bool _isSpace(int unit) =>
    (unit >= 0x09 && unit <= 0x0d) || unit == 0x20 || unit == 0x85 || unit == 0xa0 || unit == 0x1680 || (unit >= 0x2000 && unit <= 0x200a) || unit == 0x2028 || unit == 0x2029 || unit == 0x202f || unit == 0x205f || unit == 0x3000;

/// What a page's head says about it: `og:`/`twitter:` tags first, then `<title>` and the meta description
/// (`read_head`). [url] is the address the answer carries.
LinkPreview readHead(String html, String url) {
  final end = _findCi(html, '</head>');
  final head = end == null ? html : html.substring(0, end);
  String? ogTitle, ogSite, ogDescription, description, twitterTitle;
  var rest = head;
  for (var at = _findCi(rest, '<meta'); at != null; at = _findCi(rest, '<meta')) {
    final after = rest.substring(at + 5);
    final close = tagEnd(after);
    final attrs = tagAttributes(after.substring(0, close));
    String? key, content;
    for (final (name, value) in attrs) {
      if (key == null && (name == 'property' || name == 'name')) key = _asciiLower(value);
      if (content == null && name == 'content') content = _clean(value);
    }
    if (key != null && content != null && content.isNotEmpty) {
      switch (key) {
        case 'og:title':
          ogTitle ??= content;
        case 'og:site_name':
          ogSite ??= content;
        case 'og:description':
          ogDescription ??= content;
        case 'description':
          description ??= content;
        case 'twitter:title':
          twitterTitle ??= content;
      }
    }
    rest = after.substring(close);
  }
  String? titleTag;
  final titleAt = _findCi(head, '<title');
  if (titleAt != null) {
    final after = head.substring(titleAt + 6);
    final open = after.indexOf('>') + 1;
    final close = open == 0 ? null : _findCi(after, '</title', open);
    if (close != null) titleTag = _clean(after.substring(open, close));
  }
  final title = ogTitle ?? twitterTitle ?? titleTag;
  return LinkPreview(url: url, title: title == null || title.isEmpty ? null : title, site: ogSite, description: ogDescription ?? description);
}

String _asciiLower(String text) => text.replaceAllMapped(RegExp('[A-Z]'), (match) => match[0]!.toLowerCase());

/// Where a tag's `>` is, outside quotes (`tag_end`); the text's length for a tag that never closes.
@visibleForTesting
int tagEnd(String text) {
  int? quote;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (quote == null) {
      if (unit == 0x22 || unit == 0x27) {
        quote = unit;
      } else if (unit == 0x3e) {
        return i;
      }
    } else if (unit == quote) {
      quote = null;
    }
  }
  return text.length;
}

/// A tag's attributes, names lower-cased (`attributes`).
@visibleForTesting
List<(String, String)> tagAttributes(String text) {
  final out = <(String, String)>[];
  const slash = 0x2f, equals = 0x3d;
  int? unit(int i) => i < text.length ? text.codeUnitAt(i) : null;
  bool space(int i) => i < text.length && _isSpace(text.codeUnitAt(i));
  var i = 0;
  while (i < text.length) {
    while (space(i) || unit(i) == slash) {
      i++;
    }
    final start = i;
    while (i < text.length && !space(i) && unit(i) != equals && unit(i) != slash) {
      i++;
    }
    final name = _asciiLower(text.substring(start, i));
    while (space(i)) {
      i++;
    }
    var value = '';
    if (unit(i) == equals) {
      i++;
      while (space(i)) {
        i++;
      }
      final quote = unit(i);
      if (quote == 0x22 || quote == 0x27) {
        i++;
        final from = i;
        while (i < text.length && unit(i) != quote) {
          i++;
        }
        value = text.substring(from, i);
        i++;
      } else {
        final from = i;
        while (i < text.length && !space(i)) {
          i++;
        }
        value = text.substring(from, i);
      }
    }
    if (name.isNotEmpty) {
      out.add((name, value));
    } else if (i == start) {
      i++;
    }
  }
  return out;
}

/// Entities decoded, whitespace collapsed, and the length capped (`clean`).
String _clean(String text) {
  final decoded = decodeEntities(text);
  final words = <String>[];
  var from = -1;
  for (var i = 0; i <= decoded.length; i++) {
    final gap = i == decoded.length || _isSpace(decoded.codeUnitAt(i));
    if (!gap && from < 0) from = i;
    if (gap && from >= 0) {
      words.add(decoded.substring(from, i));
      from = -1;
    }
  }
  final collapsed = words.join(' ');
  final runes = collapsed.runes;
  if (runes.length <= linkPreviewMaxChars) return collapsed;
  return '${String.fromCharCodes(runes.take(linkPreviewMaxChars - 1)).trimRight()}…';
}

const Map<String, String> _entities = <String, String>{
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  '#39': "'",
  'nbsp': ' ',
  'mdash': '—',
  'ndash': '–',
  'hellip': '…',
};

final RegExp _hexDigits = RegExp(r'^\+?[0-9a-fA-F]+$');
final RegExp _digits = RegExp(r'^\+?[0-9]+$');

/// A numbered entity's character: a Unicode scalar value, as `char::from_u32` allows.
String? _numbered(String digits, int radix) {
  if (!(radix == 16 ? _hexDigits : _digits).hasMatch(digits)) return null;
  final code = int.tryParse(digits.replaceFirst('+', ''), radix: radix);
  if (code == null || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)) return null;
  return String.fromCharCode(code);
}

/// `&amp;` and its kin, and the numbered ones; what is not an entity is left as it was (`decode_entities`).
@visibleForTesting
String decodeEntities(String text) {
  final out = StringBuffer();
  var rest = text;
  for (var at = rest.indexOf('&'); at >= 0; at = rest.indexOf('&')) {
    out.write(rest.substring(0, at));
    final tail = rest.substring(at);
    final semi = tail.substring(0, tail.length < 12 ? tail.length : 12).indexOf(';');
    String? decoded;
    if (semi >= 0) {
      final name = tail.substring(1, semi);
      decoded = _entities[name];
      if (decoded == null && (name.startsWith('#x') || name.startsWith('#X'))) {
        decoded = _numbered(name.substring(2), 16);
      } else if (decoded == null && name.startsWith('#')) {
        decoded = _numbered(name.substring(1), 10);
      }
    }
    if (decoded == null) {
      out.write('&');
      rest = tail.substring(1);
    } else {
      out.write(decoded);
      rest = tail.substring(semi + 1);
    }
  }
  out.write(rest);
  return out.toString();
}
