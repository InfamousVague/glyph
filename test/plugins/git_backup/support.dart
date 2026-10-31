// What the git backup's tests share (lib/plugins/git_backup; Matt, 2026-10-31: "add a plugin to backup on git"): a
// fixture library on disk, a bare repository to push to by its file URL, the Mac's build of the core opened once, and
// the plugin's ground in memory. Nothing here reaches the network, Matt's account, GitHub or the box: every remote is a
// bare repository in a temp folder.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/files/attachment_places.dart';
import 'package:ghost_md/plugins/git_backup/git_backup.dart';
import 'package:ghost_md/plugins/host.dart';

import '../../team_sync/support.dart' show coreLibrary;
import '../support.dart';

export '../../team_sync/support.dart' show coreSkip;
export '../support.dart' show TestGround;

GhostCore? _core;

/// The core, opened once for the process (the git commands need no `init`).
Future<GhostCore> gitCore() async => _core ??= await GhostCore.open(libraryPath: File(coreLibrary).absolute.path);

/// A fresh temp folder, its symlinks resolved (the core answers real paths).
Directory tempFolder(String name) => Directory.systemTemp.createTempSync('ghost-git-$name-').absolute..resolveSymbolicLinksSync();

String realPath(Directory dir) => dir.resolveSymbolicLinksSync();

void write(String root, String relative, String text) {
  File('$root/$relative')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);
}

void writeBytes(String root, String relative, List<int> bytes) {
  File('$root/$relative')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

String read(String root, String relative) => File('$root/$relative').readAsStringSync();

bool exists(String root, String relative) => File('$root/$relative').existsSync() || Directory('$root/$relative').existsSync();

/// git on the Mac, for what the tests check of a repository the core wrote (the core itself needs no git).
Future<String> git(List<String> args, String cwd) async {
  final out = await Process.run('git', args, workingDirectory: cwd);
  expect(out.exitCode, 0, reason: 'git $args: ${out.stderr}');
  return (out.stdout as String).trim();
}

/// A bare repository at `<root>/remote.git`, by its file URL.
Future<String> bareRemote(String root) async {
  final path = '$root/remote.git';
  await git(['init', '--bare', '-b', 'main', path], root);
  return 'file://$path';
}

/// A library of a few notes, a versions file, an organization's note, the index, a film, and app data with a picture,
/// a file and two recordings (one over any small cap).
({String library, String appData}) fixtureLibrary(Directory root) {
  final library = '${realPath(root)}/Library';
  final appData = '${realPath(root)}/data';
  write(library, 'Inbox/Plan.md', '---\nid: 11111111-1111-4111-8111-111111111111\n---\n# Plan\n\nline one\nline two\nline three\n');
  write(library, 'Inbox/Plan.versions', '# Ghost.md versions 1\n# note 11111111-1111-4111-8111-111111111111\n\nv1 2026-10-31T10:00:00.000Z matt 00000001\n  +# Plan\n');
  write(library, 'workspaces/Work/Standup.md', '# Standup\n\n- yesterday\n- today\n');
  write(library, 'orgs/Acme/Team.md', '# Team\n\nthe team’s note\n');
  write(library, '.glyph/notes/11111111-1111-4111-8111-111111111111.json', '{"recordingMs": 1200}\n');
  write(library, '.glyph/library.json', '{"version": 1}\n');
  write(library, '.glyph/index.sqlite', 'the cache');
  write(library, 'video/film.mp4', 'a film');
  writeBytes(appData, 'images/pic.jpg', [0xff, 0xd8, 1, 2, 3]);
  writeBytes(appData, 'images/files/doc.pdf', [0x25, 0x50, 0x44, 0x46]);
  writeBytes(appData, 'recordings/short.wav', List.filled(20, 7));
  writeBytes(appData, 'recordings/long.wav', List.filled(200, 7));
  return (library: library, appData: appData);
}

/// What a test has of the plugin's surroundings: its ground, the activity record of its own, and every job that
/// ended on it (a done job leaves the record for the log, so the words it ended with are kept here).
class GitTestGround {
  GitTestGround(this.ground, this.record) {
    record.events.listen((event) {
      if (event.kind == JobEventKind.ended && event.job != null) ended.add(event.job!);
    });
  }

  final TestGround ground;
  final Activity record;
  final List<Job> ended = [];
}

/// The plugin's ground in memory, the activity record of this test's own, and the settings at [remote].
GitTestGround gitGround({String? remote, bool recordings = false, Set<String> orgs = const {}}) {
  useStored(MemoryStored());
  final ground = TestGround();
  usePluginGround(ground.ground);
  final record = Activity(store: MemoryStored.new);
  useActivity(record);
  setGitBackupSettings(GitBackupSettings(remote: remote, recordings: recordings, recordingsMaxBytes: 100, orgsIncluded: orgs));
  return GitTestGround(ground, record);
}

/// Waits for [done] to hold, polling, or fails after [most].
Future<void> until(bool Function() done, {Duration most = const Duration(seconds: 10), String what = 'the condition'}) async {
  final start = DateTime.now();
  while (!done()) {
    if (DateTime.now().difference(start) > most) fail('$what did not happen within $most');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// A backup engine over [library] at [appData], pushing to [remote] through the real core.
Future<GitBackup> engine({required String library, required String appData, bool holdsPusher = true, PusherClaim? elsewhere, Duration quietFor = const Duration(hours: 1), Duration floorAt = const Duration(hours: 2), bool isPhone = false, int phoneMost = phonePushMost, bool foregroundOnly = false, bool Function()? inForeground, String handle = 'matt', Activity? record, PublishBundle? publish}) async {
  final core = await gitCore();
  return GitBackup(
    invoke: core.invoke,
    place: () async => RepoPlace(kind: RepoKind.library, path: library, libraryPath: library),
    handle: () => handle,
    holdsPusher: () async => holdsPusher,
    pusherElsewhere: () => elsewhere,
    auth: () async => GitAuth.none,
    appData: appData,
    // The old places, every kind beside the app's data: what the mapper has the most to do with.
    places: () async => AttachmentPlaces.legacy(appData),
    isPhone: isPhone,
    phoneMost: phoneMost,
    foregroundOnly: foregroundOnly,
    inForeground: inForeground,
    activity: record,
    quietFor: quietFor,
    floorAt: floorAt,
    publishBundle: () async => publish,
    warn: (_) {},
  );
}
