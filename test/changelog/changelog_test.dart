// The changelog the app carries and who is shown what of it (lib/changelog; Matt, 2026-10-30: "Add a changelog popup
// modal that shows after every update with iconography"): the file itself (every release from 2.3.70, newest first,
// its newest pubspec's version, every icon one the app can draw), the rule a launch is judged by (an update, a fresh
// install, a device that has seen it, skipped versions, a build that is no release), the controller that keeps the
// version seen, and the release's check that stops a build with no entry (tool/changelog_check.sh in
// tool/cutover-build.sh).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/brand_marks.dart' show debugStoreShots;
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/changelog/change_look.dart';
import 'package:ghost_md/changelog/changelog.dart';
import 'package:ghost_md/changelog/whats_new.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/guide/guide_state.dart' show guideSeenKey;
import 'package:ghost_md/plugins/brands.dart' show pluginLucide;
import 'package:ghost_md/settings/panes/about_pane.dart' show ghostVersion;

Changelog _bundle() => Changelog.parse(File(changelogAsset).readAsStringSync());

Release _release(String version, [String kind = 'new']) => Release(version: version, date: '2026-10-29', items: [ChangeItem(icon: 'sparkles', words: 'Something $version.', kind: ChangeKind.parse(kind)!)]);

Changelog _log(List<String> versions) => Changelog([for (final v in versions) _release(v)]);

