/// A Figma link's card as the Figma plugin draws it (Matt, 2026-11-02: "Also add a figma plugin", beside the
/// connector's word to the AI: "try to link figma frames with previews where possible"): the frame's own picture,
/// named, with its file's name, where Rich embeds alone shows the file's thumbnail from Figma's oEmbed, and only for a
/// file Figma shares publicly.
///
/// - **Only connected.** With the plugin on and a token kept ([figmaFramesOn]), a Figma link alone on its line (or a
///   list line that is only the link) is asked of Figma's API (client.dart) and drawn by Rich embeds' own card
///   (lib/editor/media/rich_embeds/cards.dart): the frame's name its title, the file's name under it, the frame's
///   picture in the frame's shape, and a tap opens Figma's interactive embed on that frame. Off, or with no token, the
///   card is exactly Rich embeds' as it was, and the plugin asks nothing.
/// - **The same gates.** [FigmaEmbeds] stands in front of the device's embeds (oembed.dart `KeptEmbeds`), so its
///   [EmbedSource.allowed] is theirs: Link previews off or Local only on, the card is the quiet one and nothing is
///   asked of Figma. Local only also holds the plugin itself off, as it holds every plugin that uses the internet.
/// - **Falls back quietly.** A frame Figma will not say (403, 404, 429, no answer) is asked of the oEmbed as Rich embeds
///   asks it, and the card is that one, or the plain one: never an error. Asked again a day later (a 429 when Figma
///   says, and no answer in ten minutes).
/// - **Kept on this device** ([FigmaFrames], under [framesKey]) as the oEmbeds are, the last 300: what a frame is
///   called and where its picture is, five days, since Figma's picture addresses last longer than that; the picture
///   itself is fetched and held as Rich embeds holds any (in memory while the app runs). Disconnecting forgets them.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../editor/media/rich_embeds/oembed.dart' show EmbedSource, OEmbed;
import '../../editor/media/rich_embeds/providers.dart' show EmbedService, RichLink;
import '../host.dart' show onPluginStorage;
import '../registry.dart' show pluginOn, plugins;
import '../types.dart' show PluginHost;
import 'client.dart';
import 'manifest.dart' as figma;

/// The plugin is on and a token is kept: Figma's links are drawn from its API.
bool figmaFramesOn({PluginHost? via}) => pluginOn(figma.manifest) && ((via ?? figma.host).secrets.held(figma.tokenSecret)?.trim().isNotEmpty ?? false);

/// Whether [link] is one the Figma plugin draws now: a Figma file or frame (not a community file), with it on.
bool figmaDraws(RichLink link) => link.service == EmbedService.figma && figmaLinkOf(link) != null && figmaFramesOn();

const int _keep = 300;
const int _freshMs = 5 * 24 * 60 * 60000;
const int _refusedMs = 24 * 60 * 60000;
const int _unreachedMs = 10 * 60000;
const int _busyMs = 5 * 60000;

class _Kept {
  const _Kept({required this.at, this.frame, this.until});

  final int at;
  final FigmaFrame? frame;

  /// A failure's: not asked again before then.
  final int? until;

  bool get failed => frame == null;

  Map<String, Object?> toJson() => <String, Object?>{'at': at, ...?frame?.toJson(), 'until': ?until};

  static _Kept? from(Object? json) {
    if (json is! Map || json['at'] is! num) return null;
    final at = (json['at'] as num).toInt();
    final frame = FigmaFrame.fromJson(json);
    final until = json['until'] is num ? (json['until'] as num).toInt() : null;
    if (frame == null && until == null) return null;
    return _Kept(at: at, frame: frame, until: frame == null ? until : null);
  }
}

/// What Figma said of the links asked, kept on this device under [figma.framesKey].
class FigmaFrames extends ChangeNotifier {
  /// [via] is the host they are kept and asked through; [client] the Figma to ask (the kept token's where null);
  /// [now] the clock, in milliseconds.
  FigmaFrames({PluginHost? via, FigmaClient? Function()? client, int Function()? now})
    : _via = via,
      _client = client,
      _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final PluginHost? _via;
  final FigmaClient? Function()? _client;
  final int Function() _now;
  final Set<String> _asking = <String>{};
  bool _disposed = false;

  PluginHost get _on => _via ?? figma.host;

  /// The last read, kept while the storage answers the same value: a card asks on every draw.
  Object? _seen;
  Map<String, _Kept> _read = const <String, _Kept>{};

