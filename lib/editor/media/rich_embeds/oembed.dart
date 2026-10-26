/// What a rich embed's service says of it (oEmbed: the title, who made it, and its picture), and the picture
/// itself, asked of YouTube, Spotify and Figma by the app and kept on this device as a link card's title is
/// (lib/core/link_preview.dart): a week, a day after a failure, the last 300.
///
/// Asking is a request to the service, so it only happens for a card on screen, with Link previews on and "Nothing
/// leaves the phone" off: [KeptEmbeds.allowed] is that gate, read at each ask, and the cards read it too, drawing a
/// quiet card that asks nothing and plays nothing while it is shut. [noEmbeds] knows nothing, asks nothing and is
/// always shut: an editor not told of the device's.
///
/// The read is `dart:io`'s [HttpClient], as the app's other reads are ([httpEmbedGet]): `https` only, eight
/// seconds, a quarter of a megabyte for an answer and two for a picture. The addresses are the services' own
/// (providers.dart builds them), and a picture's is what the service answered, never anything the note wrote.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../../account/api.dart' show FetchRequest, ioFetcher;
import '../../../core/stored.dart';
import 'providers.dart';

/// What a service says of a link: its oEmbed, the parts a card shows.
@immutable
class OEmbed {
  const OEmbed({this.title, this.author, this.thumbnail, this.thumbnailWidth, this.thumbnailHeight});

  /// The video's, song's or file's name.
  final String? title;

  /// Who made it: a YouTube channel, a Figma file's owner (Spotify says no one).
  final String? author;

  /// The address of its picture.
  final String? thumbnail;
  final double? thumbnailWidth;
  final double? thumbnailHeight;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': ?title,
    'author': ?author,
    'thumbnail': ?thumbnail,
    'tw': ?thumbnailWidth,
    'th': ?thumbnailHeight,
  };

  @override
  bool operator ==(Object other) =>
      other is OEmbed && other.title == title && other.author == author && other.thumbnail == thumbnail && other.thumbnailWidth == thumbnailWidth && other.thumbnailHeight == thumbnailHeight;

  @override
  int get hashCode => Object.hash(title, author, thumbnail, thumbnailWidth, thumbnailHeight);

  @override
  String toString() => 'OEmbed($title, $author, $thumbnail)';
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double? _number(Object? value) => switch (value) {
  final num n when n > 0 => n.toDouble(),
  final String s => (double.tryParse(s) ?? 0) > 0 ? double.parse(s) : null,
  _ => null,
};

/// An oEmbed answer read: `title`, `author_name`, `thumbnail_url` and its size, as all three services write them.
/// Null for anything that is not a JSON object, and for one that says neither a title nor a picture. A picture's
/// address that is not `https` is dropped.
OEmbed? parseOEmbed(String body) {
  Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (json is! Map) return null;
  final thumbnail = _text(json['thumbnail_url']);
  final picture = thumbnail != null && Uri.tryParse(thumbnail)?.scheme == 'https' ? thumbnail : null;
  final title = _text(json['title']);
  if (title == null && picture == null) return null;
  return OEmbed(
    title: title,
    author: _text(json['author_name']),
    thumbnail: picture,
    thumbnailWidth: picture == null ? null : _number(json['thumbnail_width']),
    thumbnailHeight: picture == null ? null : _number(json['thumbnail_height']),
  );
}

/// What a service answered: its status and the bytes of its body.
typedef EmbedAnswer = ({int status, Uint8List body});

/// One GET of an address. Throws when nothing answered.
typedef EmbedGet = Future<EmbedAnswer> Function(Uri address, {int maxBytes});

/// Asks a service for a link's oEmbed. Throws when it did not answer, or answered nothing a card can show.
typedef OEmbedFetch = Future<OEmbed> Function(RichLink link);

/// Reads a picture's bytes. Throws when it could not be read.
typedef PictureFetch = Future<Uint8List> Function(String address);

/// Why an embed was not read.
class EmbedError implements Exception {
  const EmbedError(this.message);

  final String message;

  @override
  String toString() => message;
}

