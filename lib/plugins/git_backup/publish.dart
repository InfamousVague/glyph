/// "Publish as a website" (decision 4, docs/MARKDOWN_FIRST.md §11; the publisher is tauri/publish/, its README says
/// how it is vendored): with the switch on, for a GitHub remote, the plugin commits
///
/// - `.glyph/publish/` with the publisher's `bin/ghost-publish.mjs`, `dist/ghost-publish.js` and `templates/`, copied
///   from the app's assets (assets/publish/, written by tool/publish-assets.sh at release from tauri/publish/), so the
///   repository builds its site with the renderer that matched the app that wrote it, with Node alone. Rewritten
///   only when the vendored version changes (`.glyph/publish/VERSION`), so the 2 MB bundle does not churn the history;
/// - `.github/workflows/ghost-pages.yml`, the publisher's template: every push to `main` builds the site and deploys
///   it to Pages, once Pages is turned on in the repository's settings with GitHub Actions as the source;
/// - `publish.json` at the root, with the site's title and its address, written once and never over the person's own.
///
/// With the switch off the workflow is taken out, and `.glyph/publish/` with it; `publish.json` stays, since a person
/// may have written it. The page says where the site will be ([pagesSiteFor]).
///
/// In a build without the assets (a developer's, before the script ran) the workflow is still written, with a line
/// saying the publisher's files are missing, so nothing is silently half done.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'settings.dart';

/// Where the publisher's files are in the app's assets, and in the repository.
const String publishAssets = 'assets/publish';
const String publishVendored = '.glyph/publish';
const String pagesWorkflowPath = '.github/workflows/ghost-pages.yml';

/// The files vendored, by their path under `.glyph/publish/`, each to its flat name in the assets (one folder, so
/// the asset folder can be declared empty and filled by the script).
const Map<String, String> publishFiles = {'bin/ghost-publish.mjs': 'ghost-publish.mjs', 'dist/ghost-publish.js': 'ghost-publish.js', 'templates/github-pages.yml': 'github-pages.yml'};

/// The publisher's files as the app carries them: each by its path, and the version they are.
class PublishBundle {
  const PublishBundle({required this.version, required this.files});
  final String version;
  final Map<String, Uint8List> files;

  Uint8List? get workflow => files['templates/github-pages.yml'];
}

/// The bundle from the app's assets, or null in a build without them.
Future<PublishBundle?> publishBundleFromAssets() async {
  try {
    final version = (await rootBundle.loadString('$publishAssets/VERSION')).trim();
    final files = <String, Uint8List>{};
    for (final MapEntry(key: path, value: asset) in publishFiles.entries) {
      final data = await rootBundle.load('$publishAssets/$asset');
      files[path] = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    return PublishBundle(version: version, files: files);
  } catch (_) {
    return null;
  }
}

/// The workflow written where the bundle is missing: the template's shape, with the truth said.
const String missingBundleWorkflow = '''
# Ghost.md: publishes this library as a website with GitHub Pages. Written by the Back up to git plugin.
# This build of Ghost.md carried no copy of the publisher (.glyph/publish/ is not here), so the site is not built yet:
# back up again from a release build, which vendors it, and this file is replaced by the publisher's own workflow.
name: Publish the library
on:
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: read
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Ghost.md's publisher is not vendored in this repository yet; back up from a release build of Ghost.md."
''';

/// What one pass wrote.
class PublishOutcome {
  const PublishOutcome({this.vendored = false, this.workflow = false, this.config = false, this.removed = false, this.missingBundle = false});
  final bool vendored;
  final bool workflow;
  final bool config;
  final bool removed;
  final bool missingBundle;
}

/// Writes or removes the publishing files at [repoPath] for [settings] (see the header). [bundle] is the app's;
/// [title] the site's, for a fresh `publish.json`.
PublishOutcome writePublishing(String repoPath, GitBackupSettings settings, {required PublishBundle? bundle, required String title}) {
  final workflow = File('$repoPath/$pagesWorkflowPath');
  final vendored = Directory('$repoPath/$publishVendored');
  if (!settings.publish || !isGitHubRemote(settings.remote)) {
    var removed = false;
    if (workflow.existsSync()) {
      workflow.deleteSync();
      removed = true;
    }
    if (vendored.existsSync()) {
      vendored.deleteSync(recursive: true);
      removed = true;
    }
    return PublishOutcome(removed: removed);
  }
  var wroteVendored = false;
  var wroteWorkflow = false;
  var wroteConfig = false;
  if (bundle != null) {
    final versionFile = File('${vendored.path}/VERSION');
    final have = versionFile.existsSync() ? versionFile.readAsStringSync().trim() : null;
    if (have != bundle.version || publishFiles.keys.any((path) => !File('${vendored.path}/$path').existsSync())) {
      for (final MapEntry(key: path, value: bytes) in bundle.files.entries) {
        File('${vendored.path}/$path')
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(bytes);
      }
      versionFile
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('${bundle.version}\n');
      wroteVendored = true;
    }
  }
  final workflowText = bundle?.workflow == null ? missingBundleWorkflow : String.fromCharCodes(bundle!.workflow!);
  if (!workflow.existsSync() || workflow.readAsStringSync() != workflowText) {
    workflow.parent.createSync(recursive: true);
    workflow.writeAsStringSync(workflowText);
    wroteWorkflow = true;
  }
  final config = File('$repoPath/publish.json');
  if (!config.existsSync()) {
    final base = pagesSiteFor(settings.remote);
    config.writeAsStringSync('{\n  "title": ${_json(title)},\n  "description": "Notes written with Ghost.md"${base == null ? '' : ',\n  "baseUrl": ${_json(base)}'},\n  "orgs": false\n}\n');
    wroteConfig = true;
  }
  return PublishOutcome(vendored: wroteVendored, workflow: wroteWorkflow, config: wroteConfig, missingBundle: bundle == null);
}

String _json(String text) => '"${text.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
