/// The links a rich embed is drawn for (Matt: "Rich embeds: YouTube, Spotify and Figma links as playable or
/// previewable cards, not just link cards"), read from the address alone: which service, which video, track or
/// file, where a video starts, and the three addresses each card asks of it (what it is called, its player, and
/// where "Open in …" goes).
///
///     https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1m30s
///     https://youtu.be/dQw4w9WgXcQ?t=90
///     https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC
///     spotify:album:1DFixLWuPkv3KT3TnV35m3
///     https://www.figma.com/design/abcDEF1234567890ghij/Home?node-id=1-2
///
/// The web app has no counterpart: its link cards (link_cards.dart) are the plain ones. Nothing here asks the
/// network; that is oembed.dart's, behind Link previews and Local only.
library;

import 'package:flutter/foundation.dart';

/// The services a link may be a rich embed of.
enum EmbedService { youtube, spotify, figma }

/// A link one of the services plays or shows, as the card needs it.
@immutable
class RichLink {
  const RichLink({required this.service, required this.id, required this.kind, required this.source, this.start});

  final EmbedService service;

  /// The video's eleven characters, the Spotify item's twenty-two, or the Figma file's key.
  final String id;

  /// What it is on its service: `video` or `short`; `track`, `album`, `playlist`, `episode` or `show`; `file`,
  /// `design`, `proto` or `board`.
  final String kind;

  /// The address as the note has it.
  final String source;

  /// Where a video starts, in seconds, from its `t=` or `start=`; null from the beginning.
  final int? start;

  /// The service's name, as its own button says it.
  String get serviceName => switch (service) {
    EmbedService.youtube => 'YouTube',
    EmbedService.spotify => 'Spotify',
    EmbedService.figma => 'Figma',
  };

  /// What it is, in a word, for the card's quiet line.
  String get kindName => switch (kind) {
    'video' => 'Video',
    'short' => 'Short',
    'track' => 'Track',
    'album' => 'Album',
    'playlist' => 'Playlist',
    'episode' => 'Episode',
    'show' => 'Podcast',
    'proto' => 'Prototype',
    'board' => 'FigJam board',
    'community' => 'Community file',
    _ => 'Design',
  };

  /// Played in its card (a video, a song), or opened over the app (a Figma file, which wants the room).
  bool get playsInline => service != EmbedService.figma;

  /// The address the service's own page is: what "Open in …" hands the phone, and what the oEmbed is asked of.
  /// A `spotify:` URI becomes its `open.spotify.com` page, which the phone gives to Spotify where it is installed.
  String get openUrl => switch (service) {
    EmbedService.youtube => source.startsWith('http') ? source : 'https://www.youtube.com/watch?v=$id',
    EmbedService.spotify => 'https://open.spotify.com/$kind/$id',
    EmbedService.figma => source,
  };

  /// What the service is asked for the title, the author and the picture.
  Uri get oEmbed => switch (service) {
    EmbedService.youtube => Uri.https('www.youtube.com', '/oembed', <String, String>{'url': 'https://www.youtube.com/watch?v=$id', 'format': 'json'}),
    EmbedService.spotify => Uri.https('open.spotify.com', '/oembed', <String, String>{'url': 'https://open.spotify.com/$kind/$id'}),
    EmbedService.figma => Uri.https('www.figma.com', '/api/oembed', <String, String>{'url': source}),
  };

  /// The service's own player, which a tap loads: YouTube's without its cookies, playing at once (the tap was the
  /// person's asking), inline and from its start; Spotify's; Figma's interactive one.
  Uri get player => switch (service) {
    EmbedService.youtube => Uri.https('www.youtube-nocookie.com', '/embed/$id', <String, String>{
      'autoplay': '1',
      'playsinline': '1',
      'rel': '0',
      'start': ?(start == null ? null : '$start'),
    }),
    EmbedService.spotify => Uri.https('open.spotify.com', '/embed/$kind/$id', <String, String>{'utm_source': 'oembed'}),
    EmbedService.figma => Uri.https('www.figma.com', '/embed', <String, String>{'embed_host': 'ghostmd', 'url': source}),
  };

  /// The picture a card can ask for before the oEmbed answers: a YouTube video's own still.
  String? get stillGuess => service == EmbedService.youtube ? 'https://i.ytimg.com/vi/$id/hqdefault.jpg' : null;

  /// How tall Spotify's player is, in logical pixels: its compact height for one song or episode, its taller one
  /// with the list for the rest. Null for the others, which keep their own shape.
  double? get playerHeight => service != EmbedService.spotify ? null : (kind == 'track' || kind == 'episode' ? 152 : 352);

  /// What it is kept under: one video, one Spotify item, one Figma address.
  String get key => oEmbed.toString();

  @override
  bool operator ==(Object other) => other is RichLink && other.service == service && other.id == id && other.kind == kind && other.source == source && other.start == start;

