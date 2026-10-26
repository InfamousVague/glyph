import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/device_keys.dart';
import 'package:ghost_md/capture/device_mic.dart';
import 'package:ghost_md/core/iphone_app.dart';
import 'package:ghost_md/core/location.dart';
import 'package:ghost_md/core/native/ghost_worker.dart';
import 'package:ghost_md/core/phone_position.dart';

/// What an iPhone leaves out, as the real iPhone app's page does (`core/platform.ts` `isIOS`, `recordsVoice`), and
/// that the iPhone's own halves are asked for only on an iPhone: never in a test on a Mac.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('an iPhone records nothing; every other platform does', () {
    expect(recordsVoiceOn(TargetPlatform.iOS), isFalse);
    for (final platform in [TargetPlatform.android, TargetPlatform.macOS, TargetPlatform.windows, TargetPlatform.linux]) {
      expect(recordsVoiceOn(platform), isTrue, reason: '$platform');
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(recordsVoice, isFalse);
    // The look is an iPhone's; the halves are not there to be called from a test.
    expect(runsAsIPhoneApp, isFalse);
    expect(deviceSecureStore(), isA<MemorySecureStore>());
    expect(DeviceMic.supported, isFalse);
  });

  test('on an iPhone the core is the app’s own process, with no file to name', () {
    // The test's process has no core linked into it: the lookup is made in the process and finds nothing.
    final here = openCore(null, iPhone: true);
    expect(here.providesSymbol('ghost_invoke'), isFalse);
    // Anywhere else a file is named, and one that is not there is refused.
    expect(() => openCore('/nowhere/libghost_core.dylib', iPhone: true), throwsA(isA<ArgumentError>()));
    expect(() => openCore('/nowhere/libghost_core.dylib'), throwsA(isA<ArgumentError>()));
  });

  test('Notion and Slack are refused in Rust’s own words on an iPhone, and nowhere else', () {
    expect(notOnIPhone('notion', platform: TargetPlatform.iOS), 'Notion is not available on iOS yet.');
    expect(notOnIPhone('slack', platform: TargetPlatform.iOS), 'Slack is not available on iOS yet.');
    // GitHub is the page's own fetch, and works there.
    expect(notOnIPhone('github', platform: TargetPlatform.iOS), isNull);
    expect(notOnIPhone('notion', platform: TargetPlatform.android), isNull);
    expect(notOnIPhone('slack', platform: TargetPlatform.macOS), isNull);
    // Discord is Slack's shape, kept off an iPhone as Slack is (lib/plugins/discord/discord.dart).
    expect(notOnIPhone('discord', platform: TargetPlatform.iOS), 'Discord is not available on iOS yet.');
    expect(notOnIPhone('discord', platform: TargetPlatform.android), isNull);
  });

  test('an iPhone cannot say where it is, in the page’s own answer', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // No half answers (a test has none either): the reason is the iPhone's, not a browser's.
    final locator = PhoneLocator();
    expect(locator.cannot, LocateFailure.ios);
    expect(locator.onPhone, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(PhoneLocator().cannot, LocateFailure.none);
  });
}
