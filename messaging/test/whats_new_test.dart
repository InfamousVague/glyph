import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/app_state.dart';
import 'package:ghost_messaging/changelog.dart';
import 'package:ghost_messaging/ui/settings_panes.dart' show appVersion;
import 'package:ghost_messaging/ui/whats_new.dart';

import 'support/space_call_harness.dart';

/// What's new (lib/changelog.dart, lib/ui/whats_new.dart; Matt, 2026-11-19: "Implement a changelog that pops up ever
/// time a new update is released with release notes").
class _Opener extends StatefulWidget {
  const _Opener(this.current, {required this.seen, required this.onboarded});
  final String current, seen;
  final bool onboarded;
  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = AppState.of(context);
      if (widget.seen.isNotEmpty) app.set(changelogSeenKey, widget.seen);
      if (widget.onboarded) app.setFlag('onboarded', true);
      showWhatsNewIfUpdated(context, current: widget.current);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  test('versions compare as numbers, and the notes since one are the later ones up to this build, newest first', () {
    expect(laterVersion('0.9.10', '0.9.9'), isTrue);
    expect(laterVersion('0.9.9', '0.9.10'), isFalse);
    expect(laterVersion('1.0.0', '0.9.99'), isTrue);
    expect(laterVersion('0.9.20', '0.9.20'), isFalse);
    expect(laterVersion('0.9.20', ''), isTrue);
    const log = [
      ReleaseNotes('0.9.23', '', ['c']),
      ReleaseNotes('0.9.22', '', ['b']),
      ReleaseNotes('0.9.21', '', ['a']),
    ];
    expect(notesSince('0.9.21', '0.9.22', from: log).map((r) => r.version), ['0.9.22'], reason: 'not a later version this build is not');
    expect(notesSince('0.9.20', '0.9.23', from: log).map((r) => r.version), ['0.9.23', '0.9.22', '0.9.21']);
    expect(notesSince('0.9.23', '0.9.23', from: log), isEmpty);
  });

  test('every entry has a version, a date and words, newest first, and this build\'s version has one', () {
    expect(changelog, isNotEmpty);
    for (var i = 0; i < changelog.length; i++) {
      final r = changelog[i];
      expect(RegExp(r'^\d+\.\d+\.\d+$').hasMatch(r.version), isTrue, reason: r.version);
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(r.date), isTrue, reason: r.version);
      expect(r.notes, isNotEmpty);
      if (i > 0) expect(laterVersion(changelog[i - 1].version, r.version), isTrue, reason: 'newest first');
    }
    // The build's own version has notes, or the release script would have stopped it.
    final pub = RegExp(r'^version:\s*([0-9.]+)\+', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
    expect(pub, appVersion, reason: 'pubspec.yaml and appVersion go together');
  });

  Future<void> open(WidgetTester tester, {required String seen, bool onboarded = true, String current = '0.9.22'}) async {
    final h = await SpaceHarness.load(tester);
    await h.shoot(tester, _Opener(current, seen: seen, onboarded: onboarded), 'whats-new');
  }

  testWidgets('after an update the notes since the last version seen come up once', (tester) async {
    await open(tester, seen: '0.9.21', current: changelog.first.version);
    expect(find.text('What\'s new'), findsOneWidget);
    expect(find.text(changelog.first.notes.first), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the same version again shows nothing', (tester) async {
    await open(tester, seen: changelog.first.version, current: changelog.first.version);
    expect(find.text('What\'s new'), findsNothing);
  });

  testWidgets('a new install that is not set up yet is not told what is new', (tester) async {
    await open(tester, seen: '', onboarded: false, current: changelog.first.version);
    expect(find.text('What\'s new'), findsNothing);
  });

  testWidgets('a phone set up before notes were kept is shown the newest release\'s', (tester) async {
    await open(tester, seen: '', current: changelog.first.version);
    expect(find.text('What\'s new'), findsOneWidget);
    expect(find.text('Ghost Messaging ${changelog.first.version}'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
}
