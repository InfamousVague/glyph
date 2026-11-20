import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/friends/buddies.dart';
import 'package:ghost_messaging/me/me.dart';
import 'package:ghost_messaging/me/picture_make.dart';
import 'package:ghost_messaging/me/pictures.dart';
import 'package:image/image.dart' as img;

/// A photo-like picture, [w] by [h]: smooth light with shapes and a grain, as a phone's camera makes them.
Uint8List _photo(int w, int h, {double grain = 18}) {
  final r = Random(7);
  final p = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final d = sqrt(pow(x - w * 0.45, 2) + pow(y - h * 0.4, 2)) / w;
      final n = (r.nextDouble() - 0.5) * grain;
      final face = d < 0.22 ? 60.0 : 0.0;
      p.setPixelRgb(x, y, (200 - d * 180 + face + n).clamp(0, 255), (150 + sin(x / 23) * 30 + n).clamp(0, 255), (90 + y / h * 120 + n).clamp(0, 255));
    }
  }
  return img.encodeJpg(p, quality: 92);
}

int _sideOf(String b64) => img.decodeJpg(base64Decode(b64))!.width;

/// Profile pictures made sharp (Matt, 2026-11-20: "my uploaded profile picture is super blurry": a photo came out 72
/// pixels across, the most a PNG of 24000 characters held, and was drawn at up to 96 points).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a photo is made 256 pixels across as JPEG, with a small stand-in builds from before take', (tester) async {
    final made = (await tester.runAsync(() => profilePictureOf(_photo(1600, 1200))))!;
    expect(_sideOf(made.sharp), ProfilePictures.sharpSide);
    expect(img.decodeJpg(base64Decode(made.sharp))!.height, ProfilePictures.sharpSide, reason: 'square');
    expect(made.sharp.length, lessThanOrEqualTo(ProfilePictures.sharpMost));
    expect(made.small, isNotEmpty);
    expect(made.small.length, lessThanOrEqualTo(ProfilePictures.smallMost));
    expect(_sideOf(made.small), greaterThanOrEqualTo(64));
  });

  testWidgets('a picture all detail still fits, a little smaller', (tester) async {
    final made = (await tester.runAsync(() => profilePictureOf(_photo(1000, 1000, grain: 255))))!;
    expect(made.sharp.length, lessThanOrEqualTo(ProfilePictures.sharpMost));
    expect(made.small.length, lessThanOrEqualTo(ProfilePictures.smallMost));
    debugPrint('all detail: ${_sideOf(made.sharp)} px');
  });

  test('both go to friends in one packet of the hub\'s 60 KB, with room for the rest of a profile', () {
    expect(ProfilePictures.sharpMost + ProfilePictures.smallMost + 6000, lessThan(60 * 1024));
    expect(ProfilePictures.smallMost, lessThanOrEqualTo(ProfilePictures.oldMost));
    expect(ProfilePictures.sharpMost, lessThanOrEqualTo(ProfilePictures.most));
  });

  test('Me keeps both; the small one is the picture old builds and a greeting\'s mark know; taking it away clears both', () async {
    final me = Me.instance;
    await me.start(MemoryMeStore(), ValueNotifier(0), () => null);
    me.setPicture(const ProfilePicture(sharp: 'c2hhcnA=', small: 'c21hbGw='));
    expect((me.picture, me.pictureSharp), ('c21hbGw=', 'c2hhcnA='));
    me.setProfile(picture: 'b2xk');
    expect((me.picture, me.pictureSharp), ('b2xk', 'b2xk'), reason: 'set the old way: one picture');
    me.setPicture(const ProfilePicture(sharp: 'c2hhcnA=', small: 'c21hbGw='));
    me.setPicture(null);
    expect((me.picture, me.pictureSharp), ('', ''));
  });

  test('a friend\'s profile: the sharp one where it is said, else the small one', () {
    expect(Buddies.saidOf({'p': 'c21hbGw=', 'pp': 'c2hhcnA=', 'st': ''}).picture, 'c2hhcnA=');
    expect(Buddies.saidOf({'p': 'c21hbGw=', 'st': ''}).picture, 'c21hbGw=', reason: 'a build from before 0.10.4');
    expect(Buddies.saidOf({'st': ''}).picture, '', reason: 'none');
  });

  test('in a space the sharp one is kept under the small one\'s mark, which the greeting names', () {
    const small = 'c21hbGw=', sharp = 'c2hhcnA=';
    ProfilePictures.instance.keep('maya', sharp, markOf: small);
    expect(ProfilePictures.instance.of('maya', hash: ProfilePictures.hashOf(small)), sharp);
    expect(ProfilePictures.instance.of('maya', hash: ProfilePictures.hashOf('b3RoZXI=')), isNull, reason: 'a newer one');
  });
}