const String embedUserAgent = 'Mozilla/5.0 (compatible; GhostMdEmbeds/1.0)';
const Duration embedTimeout = Duration(seconds: 8);
const int oEmbedMaxBytes = 256 * 1024;
const int pictureMaxBytes = 2 * 1024 * 1024;

/// An [EmbedGet] over `dart:io`: `https` only (and `http` where [allowHttp] says, for a test's own server), redirects
/// followed as dart:io follows them, [timeout] for all of it, and at most `maxBytes` of the body.
EmbedGet httpEmbedGet({HttpClient? client, Duration timeout = embedTimeout, bool allowHttp = false}) {
  return (address, {int maxBytes = oEmbedMaxBytes}) async {
    if (address.scheme != 'https' && !(allowHttp && address.scheme == 'http')) throw const EmbedError('Only https is asked.');
    // In the web build, the browser's `fetch`: a service that does not let this site in is one not reached.
    if (kIsWeb) {
      try {
        final answer = await ioFetcher()(FetchRequest(method: 'GET', url: address, timeout: timeout));
        if (answer.bytes.length > maxBytes) throw const EmbedError('Too much came back.');
        return (status: answer.status, body: answer.bytes);
      } on EmbedError {
        rethrow;
      } catch (_) {
        throw const EmbedError("The service couldn't be reached.");
      }
    }
    final http = client ?? HttpClient();
    try {
      return await () async {
        final request = await http.getUrl(address);
        request.headers.set(HttpHeaders.userAgentHeader, embedUserAgent);
        final response = await request.close();
        final body = BytesBuilder(copy: false);
        await for (final chunk in response) {
          body.add(chunk);
          if (body.length > maxBytes) throw const EmbedError('Too much came back.');
        }
        return (status: response.statusCode, body: body.takeBytes());
      }().timeout(timeout);
    } on EmbedError {
      rethrow;
    } catch (_) {
      throw const EmbedError("The service couldn't be reached.");
    } finally {
      if (client == null) http.close(force: true);
    }
  };
}

/// An [OEmbedFetch] over [get] (dart:io's by default): the link's oEmbed address asked, a 2xx answer read.
OEmbedFetch oEmbedFetch({EmbedGet? get}) {
  final ask = get ?? httpEmbedGet();
  return (link) async {
    final answer = await ask(link.oEmbed, maxBytes: oEmbedMaxBytes);
    if (answer.status < 200 || answer.status >= 300) throw EmbedError('The service answered ${answer.status}.');
    final read = parseOEmbed(utf8.decode(answer.body, allowMalformed: true));
    if (read == null) throw const EmbedError('The service said nothing to show.');
    return read;
  };
}

/// A [PictureFetch] over [get] (dart:io's by default): `https` only, a 2xx answer's bytes.
PictureFetch pictureFetch({EmbedGet? get}) {
  final ask = get ?? httpEmbedGet();
  return (address) async {
    final uri = Uri.tryParse(address);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) throw const EmbedError('Only https is asked.');
    final answer = await ask(uri, maxBytes: pictureMaxBytes);
    if (answer.status < 200 || answer.status >= 300 || answer.body.isEmpty) throw EmbedError('The picture answered ${answer.status}.');
    return answer.body;
  };
}

/// What a rich card asks: whether anything may be asked or played at all, what is known now, to be told more, and
/// a picture.
abstract class EmbedSource implements Listenable {
  /// Link previews on and "Nothing leaves the phone" off: the card may ask, show the service's picture, and play.
  bool get allowed;

  /// What is known of [link] now, without asking.
  OEmbed? embedFor(RichLink link);

  /// Whether the service was asked about [link] lately and did not answer: the card is then the plain one.
  bool failedFor(RichLink link);

  /// Asks for [link]'s oEmbed if it is not known and fresh, and tells the listeners when it arrives.
  void wantEmbed(RichLink link);

  /// The picture at [address], kept in memory while the app runs; null where it may not be asked or failed.
  Future<Uint8List?> picture(String address);
}

class _NoEmbeds implements EmbedSource {
  const _NoEmbeds();

  @override
  bool get allowed => false;

  @override
  OEmbed? embedFor(RichLink link) => null;

  @override
  bool failedFor(RichLink link) => false;

  @override
  void wantEmbed(RichLink link) {}

