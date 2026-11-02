/// Figma's REST API as the plugin asks it, at `api.figma.com`, with the person's own personal access token in an
/// `X-Figma-Token` header (Matt, 2026-11-02: "Also add a figma plugin"). What it was written against is Figma's own
/// reference (developers.figma.com, REST API: users, files, images; not opened while this was written).
///
/// - **Which frame.** A link's `node-id` is written with a hyphen (`?node-id=12-34`, `I5-6;7-8` for an instance's
///   layer) and the API wants the colon (`12:34`): [figmaLinkOf] reads it so, from any of the four kinds of Figma
///   address Rich embeds draws (design, file, proto, board), a branch's own key where the address names one. A
///   community file is not the person's to read through the API, and is left to Rich embeds.
/// - **Three calls for a card, two at most at once.** A frame: `GET /v1/files/:key/nodes?ids=…&depth=1`, its name, its
///   size and the file's name, then `GET /v1/images/:key?ids=…&format=png&scale=…`, its picture, at a scale that keeps
///   it about as wide as a card is drawn (and never past 2), so a long page is not two megabytes of PNG. A file
///   without a frame: `GET /v1/files/:key?depth=1`, its name and thumbnail. Figma's picture addresses last a while
///   (frames.dart asks again well before), and are fetched as Rich embeds fetches any picture.
/// - **Whose token.** `GET /v1/me`, which changes nothing, for the plugin's page.
/// - **Failures are kept short.** A 403 (a token Figma does not know, or a file it may not read), a 404, a 429 with its
///   `Retry-After`, and no answer at all are each a [FigmaFailure]: the card goes back to Rich embeds' quietly, and
///   the page says the token's in words.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../account/api.dart' show FetchRequest, FetchResponse;
import '../../editor/media/rich_embeds/providers.dart' show EmbedService, RichLink, richLinkOf;
import '../types.dart' show PluginHost;
import 'manifest.dart' as figma;

/// Where the API is.
const String figmaApi = 'api.figma.com';

/// How long one call may take.
const Duration figmaTimeout = Duration(seconds: 10);

/// About how wide a frame's picture is asked for, in pixels: a card is never drawn wider than this on a Fold's inner
/// screen at its density, and a picture this wide is a few hundred kilobytes.
const double figmaPictureWidth = 1600;

/// The tallest it is asked for: a long page is drawn cropped to the card's shape anyway.
const double figmaPictureHeight = 2400;

/// The Figma file and frame a link names, as the API wants them.
@immutable
class FigmaLink {
  const FigmaLink({required this.fileKey, this.nodeId});

  /// The file's key, or its branch's.
  final String fileKey;

  /// The frame's id with the API's colon (`12:34`), or null for the file as a whole.
  final String? nodeId;

  /// What the cards' memory keeps it under.
  String get key => nodeId == null ? fileKey : '$fileKey/$nodeId';

  @override
  bool operator ==(Object other) => other is FigmaLink && other.fileKey == fileKey && other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(fileKey, nodeId);

  @override
  String toString() => 'FigmaLink($key)';
}

final RegExp _key = RegExp(r'^[A-Za-z0-9]{10,128}$');
final RegExp _node = RegExp(r'^[A-Za-z0-9:;_]{1,256}$');

/// The file and frame of a Figma rich embed, or null for any other link and for a community file.
FigmaLink? figmaLinkOf(RichLink link) {
  if (link.service != EmbedService.figma || link.kind == 'community') return null;
  final uri = Uri.tryParse(link.source);
  if (uri == null) return null;
  final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (parts.length < 2) return null;
  // `/design/<file>/branch/<branch>/<name>`: the branch is a file of its own to the API.
  final key = parts.length >= 4 && parts[2] == 'branch' && _key.hasMatch(parts[3]) ? parts[3] : parts[1];
  if (!_key.hasMatch(key)) return null;
  String? said;
  try {
    said = uri.queryParameters['node-id'];
  } on FormatException {
    said = null;
  }
  final node = said?.trim().replaceAll('-', ':');
  return FigmaLink(fileKey: key, nodeId: node != null && node.isNotEmpty && _node.hasMatch(node) ? node : null);
}

