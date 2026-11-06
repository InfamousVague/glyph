import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/updates.dart';
import 'package:ghost_md/root/iphone_wiring.dart';
import 'package:ghost_md/settings/panes/about_pane.dart';

/// Google Play's build (tool/cutover-build.sh --play; docs/store/play/README.md): it never updates itself, About says
/// Play does, its manifest drops the installer's permission and provider, and no other build is changed by any of it.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('every build but Play’s is told nothing, and this run is not one', () {
    expect(playStoreBuild, isFalse);
  });

  test('Play’s build never looks for an update, whatever it is told', () {
    const keys = ['a-key'];
    expect(UpdatesConfig.of(source: 'https://example.com/flutter', keys: keys, debug: false)?.source, 'https://example.com/flutter');
    expect(UpdatesConfig.of(source: 'https://example.com/flutter', keys: keys, debug: false, playStore: true), isNull);
    expect(UpdatesConfig.of(source: '', keys: keys, debug: false, cutover: true)?.source, tauriReleases, reason: 'the sideloaded cutover build still looks');
    expect(UpdatesConfig.of(source: '', keys: keys, debug: false, cutover: true, playStore: true), isNull);
  });

  test('About says Google Play updates the app, on a phone, in Play’s build alone', () {
    expect(appStoreUpdates(platform: TargetPlatform.android, playStore: false), isNull);
    expect(appStoreUpdates(platform: TargetPlatform.android), isNull);
    final told = appStoreUpdates(platform: TargetPlatform.android, playStore: true)!;
    expect(told.store, 'play');
    expect(updatesSummary(told), 'Updates through Google Play');
    final section = updatesSection(told);
    expect(section, hasLength(1), reason: 'no Check for updates, no alerts');
    // An iPhone is still the App Store's, and Play's switch means nothing off Android.
    expect(appStoreUpdates(platform: TargetPlatform.iOS, playStore: true)?.store, 'appstore');
    expect(appStoreUpdates(platform: TargetPlatform.macOS, macStore: false, playStore: true), isNull);
  });

  test('the play manifest takes out the installer permission and provider, and Gradle lays it over only for Play', () {
    final play = read('android/app/src/play/AndroidManifest.xml').replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    expect(play, contains('android.permission.REQUEST_INSTALL_PACKAGES" tools:node="remove"'));
    expect(play, contains(r'android:authorities="${applicationId}.updates"'));
    expect(RegExp('tools:node="remove"').allMatches(play), hasLength(2));
    final main = read('android/app/src/main/AndroidManifest.xml');
    expect(main, contains('android.permission.REQUEST_INSTALL_PACKAGES'), reason: 'the sideloaded APK still updates itself');
    final gradle = read('android/app/build.gradle.kts');
    expect(gradle, contains('if (ghostPlay) getByName("release").manifest.srcFile("src/play/AndroidManifest.xml")'));
    expect(gradle, contains('if (ghostPlay) ndk { abiFilters.clear(); abiFilters += listOf("arm64-v8a") }'), reason: 'Play offers the bundle only where the core runs');
    expect(Directory('android/app/src/release').existsSync(), isFalse, reason: 'the release source set has no manifest of its own to replace');
    final script = read('tool/cutover-build.sh');
    expect(script, contains('--dart-define=GHOST_STORE=play'));
    expect(script, contains('export GHOST_STORE=play GHOST_WEAR=0'));
    expect(script, contains(r'GLYPH_ANDROID_SIGNING="${GLYPH_ANDROID_SIGNING:-$HOME/.config/glyph/play-signing.properties}"'), reason: 'Play takes the upload key only');
  });
}
