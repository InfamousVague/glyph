/// What changed in each release, as the app carries it (Matt, 2026-10-30: "Add a changelog popup modal that shows after
/// every update with iconography"): assets/changelog.json, newest first, written for a person using the app.
///
/// A release is `{version, date, title?, items}` and an item `{icon, words, kind}`:
/// - `version` is the release's own (2.3.88), as `--build-name` gives it and pubspec.yaml's `version` holds
///   (test/changelog/changelog_test.dart holds the newest entry to pubspec's, and tool/cutover-build.sh refuses to
///   build a version with no entry, through tool/changelog_check.sh).
/// - `date` the day it was built, `YYYY-MM-DD` (UTC); `title` a few words, where the release has a theme.
/// - `icon` names a glyph by Lucide's name ([Lucide.all]), drawn in the icon pack and style chosen in Settings ›
///   Appearance; or a built-in plugin's id, which draws that plugin's mark as the activity tray does (lib/activity/
///   job_mark.dart), its glyph where it wears none or in a store-shot build (change_look.dart).
/// - `kind` is `new`, `better` or `fixed`, drawn as a small tag in its colour.
///
/// Nothing is fetched: the words of a release not yet installed are not known here, which is why the activity tray's
/// Update section says no more than the version waiting (docs/ACTIVITY.md, The app's updates).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../core/updates.dart' show isNewerVersion;

/// Where the changelog is in the bundle (pubspec.yaml's assets).
const String changelogAsset = 'assets/changelog.json';

/// What an item is: something new, something made better, or something fixed.
enum ChangeKind {
  added('new', 'New'),
  better('better', 'Better'),
  fixed('fixed', 'Fixed');

  const ChangeKind(this.id, this.label);

  /// The word in the file.
  final String id;

  /// The tag's word.
  final String label;

  static ChangeKind? parse(Object? id) {
    for (final kind in values) {
      if (kind.id == id) return kind;
    }
    return null;
  }
}

/// One line of a release: its glyph, its sentence and its kind.
@immutable
class ChangeItem {
  const ChangeItem({required this.icon, required this.words, required this.kind});

  final String icon;
  final String words;
  final ChangeKind kind;
}

/// One release.
@immutable
class Release {
  const Release({required this.version, required this.date, this.title, required this.items});

  final String version;

  /// `YYYY-MM-DD`.
  final String date;
  final String? title;
  final List<ChangeItem> items;
}

/// What [Changelog.since] answers: the releases to show, newest first, and whether there were more before them.
typedef ReleasesSince = ({List<Release> releases, bool more});

/// Every release the file has, newest first.
@immutable
class Changelog {
  const Changelog(this.releases);

  /// Nothing at all: a build whose file would not read.
  static const Changelog empty = Changelog([]);

  final List<Release> releases;

  /// The file's words. A release or an item that is not the shape above is left out rather than failing the rest; the
  /// releases are put newest first whatever order the file has them in.
  factory Changelog.parse(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return empty;
    }
    if (json is! List) return empty;
    final releases = <Release>[];
    for (final each in json) {
      if (each is! Map) continue;
      final version = each['version'], date = each['date'], title = each['title'], items = each['items'];
      if (version is! String || date is! String || items is! List) continue;
      releases.add(Release(
        version: version,
        date: date,
        title: title is String && title.trim().isNotEmpty ? title : null,
        items: [
          for (final item in items)
            if (item is Map && item['icon'] is String && item['words'] is String && ChangeKind.parse(item['kind']) != null)
              ChangeItem(icon: item['icon'] as String, words: item['words'] as String, kind: ChangeKind.parse(item['kind'])!),
        ],
      ));
    }
    releases.sort((a, b) => compareVersions(b.version, a.version));
    return Changelog(List.unmodifiable(releases));
  }

  /// The newest release, or null for an empty file.
  Release? get newest => releases.isEmpty ? null : releases.first;

  /// [version]'s release, or null where the file has none.
  Release? of(String version) {
    for (final release in releases) {
      if (compareVersions(release.version, version) == 0) return release;
    }
    return null;
  }

  /// The releases after [after] up to and including [upTo], newest first, at most [most] of them; `more` says some
  /// older ones were left out ("and earlier changes"). [after] null is every release up to [upTo].
  ReleasesSince since(String? after, String upTo, {int most = 5}) {
    final all = [
      for (final release in releases)
        if (compareVersions(release.version, upTo) <= 0 && (after == null || compareVersions(release.version, after) > 0)) release,
    ];
    return (releases: all.length > most ? all.sublist(0, most) : all, more: all.length > most);
  }
}

/// Dotted versions compared as numbers, as the updater compares them (lib/core/updates.dart [isNewerVersion]):
/// below 0 where [a] is older, 0 where they are the same, above 0 where it is newer.
int compareVersions(String a, String b) => isNewerVersion(a, b) ? 1 : (isNewerVersion(b, a) ? -1 : 0);

Changelog? _bundled;
Future<Changelog>? _reading;

/// The changelog this build carries, once [loadChangelog] has read it; null before.
Changelog? get bundledChangelog => _bundled;

/// Reads the bundle's changelog, once: the first call reads it, every later one answers the same. A file that will
/// not read is [Changelog.empty], so nothing is shown rather than anything failing.
Future<Changelog> loadChangelog({AssetBundle? bundle}) {
  final done = _bundled;
  if (done != null) return Future.value(done);
  return _reading ??= () async {
    try {
      return _bundled = Changelog.parse(await (bundle ?? rootBundle).loadString(changelogAsset));
    } catch (failure) {
      debugPrint('[changelog] not read: $failure');
      return _bundled = Changelog.empty;
    } finally {
      _reading = null;
    }
  }();
}

/// A test's own changelog in place of the bundle's; null forgets it, so the next [loadChangelog] reads the bundle.
@visibleForTesting
void debugUseChangelog(Changelog? changelog) {
  _bundled = changelog;
  _reading = null;
}