/// The same, read from an address.
FigmaLink? figmaLinkOfUrl(String url) {
  final link = richLinkOf(url);
  return link == null ? null : figmaLinkOf(link);
}

/// What Figma said of a link: the frame's name and the file's, and its picture with its size.
@immutable
class FigmaFrame {
  const FigmaFrame({required this.file, this.frame, this.picture, this.width, this.height});

  /// The file's name.
  final String file;

  /// The frame's name, or null for the file as a whole.
  final String? frame;

  /// Where its picture is: Figma's render of the frame, or the file's thumbnail.
  final String? picture;

  /// The frame's size in Figma, for the card's shape; null for a file's thumbnail.
  final double? width;
  final double? height;

  Map<String, Object?> toJson() => <String, Object?>{'file': file, 'frame': ?frame, 'picture': ?picture, 'w': ?width, 'h': ?height};

  static FigmaFrame? fromJson(Object? json) {
    if (json is! Map || json['file'] is! String) return null;
    String? text(String key) => json[key] is String ? json[key] as String : null;
    double? size(String key) => json[key] is num ? (json[key] as num).toDouble() : null;
    return FigmaFrame(file: json['file'] as String, frame: text('frame'), picture: text('picture'), width: size('w'), height: size('h'));
  }

  @override
  bool operator ==(Object other) => other is FigmaFrame && other.file == file && other.frame == frame && other.picture == picture && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(file, frame, picture, width, height);

  @override
  String toString() => 'FigmaFrame($file, $frame, $picture)';
}

/// Whose a token is: `GET /v1/me`.
@immutable
class FigmaAccount {
  const FigmaAccount({this.handle, this.email});

  final String? handle;
  final String? email;

  /// The handle and the address, as the page says them: "Matt · matt@example.com".
  String get words => [?handle, ?email].join(' · ');
}

/// What Figma refused, or that it was not reached.
class FigmaFailure implements Exception {
  const FigmaFailure(this.message, {this.status, this.retryAfter});

  final String message;

  /// Figma's status; null where nothing answered.
  final int? status;

  /// How long Figma asked to be left, from a 429's `Retry-After`.
  final Duration? retryAfter;

  /// A 403 that names the token's scopes: the token is good, but may not do this.
  bool get scope => status == 403 && message.toLowerCase().contains('scope');

  /// A token Figma does not know.
  bool get badToken => (status == 403 && !scope && message.toLowerCase().contains('token')) || status == 401;

  /// Asking less often: wait and ask again.
  bool get busy => status == 429;

  @override
  String toString() => message;
}

/// What is said when Figma could not be reached.
const String figmaUnreachable = 'Figma couldn’t be reached. Check the connection and try again.';

/// Figma, asked with one token through the plugin's host.
class FigmaClient {
  FigmaClient({required this.token, PluginHost? via}) : _via = via;

  final String token;
  final PluginHost? _via;

  PluginHost get _on => _via ?? figma.host;

  /// The token the plugin keeps, as a client; null where none is kept.
  static FigmaClient? kept({PluginHost? via}) {
    final token = (via ?? figma.host).secrets.held(figma.tokenSecret)?.trim() ?? '';
    return token.isEmpty ? null : FigmaClient(token: token, via: via);
  }

  Future<Map<String, Object?>> _get(String path, [Map<String, String>? query]) async {
    final FetchResponse answer;
    try {
      answer = await _on.fetch(FetchRequest(method: 'GET', url: Uri.https(figmaApi, path, query), headers: {'X-Figma-Token': token}, timeout: figmaTimeout));
    } on TimeoutException {
      throw const FigmaFailure(figmaUnreachable);
    } catch (error) {
      if (error is Error) rethrow;
      throw const FigmaFailure(figmaUnreachable);
    }
    Object? json;
    try {
      json = jsonDecode(answer.text);
    } on FormatException {
      json = null;
    }
    if (!answer.ok) throw _failure(answer, json);
    if (json is! Map) throw FigmaFailure('Figma answered something that isn’t JSON.', status: answer.status);
    return json.cast<String, Object?>();
  }