  @override
  int get hashCode => Object.hash(service, id, kind, source, start);

  @override
  String toString() => 'RichLink(${service.name}, $kind, $id${start == null ? '' : ', from $start s'})';
}

final RegExp _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
final RegExp _spotifyId = RegExp(r'^[A-Za-z0-9]{22}$');
final RegExp _figmaKey = RegExp(r'^[A-Za-z0-9]{10,128}$');
final RegExp _intl = RegExp(r'^intl-[a-z]{2}(?:[-_][a-zA-Z]{2})?$');
const Set<String> _spotifyKinds = <String>{'track', 'album', 'playlist', 'episode', 'show'};
const Set<String> _figmaKinds = <String>{'file', 'design', 'proto', 'board'};
const Set<String> _youtubeHosts = <String>{'youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com', 'youtube-nocookie.com', 'www.youtube-nocookie.com'};
const Set<String> _youtubePaths = <String>{'shorts', 'embed', 'live', 'v'};

/// The rich embed `url` is, or null for any other address.
RichLink? richLinkOf(String url) {
  final text = url.trim();
  if (text.startsWith('spotify:')) return _spotifyUri(text);
  final uri = Uri.tryParse(text);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase();
  final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (host == 'youtu.be') return parts.isEmpty ? null : _video(parts.first, 'video', uri, text);
  if (_youtubeHosts.contains(host)) {
    if (parts.length == 1 && parts.first == 'watch') return _video(uri.queryParameters['v'] ?? '', 'video', uri, text);
    if (parts.length >= 2 && _youtubePaths.contains(parts.first)) return _video(parts[1], parts.first == 'shorts' ? 'short' : 'video', uri, text);
    return null;
  }
  if (host == 'open.spotify.com') {
    var at = 0;
    if (at < parts.length && _intl.hasMatch(parts[at])) at++;
    if (at < parts.length && parts[at] == 'embed') at++;
    if (parts.length - at < 2) return null;
    return _spotify(parts[at], parts[at + 1], text);
  }
  if (host == 'figma.com' || host == 'www.figma.com') {
    // A community file (`/community/file/<number>/<name>`): Figma's oEmbed refuses it ("Not a Figma URL"), but its
    // embed opens it, so it is a Figma card all the same, its words the page's own (cards.dart).
    if (parts.length >= 3 && parts[0] == 'community' && parts[1] == 'file' && _figmaKey.hasMatch(parts[2])) {
      return RichLink(service: EmbedService.figma, id: parts[2], kind: 'community', source: uri.replace(scheme: 'https').toString());
    }
    if (parts.length < 2 || !_figmaKinds.contains(parts.first) || !_figmaKey.hasMatch(parts[1])) return null;
    return RichLink(service: EmbedService.figma, id: parts[1], kind: parts.first, source: uri.replace(scheme: 'https').toString());
  }
  return null;
}

RichLink? _video(String id, String kind, Uri uri, String source) {
  if (!_videoId.hasMatch(id)) return null;
  // `t=` in the query or after a `#`, then `start=`, as YouTube's own share and embed links write it.
  final fragment = uri.fragment.startsWith('t=') ? uri.fragment.substring(2) : null;
  final start = startSeconds(uri.queryParameters['t'] ?? fragment ?? uri.queryParameters['start']);
  return RichLink(service: EmbedService.youtube, id: id, kind: kind, source: source, start: start);
}

RichLink? _spotify(String kind, String id, String source) {
  if (!_spotifyKinds.contains(kind) || !_spotifyId.hasMatch(id)) return null;
  return RichLink(service: EmbedService.spotify, id: id, kind: kind, source: source);
}

/// `spotify:track:<id>`, and the old `spotify:user:<name>:playlist:<id>`.
RichLink? _spotifyUri(String text) {
  final parts = text.split(':');
  if (parts.length == 3) return _spotify(parts[1], parts[2], text);
  if (parts.length == 5 && parts[1] == 'user') return _spotify(parts[3], parts[4], text);
  return null;
}

final RegExp _clock = RegExp(r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s?)?$');

/// A start time as YouTube writes it, in seconds: `90`, `90s`, `1m30s`, `1h2m3s`. Null for none, for nothing it
/// can read, and for the very start.
@visibleForTesting
int? startSeconds(String? said) {
  if (said == null || said.isEmpty) return null;
  final found = _clock.firstMatch(said.toLowerCase());
  if (found == null || found.group(0)!.isEmpty) return null;
  final hours = int.tryParse(found.group(1) ?? '') ?? 0;
  final minutes = int.tryParse(found.group(2) ?? '') ?? 0;
  final seconds = int.tryParse(found.group(3) ?? '') ?? 0;
  final total = hours * 3600 + minutes * 60 + seconds;
  return total > 0 ? total : null;
}
