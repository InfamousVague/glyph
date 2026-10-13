import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/how_canvas.dart';
import 'package:ghost_md/core/mac_app.dart';
import 'package:ghost_md/core/native/device_paths.dart';
import 'package:ghost_md/root/iphone_wiring.dart';
import 'package:ghost_md/settings/panes/about_pane.dart';
import 'package:ghost_md/settings/settings_sections.dart';

/// The Mac build for the Mac App Store (tool/cutover-build-mac-store.sh; docs/CUTOVER.md, section 9): what it is
/// told, what a sandbox changes, and that no other build is changed by any of it.
void main() {
  String read(String path) => File(path).readAsStringSync();

  /// A plist's keys and values with the comments taken out.
  String bare(String xml) => xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  group('in Dart', () {
    test('every build but the store’s is told nothing, and this run is not one', () {
      expect(macAppStore, isFalse);
      expect(macSandboxKeepsFiles, isFalse);
    });

    test('the container’s own path is taken as told only by the store’s build, really sandboxed', () {
      expect(macSandboxKeepsFilesFor(store: true, sandboxed: true), isTrue);
      // The store's build somehow outside a sandbox, and any other build inside one, are held to the rule in code.
      expect(macSandboxKeepsFilesFor(store: true, sandboxed: false), isFalse);
      expect(macSandboxKeepsFilesFor(store: false, sandboxed: true), isFalse);
      expect(macSandboxKeepsFilesFor(store: false, sandboxed: false), isFalse);
    });

    test('a sandboxed Mac app’s container is named by the bundle id, which is why the path is not asked of there', () {
      const container = '/Users/someone/Library/Containers/com.mattssoftware.glyph/Data/Library';
      const data = '$container/Application Support/com.mattssoftware.glyph.v2', cache = '$container/Caches/com.mattssoftware.glyph.v2';
      // The rule every build that is not sandboxed is held to reads the container as the Tauri app's folder.
      expect(isRealAppPath(data), isTrue);
      expect(() => DevicePaths.told(dataDir: data, cacheDir: cache, sandboxed: false), throwsStateError);
      // Sandboxed, the Mac keeps the app to its container, and the path is taken as told.
      final told = DevicePaths.told(dataDir: data, cacheDir: cache, sandboxed: true);
      expect(told.dataDir, data);
      expect(told.cacheDir, cache);
    });

    test('the build on the website still refuses the Tauri app’s folder', () {
      const home = '/Users/someone/Library';
      expect(() => DevicePaths.told(dataDir: '$home/Application Support/com.mattssoftware.glyph', cacheDir: '$home/Caches/com.mattssoftware.glyph', sandboxed: false), throwsStateError);
      final own = DevicePaths.told(dataDir: '$home/Application Support/com.mattssoftware.glyph.v2', cacheDir: '$home/Caches/com.mattssoftware.glyph.v2', sandboxed: false);
      expect(own.dataDir, endsWith('.v2'));
    });

    test('About is told its updates are the App Store’s on a Mac only in the store’s build', () {
      expect(appStoreUpdates(platform: TargetPlatform.macOS, macStore: false), isNull);
      expect(appStoreUpdates(platform: TargetPlatform.macOS), isNull);
      final told = appStoreUpdates(platform: TargetPlatform.macOS, macStore: true);
      expect(told?.store, 'appstore');
      expect(updatesSummary(told!), 'Updates through the App Store');
      // An iPhone as before, and no other platform by the Mac's switch.
      expect(appStoreUpdates(platform: TargetPlatform.iOS, macStore: false)?.store, 'appstore');
      expect(appStoreUpdates(platform: TargetPlatform.android, macStore: true), isNull);
    });

    test('the store’s build offers no Guide book and no Backup page; the website’s has both', () {
      expect(offersGuideBookFor(records: true, macStore: false), isTrue);
      expect(offersGuideBookFor(records: true, macStore: true), isFalse);
      expect(offersGuideBookFor(records: false, macStore: false), isFalse);
      expect(backupOffered(ios: false, macStore: false), isTrue);
      expect(backupOffered(ios: false, macStore: true), isFalse);
      expect(backupOffered(ios: true, macStore: false), isFalse);
    });

    test('the example canvas every other build draws is unchanged', () {
      final speak = howCanvas(voice: true).nodes.firstWhere((node) => node.id == 'speak');
      expect(speak.text, contains('press the side key'));
    });

    test('the carry is never begun by the store’s build', () {
      final main = read('lib/main.dart');
      expect(main, contains('final mac = runsAsMacApp && replacesTauriApp && !macAppStore;'));
    });
  });

  group('the Mac’s Swift', () {
    final channels = read('macos/Runner/GhostChannels.swift');
    final files = read('macos/Runner/FilesChannel.swift');
    final keychain = read('apple/Keychain.swift');

    test('knows a sandbox by what macOS gives one, and reads no other app’s Keychain item from inside it', () {
      expect(channels, contains('static let sandboxed = !(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] ?? "").isEmpty'));
      expect(channels, contains('guard !sandboxed else { return nil }'));
    });

    test('keeps a chosen folder as a security-scoped bookmark only when sandboxed, and takes it up before the core opens', () {
      expect(files, contains('guard GhostChannels.sandboxed, !restored else { return }'));
      expect(files, contains('if GhostChannels.sandboxed, self?.grant(url) != true {'));
      expect(files, contains('.withSecurityScope'));
      // Asked where the app's folders are asked for, which is before `init`.
      final asked = channels.indexOf('self.files.restoreGrants()'), answered = channels.indexOf('result(["dataDir": dirs.data.path');
      expect(asked, greaterThan(0));
      expect(answered, greaterThan(asked));
    });

    test('the store’s build keeps its secrets under a service of its own, and every other build under the one it had', () {
      expect(keychain, contains(r'return "\(id).store.secure"'));
      expect(keychain, contains(r'return "\(id).secure"'));
      expect(keychain, contains('#if os(macOS)'));
    });
  });

  group('the store’s build', () {
    final entitlements = bare(read('macos/Runner/Store.entitlements'));
    final script = read('tool/cutover-build-mac-store.sh');

    test('is sandboxed with five entitlements and nothing that loosens the hardened runtime', () {
      final keys = RegExp(r'<key>([^<]+)</key>\s*<true/>').allMatches(entitlements).map((m) => m.group(1)).toList();
      expect(keys, [
        'com.apple.security.app-sandbox',
        'com.apple.security.network.client',
        'com.apple.security.device.audio-input',
        'com.apple.security.files.user-selected.read-write',
        'com.apple.security.files.bookmarks.app-scope',
      ]);
      for (final loose in ['cs.allow-jit', 'cs.disable-library-validation', 'cs.allow-unsigned-executable-memory', 'temporary-exception', 'network.server', 'automation.apple-events']) {
        expect(entitlements, isNot(contains(loose)));
      }
    });

    test('the website’s build is not sandboxed and its project names neither of the store’s files', () {
      final release = bare(read('macos/Runner/Release.entitlements'));
      expect(release, isNot(contains('app-sandbox')));
      final project = read('macos/Runner.xcodeproj/project.pbxproj');
      expect(project, isNot(contains('Store.entitlements')));
      expect(project, isNot(contains('PrivacyInfo.xcprivacy')));
      expect(project, contains('CODE_SIGN_ENTITLEMENTS = Runner/Release.entitlements;'));
      final website = read('tool/cutover-build-mac.sh');
      expect(website, isNot(contains('GHOST_MAC_STORE')));
      expect(website, contains('--dart-define=GHOST_CUTOVER=true'));
    });

    test('its privacy manifest is the iPhone’s, word for word below the comment', () {
      String body(String path) => bare(read(path)).trim();
      expect(body('macos/Runner/PrivacyInfo.xcprivacy'), body('ios/Runner/PrivacyInfo.xcprivacy'));
    });

    test('the Mac’s Info.plist says what a recording app must, and the store’s category', () {
      final plist = read('macos/Runner/Info.plist');
      expect(plist, contains('NSMicrophoneUsageDescription'));
      expect(plist, contains('public.app-category.productivity'));
      expect(plist, contains('<string>ghostmd</string>'));
      // The export answer is the store copy's alone, put there by the script.
      expect(plist, isNot(contains('ITSAppUsesNonExemptEncryption')));
    });

    test('the script tells Dart it is the store’s and not the carry, signs as the store asks, and uploads nothing', () {
      expect(script, contains('--dart-define=GHOST_MAC_STORE=true'));
      expect(script, isNot(contains('--dart-define=GHOST_CUTOVER=true')));
      expect(script, isNot(contains('--dart-define=GHOST_PLAIN')), reason: 'the Mac keeps its own look');
      expect(script, contains("buddy 'Add :ITSAppUsesNonExemptEncryption bool false'"));
      expect(script, contains('--options runtime --timestamp'));
      expect(script, contains('Apple Distribution: '));
      expect(script, contains('3rd Party Mac Developer Installer: '));
      expect(script, contains('productbuild --component "\$app" /Applications --sign "\$installer"'));
      expect(script, contains('code=\$((major * 1000000 + minor * 1000 + patch))'));
      for (final sends in ['altool', 'notarytool', 'iTMSTransporter', 'upload-app', 'scp ', 'curl ']) {
        expect(script, isNot(contains(sends)), reason: 'the script sends nothing: $sends');
      }
    });

    test('a build to run here has another id, claims no link, and is never on the real service', () {
      expect(script, contains('wanted_id="com.mattssoftware.glyph.storeproof"'));
      expect(script, contains("buddy 'Delete :CFBundleURLTypes'"));
      expect(script, contains('"") api="http://127.0.0.1:9/api" ;;'));
      expect(script, contains(r'${local_run:+--dart-define=GHOST_MODELS=http://127.0.0.1:9}'));
      expect(script, contains("the store's build is on the real service by itself"));
    });
  });
}