  /// Whose the token is.
  Future<FigmaAccount> me() async {
    final json = await _get('/v1/me');
    String? text(String key) => json[key] is String && (json[key] as String).trim().isNotEmpty ? (json[key] as String).trim() : null;
    return FigmaAccount(handle: text('handle'), email: text('email'));
  }

  /// What [link] is: a frame's name, size and picture, or a file's name and thumbnail.
  Future<FigmaFrame> frame(FigmaLink link) async {
    final key = Uri.encodeComponent(link.fileKey);
    final node = link.nodeId;
    if (node == null) {
      final file = await _get('/v1/files/$key', {'depth': '1'});
      return FigmaFrame(file: _name(file['name']) ?? 'Figma file', picture: _https(file['thumbnailUrl']));
    }
    final nodes = await _get('/v1/files/$key/nodes', {'ids': node, 'depth': '1'});
    final fileName = _name(nodes['name']) ?? 'Figma file';
    final thumbnail = _https(nodes['thumbnailUrl']);
    final held = nodes['nodes'];
    final entry = held is Map ? held[node] : null;
    final document = entry is Map ? entry['document'] : null;
    // A frame the file no longer has: the file, as a link without one is drawn.
    if (document is! Map) return FigmaFrame(file: fileName, picture: thumbnail);
    final box = document['absoluteBoundingBox'];
    final width = box is Map && box['width'] is num ? (box['width'] as num).toDouble() : null;
    final height = box is Map && box['height'] is num ? (box['height'] as num).toDouble() : null;
    final images = await _get('/v1/images/$key', {'ids': node, 'format': 'png', 'scale': pictureScale(width, height)});
    final made = images['images'];
    final picture = made is Map ? _https(made[node]) : null;
    return FigmaFrame(
      file: fileName,
      frame: _name(document['name']),
      // Figma made no picture of it (a page, an empty frame): the file's thumbnail, in its own shape.
      picture: picture ?? thumbnail,
      width: picture == null || width == null || width <= 0 ? null : width,
      height: picture == null || height == null || height <= 0 ? null : height,
    );
  }
}

/// The scale a frame of [width] by [height] is drawn at: about [figmaPictureWidth] across and at most
/// [figmaPictureHeight] down, never past 2, nor under Figma's least (0.01). Two decimals, as Figma reads it.
@visibleForTesting
String pictureScale(double? width, double? height) {
  var scale = 2.0;
  if (width != null && width > 0) scale = math.min(scale, figmaPictureWidth / width);
  if (height != null && height > 0) scale = math.min(scale, figmaPictureHeight / height);
  scale = scale.clamp(0.01, 2.0);
  final text = scale.toStringAsFixed(2);
  return text.endsWith('.00') ? text.substring(0, text.length - 3) : text.replaceFirst(RegExp(r'0$'), '');
}

String? _name(Object? value) => value is String && value.trim().isNotEmpty ? value.trim() : null;

String? _https(Object? value) => value is String && Uri.tryParse(value)?.scheme == 'https' ? value : null;

FigmaFailure _failure(FetchResponse answer, Object? json) {
  final said = json is Map ? (json['err'] ?? json['message']) : null;
  final words = said is String && said.trim().isNotEmpty ? said.trim() : null;
  final status = answer.status;
  Duration? wait;
  if (status == 429) {
    final seconds = int.tryParse(answer.headers['retry-after']?.trim() ?? '');
    if (seconds != null && seconds > 0) wait = Duration(seconds: seconds);
  }
  final message = switch (status) {
    401 => 'Figma didn’t accept the token${words == null ? '' : ': $words'}.',
    403 => words == null ? 'Figma refused: the token may not read this.' : 'Figma refused: $words.',
    404 => 'Figma has no such file, or it isn’t one this token can open.',
    429 => 'Figma asked for fewer requests for a while.',
    _ => 'Figma answered $status${words == null ? '' : ': $words'}.',
  };
  return FigmaFailure(message, status: status, retryAfter: wait);
}
