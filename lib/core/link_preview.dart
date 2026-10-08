/// What a linked page is called, for the card under a link (lib/editor/media/link_cards.dart; Matt: "add link
/// preview cards"). Ports `src/app/core/linkPreview.ts`.
///
/// The page's own HTML is read by the app (`link_preview`, native generation 17 on the page). What comes back is
/// kept, so a card shows its title at once the next time and the site is asked once a week at most. Asking is a
/// request to the linked site, so it only happens for a card on screen, with Link previews on and "Nothing leaves
/// the phone" off.
///
/// What differs:
/// - The module's state (what is kept, what is being asked) is a [KeptLinkPreviews] object, and
///   `LINK_PREVIEW_READY` on `window` is its `notifyListeners`. The cards are written against [LinkPreviewer], so
///   a note drawn where nothing may be asked is given [noLinkPreviews], which knows nothing and asks nothing: the
///   card then says the site and the path, as the page's does in a browser.
/// - The read itself (`invoke('link_preview')`) and the gate (`isTauri`, the two switches, the generation) are
///   seams given to [KeptLinkPreviews]: [LinkPreviewFetch] and `canAsk`. This stage has no network of its own.
/// - `openLink` (the opener plugin, or `window.open`) is the seam [LinkOpener]: the app has no opener yet.
/// - `siteOf` and `pathOf` read the address with Dart's `Uri`, where the page used `URL`. An address with no
///   scheme and host is "not a URL" to both.
library;

import 'dart:async';

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