  /// Read only: [_put] writes a copy.
  Map<String, _Kept> _all() {
    final Object? raw = _on.storage.get<Object?>(figma.framesKey, null);
    if (raw != null && identical(raw, _seen)) return _read;
    final read = <String, _Kept>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        final kept = _Kept.from(value);
        if (key is String && kept != null) read[key] = kept;
      });
    }
    _seen = raw;
    _read = read;
    return read;
  }

  void _put(String key, _Kept kept) {
    final all = {..._all(), key: kept};
    final entries = all.entries.toList()..sort((a, b) => b.value.at - a.value.at);
    _on.storage.set(figma.framesKey, <String, Object?>{for (final entry in entries.take(_keep)) entry.key: entry.value.toJson()});
  }

  /// What is known of [link], fresh or not.
  FigmaFrame? frameFor(FigmaLink link) => _all()[link.key]?.frame;

  /// Figma was asked about [link] lately and would not say.
  bool failedFor(FigmaLink link) => _all()[link.key]?.failed ?? false;

  /// Whether [link] is being asked now.
  bool askingFor(FigmaLink link) => _asking.contains(link.key);

  /// Asks Figma for [link] where it is not known and fresh, nor refused lately; [failed] is told when Figma would not
  /// say, and the listeners either way.
  void want(FigmaLink link, {VoidCallback? failed}) {
    final key = link.key;
    final entry = _all()[key];
    final now = _now();
    if (entry != null && (entry.failed ? now < (entry.until ?? 0) : now - entry.at < _freshMs)) return;
    if (!_asking.add(key)) return;
    unawaited(_ask(link, failed).whenComplete(() => _asking.remove(key)));
  }

  Future<void> _ask(FigmaLink link, VoidCallback? failed) async {
    final client = (_client ?? () => FigmaClient.kept(via: _via))();
    if (client == null) return;
    try {
      final frame = await client.frame(link);
      if (_disposed) return;
      _put(link.key, _Kept(at: _now(), frame: frame));
    } catch (error) {
      if (_disposed) return;
      // Anything else that went wrong (an answer in a shape no one expected) is no answer: never an error on the card.
      final failure = error is FigmaFailure ? error : const FigmaFailure(figmaUnreachable);
      final now = _now();
      final wait = failure.busy ? (failure.retryAfter?.inMilliseconds.clamp(30000, 3600000) ?? _busyMs) : (failure.status == null ? _unreachedMs : _refusedMs);
      _put(link.key, _Kept(at: now, until: now + wait));
      failed?.call();
    }
    if (!_disposed) notifyListeners();
  }

  /// Forgets what Figma refused, so a new token is asked at once: the page, as a token is kept.
  void forgetFailures() {
    final all = _all();
    final kept = <String, Object?>{
      for (final entry in all.entries)
        if (!entry.value.failed) entry.key: entry.value.toJson(),
    };
    if (kept.length != all.length) _on.storage.set(figma.framesKey, kept);
    if (!_disposed) notifyListeners();
  }

  /// Forgets everything: the page, as the token is let go of.
  void forgetAll() {
    _on.storage.remove(figma.framesKey);
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The frames the app's cards read, one for the app (the plugin's page forgets through it).
final FigmaFrames figmaFrames = FigmaFrames();

/// The device's embeds with the Figma plugin in front of them (see the header): a Figma link it draws is its own,
/// every other link and every other service the embeds' as before.
class FigmaEmbeds extends ChangeNotifier implements EmbedSource {
  /// [base] is the device's embeds; [frames] what Figma said ([figmaFrames] where null); [on] whether the plugin draws
  /// Figma's links ([figmaFramesOn] where null).
  FigmaEmbeds(this.base, {FigmaFrames? frames, bool Function()? on})
    : _frames = frames ?? figmaFrames,
      _onNow = on ?? figmaFramesOn;

  final EmbedSource base;
  final FigmaFrames _frames;
  final bool Function() _onNow;
  bool? _was;
  VoidCallback? _stopStorage;
  Listenable? _registry;

  FigmaLink? _figma(RichLink link) => link.service == EmbedService.figma && _onNow() ? figmaLinkOf(link) : null;

  @override
  bool get allowed => base.allowed;

  @override
  OEmbed? embedFor(RichLink link) {
    final figma = _figma(link);
    if (figma == null) return base.embedFor(link);
    final frame = _frames.frameFor(figma);
    if (frame != null) return embedOfFrame(frame);
    return _frames.failedFor(figma) ? base.embedFor(link) : null;
  }

  @override
  bool failedFor(RichLink link) {
    final figma = _figma(link);
    if (figma == null) return base.failedFor(link);
    if (_frames.frameFor(figma) != null) return false;
    return _frames.failedFor(figma) && base.failedFor(link);
  }

  @override
  void wantEmbed(RichLink link) {
    if (link.service == EmbedService.figma) _remember(link);
    final figma = _figma(link);
    if (figma == null) return base.wantEmbed(link);
    if (!base.allowed) return;
    // Refused lately: the oEmbed, as Rich embeds asks it, while Figma is left alone.
    if (_frames.failedFor(figma) && _frames.frameFor(figma) == null) base.wantEmbed(link);
    _frames.want(figma, failed: () => base.wantEmbed(link));
  }

  @override
  Future<Uint8List?> picture(String address) => base.picture(address);

  // ---- telling the cards ----

  void _told() => notifyListeners();

  /// The Figma links the cards have wanted, the latest last: asked again of whichever now draws them when the plugin
  /// turns on or off, since a card on screen asks only as it is drawn.
  final Set<RichLink> _wanted = <RichLink>{};

  void _remember(RichLink link) {
    _wanted
      ..remove(link)
      ..add(link);
    if (_wanted.length > 64) _wanted.remove(_wanted.first);
  }

  /// The plugin turned on or off, or the token kept or let go of: the cards on screen are asked for again, and every
  /// Figma card draws again.
  void _maybeMoved() {
    final now = _onNow();
    if (now == _was) return;
    _was = now;
    for (final link in [..._wanted]) {
      wantEmbed(link);
    }
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) {
      _was = _onNow();
      base.addListener(_told);
      _frames.addListener(_told);
      _registry = plugins..addListener(_maybeMoved);
      _stopStorage = onPluginStorage(_maybeMoved);
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _stop();
  }

  void _stop() {
    base.removeListener(_told);
    _frames.removeListener(_told);
    _registry?.removeListener(_maybeMoved);
    _registry = null;
    _stopStorage?.call();
    _stopStorage = null;
  }

  @override
  void dispose() {
    if (hasListeners) _stop();
    super.dispose();
  }
}

/// A frame as the card reads an oEmbed: its name the title, its file's name under it, its picture in its shape.
OEmbed embedOfFrame(FigmaFrame frame) => OEmbed(
  title: frame.frame ?? frame.file,
  author: frame.frame == null ? null : frame.file,
  thumbnail: frame.picture,
  thumbnailWidth: frame.picture == null ? null : frame.width,
  thumbnailHeight: frame.picture == null ? null : frame.height,
);
