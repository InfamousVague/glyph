/// What this build is, for About's "This build": only what the build itself knows for certain (what it was compiled
/// with and what it runs on), each as a name and its words. Nothing here is asked of a service.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'updates.dart' show ghostBuild;

/// The commit this build was made from (`--dart-define=GHOST_COMMIT=…`, tool/cutover-build.sh), or ''.
const String ghostCommit = String.fromEnvironment('GHOST_COMMIT');
const bool _cutover = bool.fromEnvironment('GHOST_CUTOVER');
const String _api = String.fromEnvironment('GHOST_API');
const bool _perf = bool.fromEnvironment('GHOST_PERF');

/// `20261011223058` as `2026-10-11 22:30:58 UTC`; anything else as it is.
String builtWhen(String stamp) => stamp.length == 14 && int.tryParse(stamp) != null
    ? '${stamp.substring(0, 4)}-${stamp.substring(4, 6)}-${stamp.substring(6, 8)} ${stamp.substring(8, 10)}:${stamp.substring(10, 12)}:${stamp.substring(12, 14)} UTC'
    : stamp;

/// The version's number as Android counts it: 2.0.1 is 2000001.
String versionCodeOf(String version) {
  final parts = version.split('-').first.split('.').map(int.tryParse).toList();
  if (parts.length != 3 || parts.contains(null)) return '';
  return '${parts[0]! * 1000000 + parts[1]! * 1000 + parts[2]!}';
}

/// The rows of "This build", in order. [service] is where the account lives for this build, when it has one;
/// [updatesFrom] where its updates are looked for.
List<({String name, String words})> buildFacts({required String version, String? service, String? updatesFrom}) {
  final mode = kReleaseMode ? 'Release' : (kProfileMode ? 'Profile' : 'Debug');
  final dart = Platform.version.split(' ').first;
  final serviceHost = service ?? (_api.isEmpty ? null : Uri.tryParse(_api)?.host);
  return [
    (name: 'Version', words: versionCodeOf(version).isEmpty ? version : '$version (${versionCodeOf(version)})'),
    (name: 'Built', words: ghostBuild.isEmpty ? 'Not stamped' : builtWhen(ghostBuild)),
    (name: 'Commit', words: ghostCommit.isEmpty ? 'Not stamped' : ghostCommit),
    (name: 'Kind', words: [mode, 'Flutter', if (_cutover) 'replaces the first Ghost.md', if (_perf) 'measured'].join(' · ')),
    (name: 'Dart', words: dart),
    (name: 'Runs on', words: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'),
    (name: 'Account service', words: serviceHost == null || serviceHost.isEmpty ? 'None in this build' : serviceHost),
    (name: 'Updates from', words: updatesFrom == null || updatesFrom.isEmpty ? 'Nowhere in this build' : updatesFrom),
  ];
}