void main() {
  group('the file', () {
    test('is a list of releases, newest first, each with a day, words and a kind for every item', () {
      final raw = jsonDecode(File(changelogAsset).readAsStringSync()) as List<dynamic>;
      final parsed = _bundle();
      expect(parsed.releases.length, raw.length, reason: 'every release in the file reads');
      final versions = [for (final release in raw) (release as Map<String, dynamic>)['version']];
      expect(versions, [for (final release in parsed.releases) release.version], reason: 'the file is newest first');
      for (final release in parsed.releases) {
        expect(release.date, matches(RegExp(r'^2026-\d\d-\d\d$')), reason: release.version);
        expect(release.items.length, inInclusiveRange(1, 7), reason: '${release.version}: at most seven lines');
        final items = ((raw.firstWhere((r) => r['version'] == release.version) as Map<String, dynamic>)['items'] as List<dynamic>);
        expect(release.items.length, items.length, reason: '${release.version}: every item has an icon, words and a kind');
        for (final item in release.items) {
          expect(item.words.trim(), isNotEmpty);
          expect(item.words, endsWith('.'), reason: 'one plain sentence: ${item.words}');
          expect(item.words.length, lessThan(140), reason: 'short: ${item.words}');
        }
      }
    });

    test('has every release from 2.3.70 to 2.3.89', () {
      final have = {for (final release in _bundle().releases) release.version};
      for (var patch = 70; patch <= 89; patch += 1) {
        expect(have, contains('2.3.$patch'));
      }
    });

    // pubspec.yaml's version stays the development build's 0.1.0: a release's is the one tool/cutover-build.sh is given
    // (--build-name and GHOST_VERSION), which tool/changelog_check.sh holds to the file before it builds. Where pubspec
    // is ever given a release's version, the newest entry is that one.
    test('its newest entry is pubspec.yaml\'s version wherever pubspec carries a release, and newer than any it has', () {
      final pubspec = RegExp(r'^version:\s*([0-9.]+)\+', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
      final newest = _bundle().newest!.version;
      expect(ghostVersion, pubspec, reason: 'the app says the version pubspec has, when it is told none');
      if (compareVersions(pubspec, '2.0.0') >= 0) {
        expect(newest, pubspec, reason: 'a release adds its entry to assets/changelog.json');
      } else {
        expect(pubspec, '0.1.0', reason: 'the development build’s');
      }
      expect(compareVersions(newest, '2.3.88'), greaterThanOrEqualTo(0), reason: 'the last release built, 2026-10-30, is 2.3.88');
      for (final release in _bundle().releases) {
        expect(compareVersions(newest, release.version), greaterThanOrEqualTo(0));
      }
    });

    test('is in the bundle', () {
      expect(File('pubspec.yaml').readAsStringSync(), contains('\n    - $changelogAsset\n'));
    });

    test('every icon is a glyph the app has, or a built-in plugin with its mark or its glyph', () {
      for (final release in _bundle().releases) {
        for (final item in release.items) {
          final found = changeGlyphOf(item.icon);
          expect(found.known, isTrue, reason: '${release.version}: "${item.icon}" is neither a Lucide name nor a plugin');
          final plugin = found.plugin;
          if (plugin != null) {
            expect(found.mark != null || Lucide.all[plugin.icon] != null, isTrue, reason: '${item.icon} has a mark or a glyph of its own');
            expect(pluginLucide(plugin), isNot(Lucide.puzzle), reason: '${item.icon}: its own glyph, not the stand-in');
          }
        }
      }
      // A name that is neither draws the sparkle, and says it was not known.
      expect(changeGlyphOf('no-such-glyph'), isA<ChangeGlyph>().having((g) => g.known, 'known', isFalse).having((g) => g.glyph, 'glyph', Lucide.sparkles));
    });

    test('a store-shot build draws no plugin\'s mark, only its glyph', () {
      addTearDown(() => debugStoreShots = null);
      debugStoreShots = false;
      expect(changeGlyphOf('notion').mark, isNotNull);
      expect(changeGlyphOf('github').mark, isNotNull);
      debugStoreShots = true;
      for (final release in _bundle().releases) {
        for (final item in release.items) {
          expect(changeGlyphOf(item.icon).mark, isNull, reason: item.icon);
        }
      }
      expect(changeGlyphOf('notion').glyph, pluginLucide(changeGlyphOf('notion').plugin!));
    });
  });

  group('reading', () {
    test('leaves out what is not the shape, and puts the releases newest first', () {
      final log = Changelog.parse(jsonEncode([
        {'version': '2.3.9', 'date': '2026-10-01', 'items': [{'icon': 'link', 'words': 'A.', 'kind': 'fixed'}, {'icon': 'link', 'words': 'B.', 'kind': 'sideways'}]},
        {'version': '2.3.10', 'date': '2026-10-02', 'title': 'Ten', 'items': []},
        {'date': 'no version'},
        'not a release',
      ]));
      expect([for (final r in log.releases) r.version], ['2.3.10', '2.3.9']);
      expect(log.of('2.3.9')!.items.map((i) => i.words), ['A.']);
      expect(log.of('2.3.10')!.title, 'Ten');
      expect(Changelog.parse('not json').releases, isEmpty);
      expect(Changelog.parse('{}').releases, isEmpty);
    });

    test('compares versions as numbers', () {
      expect(compareVersions('2.3.10', '2.3.9'), greaterThan(0));
      expect(compareVersions('2.3.88', '2.3.88'), 0);
      expect(compareVersions('2.2.5', '2.3.0'), lessThan(0));
    });

    test('since a version: the ones after it up to the one running, newest first, five at most', () {
      final log = _log(['2.3.88', '2.3.87', '2.3.86', '2.3.85', '2.3.84', '2.3.83', '2.3.82', '2.3.81']);
      final two = log.since('2.3.86', '2.3.88');
      expect([for (final r in two.releases) r.version], ['2.3.88', '2.3.87']);
      expect(two.more, isFalse);
      final seven = log.since('2.3.81', '2.3.88');
      expect([for (final r in seven.releases) r.version], ['2.3.88', '2.3.87', '2.3.86', '2.3.85', '2.3.84']);
      expect(seven.more, isTrue);
      // Not past the version running.
      expect([for (final r in log.since('2.3.85', '2.3.87').releases) r.version], ['2.3.87', '2.3.86']);
    });

    test('the day a person reads', () {
      expect(releaseDay('2026-10-30'), '30 Oct 2026');
      expect(releaseDay('2026-01-05'), '5 Jan 2026');
      expect(releaseDay('soon'), 'soon');
    });
  });

  group('who is shown what', () {
    final log = _log(['2.3.88', '2.3.87', '2.3.86', '2.3.85', '2.3.84', '2.3.83', '2.3.82']);
    List<String>? shown(WhatsNewVerdict verdict) => verdict.show == null ? null : [for (final r in verdict.show!.releases) r.version];

    test('after an update: the releases since the one last seen', () {
      final verdict = whatsNewVerdict(changelog: log, running: '2.3.88', lastSeen: '2.3.87', usedBefore: true);
      expect(shown(verdict), ['2.3.88']);
      expect(verdict.keep, isNull, reason: 'kept as seen only once the card is put away');
    });

    test('skipped versions are all shown, newest first, five at most and then "earlier changes"', () {
      final three = whatsNewVerdict(changelog: log, running: '2.3.88', lastSeen: '2.3.85', usedBefore: true);
      expect(shown(three), ['2.3.88', '2.3.87', '2.3.86']);
      expect(three.show!.more, isFalse);
      final six = whatsNewVerdict(changelog: log, running: '2.3.88', lastSeen: '2.3.82', usedBefore: true);
      expect(shown(six), ['2.3.88', '2.3.87', '2.3.86', '2.3.85', '2.3.84']);
      expect(six.show!.more, isTrue);
    });

    test('a fresh install: nothing, and the version kept as seen', () {
      final verdict = whatsNewVerdict(changelog: log, running: '2.3.88', lastSeen: null, usedBefore: false);
      expect(verdict.show, isNull);
      expect(verdict.keep, '2.3.88');
    });

    test('a device that ran the app before this was kept: the running version alone', () {
      final verdict = whatsNewVerdict(changelog: log, running: '2.3.88', lastSeen: null, usedBefore: true);
      expect(shown(verdict), ['2.3.88']);
    });

    test('seen already, or older: nothing', () {
      expect(whatsNewVerdict(changelog: log, running: '2.3.88', lastSeen: '2.3.88', usedBefore: true).show, isNull);
      expect(whatsNewVerdict(changelog: log, running: '2.3.87', lastSeen: '2.3.88', usedBefore: true).show, isNull);
    });

    test('a build that is no release (a development build, an iPhone\'s numbering) shows and keeps nothing', () {
      for (final running in ['0.1.0', '2.2.5', null]) {
        final verdict = whatsNewVerdict(changelog: log, running: running, lastSeen: '2.3.80', usedBefore: true);
        expect((verdict.show, verdict.keep), (null, null), reason: '$running');
      }
    });
  });

  group('the device\'s memory', () {
    final log = _log(['2.3.88', '2.3.87', '2.3.86']);

    test('a fresh install keeps the version at once and never raises the card', () {
      final store = MemoryStored();
      final whatsNew = WhatsNew(store: store)..settle(changelog: log, running: '2.3.88');
      expect(whatsNew.waiting, isNull);
      expect(store.readText(whatsNewSeenKey), '2.3.88');
      whatsNew.raise();
      expect(whatsNew.up, isFalse);
    });

    test('used before is the walkthrough\'s key holding anything, or the Mac saying it put this version in place', () {
      expect(usedBeforeOn(MemoryStored({guideSeenKey: '1'})), isTrue);
      expect(usedBeforeOn(MemoryStored({guideSeenKey: '2'})), isTrue);
      expect(usedBeforeOn(MemoryStored()), isFalse);
      final mac = WhatsNew(store: MemoryStored())..settle(changelog: log, running: '2.3.88', justUpdated: true);
      expect(mac.waiting?.releases.map((r) => r.version), ['2.3.88']);
    });

    test('shown once: put away, the version is seen and the next launch shows nothing', () {
      final store = MemoryStored({whatsNewSeenKey: '2.3.86'});
      final first = WhatsNew(store: store)..settle(changelog: log, running: '2.3.88');
      expect(first.waiting?.releases.map((r) => r.version), ['2.3.88', '2.3.87']);
      first.raise();
      expect(first.up, isTrue);
      first.seen();
      expect((first.up, first.waiting), (false, null));
      expect(store.readText(whatsNewSeenKey), '2.3.88');
      final next = WhatsNew(store: store)..settle(changelog: log, running: '2.3.88');
      expect(next.waiting, isNull);
    });

    test('decided once per version: told again as the phone answers, nothing changes', () {
      final store = MemoryStored({whatsNewSeenKey: '2.3.87'});
      var told = 0;
      final whatsNew = WhatsNew(store: store)..addListener(() => told += 1);
      whatsNew.settle(changelog: log, running: null);
      expect(told, 0, reason: 'the version not known yet');
      whatsNew
        ..settle(changelog: log, running: '2.3.88')
        ..settle(changelog: log, running: '2.3.88');
      expect(told, 1);
      expect(whatsNew.running, '2.3.88');
    });
  });

  group('the release\'s check', () {
    Future<ProcessResult> check(String version, [String? file]) => Process.run('sh', ['tool/changelog_check.sh', version, ?file]);

    test('passes a version the changelog has', () async {
      final result = await check(_bundle().newest!.version);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    });

    test('stops a version it has not, saying what to add, and a version that is only a prefix of one', () async {
      final missing = await check('2.3.99');
      expect(missing.exitCode, 1);
      expect(missing.stderr as String, contains('assets/changelog.json has no entry for 2.3.99 (its newest is ${_bundle().newest!.version})'));
      expect((await check('2.3.8')).exitCode, 1, reason: '2.3.8 is not 2.3.88');
      expect((await check('2x3x88')).exitCode, 1, reason: 'a dot is a dot');
    });

    test('reads another file where given, and stops where there is none', () async {
      final dir = Directory.systemTemp.createTempSync('changelog-check');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/changelog.json')..writeAsStringSync('[\n  {"version": "3.0.0", "date": "2026-11-01", "items": []}\n]\n');
      expect((await check('3.0.0', file.path)).exitCode, 0);
      expect((await check('2.3.88', file.path)).exitCode, 1);
      final none = await check('3.0.0', '${dir.path}/gone.json');
      expect(none.exitCode, 1);
      expect(none.stderr as String, contains('no changelog at'));
    });

    test('runs in tool/cutover-build.sh before anything is built, for a release', () {
      final script = File('tool/cutover-build.sh').readAsStringSync();
      final at = script.indexOf('tool/changelog_check.sh "\$version"');
      expect(at, greaterThan(0));
      expect(at, lessThan(script.indexOf('flutter build apk')));
      expect(script, contains('if [ "\$mode" = "--release" ]; then tool/changelog_check.sh'));
    });
  });
}