  @override
  Future<Uint8List?> picture(String address) => Future<Uint8List?>.value();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// Knows nothing, asks nothing, and plays nothing: an editor not told of the device's embeds.
const EmbedSource noEmbeds = _NoEmbeds();

const String _key = 'glyph-rich-embeds';
const int _keep = 300;
const int _freshMs = 7 * 24 * 60 * 60000;
const int _retryMs = 24 * 60 * 60000;
const int _picturesHeld = 32;

class _Kept {
  _Kept({required this.at, this.embed, this.failed = false});

  final int at;
  final OEmbed? embed;
  final bool failed;

  Map<String, Object?> toJson() => <String, Object?>{...?embed?.toJson(), 'at': at, if (failed) 'failed': true};

  static _Kept? from(Object? json) {
    if (json is! Map) return null;
    final at = json['at'];
    if (at is! num) return null;
    if (json['failed'] == true) return _Kept(at: at.toInt(), failed: true);
    String? text(String key) => json[key] is String ? json[key] as String : null;
    double? size(String key) => json[key] is num ? (json[key] as num).toDouble() : null;
    return _Kept(at: at.toInt(), embed: OEmbed(title: text('title'), author: text('author'), thumbnail: text('thumbnail'), thumbnailWidth: size('tw'), thumbnailHeight: size('th')));
  }
}

/// The embeds kept on this device.
class KeptEmbeds extends ChangeNotifier implements EmbedSource {
  /// [stored] is where they are kept; [fetch] asks a service, or null where nothing may; [pictures] reads a
  /// picture; [allowed] is the gate, read at each ask and by each card; [now] is the clock, in milliseconds.
  KeptEmbeds(this._stored, {OEmbedFetch? fetch, PictureFetch? pictures, bool Function()? allowed, int Function()? now})
    : _fetch = fetch,
      _pictures = pictures,
      _allowed = allowed ?? (() => true),
      _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Stored _stored;
  final OEmbedFetch? _fetch;
  final PictureFetch? _pictures;
  final bool Function() _allowed;
  final int Function() _now;

  Map<String, _Kept>? _kept;
  final Set<String> _asking = <String>{};
  final LinkedHashMap<String, Future<Uint8List?>> _held = LinkedHashMap<String, Future<Uint8List?>>();
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

  void _save() {
    final entries = _all().entries.toList()..sort((a, b) => b.value.at - a.value.at);
    final kept = <String, _Kept>{for (final entry in entries.take(_keep)) entry.key: entry.value};
    _kept = kept;
    _stored.write(_key, <String, Object?>{for (final entry in kept.entries) entry.key: entry.value.toJson()});
  }

  @override
  bool get allowed => _fetch != null && _allowed();

  @override
  OEmbed? embedFor(RichLink link) => _all()[link.key]?.embed;

  @override
  bool failedFor(RichLink link) => _all()[link.key]?.failed ?? false;

  @override
  void wantEmbed(RichLink link) {
    final key = link.key;
    final entry = _all()[key];
    if (entry != null && _now() - entry.at < (entry.failed ? _retryMs : _freshMs)) return;
    if (_asking.contains(key)) return;
    _asking.add(key);
    unawaited(_ask(link).whenComplete(() => _asking.remove(key)));
  }

  Future<void> _ask(RichLink link) async {
    final fetch = _fetch;
    if (fetch == null || !_allowed()) return;
    try {
      final embed = await fetch(link);
      _all()[link.key] = _Kept(at: _now(), embed: embed);
    } catch (_) {
      _all()[link.key] = _Kept(at: _now(), failed: true);
    }
    _save();
    if (!_disposed) notifyListeners();
  }

  @override
  Future<Uint8List?> picture(String address) {
    final read = _pictures;
    if (read == null || !_allowed()) return Future<Uint8List?>.value();
    final had = _held.remove(address);
    if (had != null) {
      // The most recently drawn last: the first is the one let go.
      _held[address] = had;
      return had;
    }
    final asked = read(address).then<Uint8List?>((bytes) => bytes, onError: (Object _) {
      _held.remove(address);
      return null;
    });
    _held[address] = asked;
    while (_held.length > _picturesHeld) {
      _held.remove(_held.keys.first);
    }
    return asked;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
