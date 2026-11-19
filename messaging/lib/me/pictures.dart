import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart' show SHA256Digest;

/// Profile pictures of people on Ghost, by their id on the hub (Matt, 2026-11-19: "build a profile section in the app
/// that allows us to set profile pictures and status messages"): a friend's comes with their profile; someone in a
/// space says only their picture's [hashOf] when they come in, and the picture itself is asked of them when someone
/// looks at their profile (lib/voice/hangout.dart, `pic?`), so a space's greetings stay small.
///
/// Each picture is a square base64 PNG of at most [most] characters (lib/ui/circles/circle_picture.dart makes them).
class ProfilePictures extends ChangeNotifier {
  ProfilePictures._();
  static final ProfilePictures instance = ProfilePictures._();

  /// The longest a picture may be, as base64: one circle's picture, which rides in one packet with room to spare.
  static const most = 24000;

  final Map<String, ({String hash, String picture})> _by = {};

  /// A short mark of [picture]: what a greeting carries in its place. '' for none.
  static String hashOf(String picture) {
    if (picture.isEmpty) return '';
    final d = SHA256Digest().process(Uint8List.fromList(utf8.encode(picture)));
    return [for (final b in d.take(6)) b.toRadixString(16).padLeft(2, '0')].join();
  }

  /// [id]'s picture where it is here (and, given [hash], only that one); null where not.
  String? of(String id, {String? hash}) {
    final had = _by[id];
    if (had == null || (hash != null && hash.isNotEmpty && had.hash != hash)) return null;
    return had.picture;
  }

  /// Keeps [picture] as [id]'s. An empty one forgets theirs; one too long, or not base64, is not kept.
  void keep(String id, String picture) {
    if (id.isEmpty) return;
    if (picture.isEmpty) {
      if (_by.remove(id) != null) notifyListeners();
      return;
    }
    if (picture.length > most || !RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(picture)) return;
    final hash = hashOf(picture);
    if (_by[id]?.hash == hash) return;
    _by[id] = (hash: hash, picture: picture);
    notifyListeners();
  }
}
