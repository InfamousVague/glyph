// The git backup end to end, over the Mac's build of the core and bare repositories on disk (lib/plugins/git_backup/
// backup.dart, merge.dart, restore.dart; Matt, 2026-10-31): init on a fixture library with the generated files and the
// attachments mapped in, a commit after quiet and the hourly floor, the messages, a push, a fetch and merge of a note
// both sides changed (merge_words where it can, a conflict copy with a FRESH id where it cannot), a picture both
// changed (theirs wins, ours beside), a note the remote deleted (to .trash/), an organization left out and taken in,
// recordings off and on with the cap, the pusher claim held elsewhere, a failure as a red row with Retry, an iPhone's
// foreground-only cadence, and a restore from a clone (folders, attachments, the organizations held aside, the
// config). Skipped where the core is not built (tool/build-native.sh host).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/files/attachment_places.dart';
import 'package:ghost_md/plugins/git_backup/git_backup.dart';
import 'package:ghost_md/plugins/host.dart';

import 'support.dart';

void main() {
  final skip = coreSkip;
  late Directory root;
  late String library;
  late String appData;
  late String remote;

  setUp(() async {
    root = tempFolder('backup');
    final fixture = fixtureLibrary(root);
    library = fixture.library;
    appData = fixture.appData;
    remote = await bareRemote(realPath(root));
  });

  tearDown(() {
    usePluginGround(PluginGround());
    root.deleteSync(recursive: true);
  });

  Future<String> remoteFile(String path) => git(['show', 'main:$path'], '${realPath(root)}/remote.git');
  Future<List<String>> remoteFiles() async => (await git(['ls-tree', '-r', '--name-only', 'main'], '${realPath(root)}/remote.git')).split('\n');

  group('the first backup', () {
    test('init in the Library, the generated files, the attachments at the names the notes link, films and the index never, the organization and recordings left out; then the push', skip: skip, () async {
      final on = gitGround(remote: remote);
      final backup = await engine(library: library, appData: appData, record: on.record);
      final outcome = await backup.backUpNow(personStarted: true);
      expect(outcome.ok, isTrue, reason: '$outcome');
      expect(outcome.committed, isNotNull);
      expect(outcome.pushed, isTrue);
      expect(exists(library, '.git'), isTrue, reason: 'the repository is the Library folder');
      expect(read(library, 'README.txt'), contains('Ghost.md library'));
      expect(exists(library, 'README.md'), isFalse);
      expect(read(library, '.gitignore'), allOf(contains('.glyph/index.sqlite'), contains('recordings/'), contains('orgs/Acme/')));
      expect(read(library, '.glyph/config.json'), contains('"remote": "$remote"'));
      final files = await remoteFiles();
      expect(files, containsAll(['.gitignore', 'README.txt', 'Inbox/Plan.md', 'Inbox/Plan.versions', 'workspaces/Work/Standup.md', '.glyph/notes/11111111-1111-4111-8111-111111111111.json', '.glyph/library.json', '.glyph/config.json', 'image/pic.jpg', 'file/doc.pdf']));
      expect(files.where((f) => f.startsWith('orgs/') || f.startsWith('recordings/') || f.startsWith('video/') || f.contains('index.sqlite')), isEmpty);
      expect(await git(['log', '-1', '--format=%an <%ae>'], library), 'matt <matt@users.ghostmarkdown.com>');
      expect(gitBackupSettings().lastPushAt, isNotNull);
      final job = on.ended.single;
      expect((job.state, job.plugin), (JobState.done, 'git-backup'));
      expect(job.result?.words, 'Backed up');
      // Nothing changed: nothing committed, and the row says so quietly.
      final again = await backup.backUpNow();
      expect((again.committed, again.pushed), (null, false));
    });

    test('signed out the author is Ghost.md; the sizes name what is left out', skip: skip, () async {
      gitGround(remote: remote);
      final backup = await engine(library: library, appData: appData, handle: '');
      await backup.backUpNow();
      expect(await git(['log', '-1', '--format=%an <%ae>'], library), 'Ghost.md <ghost@localhost>');
      final status = await backup.status(sizes: true);
      expect(status.sizes!.recordings.bytes, 220);
      expect(status.sizes!.orgsExcluded.files, 1);
      expect(status.lastCommit?.name, 'Ghost.md');
      expect(status.divergence?.state, 'same');
    });
  });

  group('the cadence', () {
    test('a commit two minutes after the last change (here, after the test’s quiet), one for the whole spell, with the note’s title in the message', skip: skip, () async {
      gitGround(remote: remote);
      final backup = await engine(library: library, appData: appData, quietFor: const Duration(milliseconds: 150), floorAt: const Duration(seconds: 30));
      await backup.backUpNow();
      write(library, 'Inbox/Plan.md', '---\nid: 11111111-1111-4111-8111-111111111111\n---\n# Plan\n\nline one\nline two changed\nline three\n');
      backup.changed();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      write(library, 'Inbox/Plan.md', '---\nid: 11111111-1111-4111-8111-111111111111\n---\n# Plan\n\nline one\nline two changed twice\nline three\n');
      backup.changed();
      expect(backup.pending, isTrue);
      await until(() => !backup.pending && !backup.running && backup.last != null, what: 'the quiet commit');
      expect(backup.last!.committed, isNotNull);
      expect(await git(['log', '-1', '--format=%s'], library), 'Edit: Plan');
      expect(await git(['rev-list', '--count', 'HEAD'], library), '2', reason: 'one commit for the spell, not one a keystroke');
      backup.dispose();
    });

    test('the hourly floor commits while changes keep coming (here, the floor is short and the quiet long)', skip: skip, () async {
      gitGround(remote: remote);
      final backup = await engine(library: library, appData: appData, quietFor: const Duration(seconds: 30), floorAt: const Duration(milliseconds: 200));
      await backup.backUpNow();
      write(library, 'Inbox/New.md', '# New\n');
      backup.changed();
      for (var i = 0; i < 6; i += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        write(library, 'Inbox/New.md', '# New\n\n$i\n');
        backup.changed();
      }
      await until(() => backup.last?.committed != null && !backup.running, what: 'the floor commit');
      expect(await git(['log', '-1', '--format=%s'], library), 'New: New');
      backup.dispose();
    });

    test('on an iPhone a commit waits for the foreground and runs on resume', skip: skip, () async {
      gitGround(remote: remote);
      var front = false;
      final backup = await engine(library: library, appData: appData, quietFor: const Duration(milliseconds: 50), foregroundOnly: true, inForeground: () => front);
      await backup.backUpNow();
      write(library, 'Inbox/Plan.md', '# Plan\n\nchanged on the phone\n');
      backup.changed();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await git(['rev-list', '--count', 'HEAD'], library), '1', reason: 'behind another app, nothing runs');
      front = true;
      backup.resumed();
      await until(() => backup.last?.committed != null && !backup.running, what: 'the commit on resume');
      expect(await git(['log', '-1', '--format=%s'], library), 'Edit: Plan');
      backup.dispose();
    });

    test('deleted and moved notes in the message', skip: skip, () async {
      gitGround(remote: remote);
      final backup = await engine(library: library, appData: appData);
      await backup.backUpNow();
      File('$library/workspaces/Work/Standup.md').deleteSync();
      await backup.backUpNow();
      expect(await git(['log', '-1', '--format=%s'], library), 'Deleted: Standup');
      File('$library/Inbox/Plan.md').renameSync('$library/workspaces/Work/Plan.md');
      File('$library/Inbox/Plan.versions').renameSync('$library/workspaces/Work/Plan.versions');
      await backup.backUpNow();
      expect(await git(['log', '-1', '--format=%s'], library), 'Moved: Plan');
    });
  });

  group('two devices on one repository', () {
    /// A second device's clone at `<root>/b`, with a change committed and pushed through the core's git alone.
    Future<GitRepo> otherDevice(Future<void> Function(String path) change, {String message = 'from the other device'}) async {
      final core = await gitCore();
      final b = '${realPath(root)}/b';
      await GitRepo.clone(core.invoke, url: remote, into: b);
      await change(b);
      final repo = GitRepo(core.invoke, b);
      await repo.commit(message, const GitWho(name: 'phone', email: 'phone@users.ghostmarkdown.com'));
      await repo.push(GitAuth.none);
      return repo;
    }

    test('a note both devices changed on different lines is merged with merge_words, committed with two parents, and pushed', skip: skip, () async {
      gitGround(remote: remote);
      final backup = await engine(library: library, appData: appData);
      await backup.backUpNow();
      await otherDevice((b) async => write(b, 'Inbox/Plan.md', '---\nid: 11111111-1111-4111-8111-111111111111\n---\n# Plan\n\nline one\nline two (phone)\nline three\n'));
      write(library, 'Inbox/Plan.md', '---\nid: 11111111-1111-4111-8111-111111111111\n---\n# Plan (Mac)\n\nline one\nline two\nline three\n');
      final outcome = await backup.backUpNow();
      expect(outcome.ok, isTrue, reason: '$outcome');
      expect((outcome.merged, outcome.pushed), (1, true));
      expect(outcome.conflicts, isEmpty);
      expect(read(library, 'Inbox/Plan.md'), '---\nid: 11111111-1111-4111-8111-111111111111\n---\n# Plan (Mac)\n\nline one\nline two (phone)\nline three\n');
      expect(await remoteFile('Inbox/Plan.md'), contains('line two (phone)'));
      final parents = await git(['log', '-1', '--format=%P'], library);
      expect(parents.split(' '), hasLength(2), reason: 'the merge commit has both parents');
      expect(await git(['log', '-1', '--format=%s'], library), 'Merge a commit from the remote');
      expect(await git(['fsck', '--strict'], '${realPath(root)}/remote.git'), '');
    });

    test('the same line changed on both: ours stays, theirs is a new note beside it with a FRESH id and no sidecar; a note the remote deleted goes to .trash/', skip: skip, () async {
      final on = gitGround(remote: remote);
      final backup = await engine(library: library, appData: appData, record: on.record);
      await backup.backUpNow();
      await otherDevice((b) async {
        write(b, 'Inbox/Plan.md', '---\nid: 11111111-1111-4111-8111-111111111111\n---\n# Plan\n\nline one\nline two (phone)\nline three\n');
        File('$b/workspaces/Work/Standup.md').deleteSync();
      });
      write(library, 'Inbox/Plan.md', '---\nid: 11111111-1111-4111-8111-111111111111\n---\n# Plan\n\nline one\nline two (Mac)\nline three\n');
      final outcome = await backup.backUpNow(personStarted: true);
      expect(outcome.ok, isTrue, reason: '$outcome');
      expect(outcome.conflicts, ['Inbox/Plan (conflict from git).md']);
      expect(read(library, 'Inbox/Plan.md'), contains('line two (Mac)'));
      final copy = read(library, 'Inbox/Plan (conflict from git).md');
      expect(copy, contains('line two (phone)'));
      final id = noteIdOf(copy)!;
      expect(id, isNot('11111111-1111-4111-8111-111111111111'));
      expect(id, hasLength(36));
      expect(exists(library, '.glyph/notes/$id.json'), isFalse, reason: 'no sidecar for the copy');
      expect(exists(library, 'workspaces/Work/Standup.md'), isFalse);
      expect(exists(library, '.trash/workspaces/Work/Standup.md'), isTrue, reason: 'a note the remote deleted is trashed, never lost');
      expect(await remoteFiles(), contains('Inbox/Plan (conflict from git).md'));
      expect(gitBackupSettings().conflicts, ['Inbox/Plan (conflict from git).md']);
      final job = on.ended.last;
      expect(job.result?.words, 'Backed up, 1 commit merged in, 1 conflict copy');
      expect(job.result?.action, 'Open');
    });

    test('a picture both devices changed: theirs wins, ours kept beside it; one only they changed is taken', skip: skip, () async {
      gitGround(remote: remote);
      final backup = await engine(library: library, appData: appData);
      await backup.backUpNow();
      await otherDevice((b) async {
        writeBytes(b, 'image/pic.jpg', [9, 9, 9]);
        writeBytes(b, 'image/theirs.jpg', [5]);
      });
      writeBytes(appData, 'images/pic.jpg', [1, 1, 1, 1]);
      final outcome = await backup.backUpNow();
      expect(outcome.ok, isTrue, reason: '$outcome');
      expect(File('$library/image/pic.jpg').readAsBytesSync(), [9, 9, 9]);
      expect(File('$library/image/pic.conflict.jpg').readAsBytesSync(), [1, 1, 1, 1]);
      expect(File('$library/image/theirs.jpg').readAsBytesSync(), [5]);
    });

    test('only the device holding the pusher claim pushes; the other commits and says who pushes', skip: skip, () async {
      final on = gitGround(remote: remote);
      final backup = await engine(library: library, appData: appData, holdsPusher: false, elsewhere: const PusherClaim(by: 'mac1', name: 'Mac', at: 0), record: on.record);
      final outcome = await backup.backUpNow(personStarted: true);
      expect(outcome.committed, isNotNull);
      expect(outcome.pushed, isFalse);
      expect(outcome.elsewhere?.name, 'Mac');
      expect((await Process.run('git', ['rev-parse', '--verify', '-q', 'main'], workingDirectory: '${realPath(root)}/remote.git')).exitCode, isNot(0), reason: 'nothing on the remote');
      expect(on.ended.single.result?.words, 'Committed here; Mac pushes');
      final status = await backup.status();
      expect(status.elsewhere?.name, 'Mac');
    });
  });

  group('what is included', () {
    test('an organization is left out as HEAD last had it (never deleted), and committed once its switch is on', skip: skip, () async {
      gitGround(remote: remote);
      final backup = await engine(library: library, appData: appData);
      await backup.backUpNow();
      expect(await remoteFiles(), isNot(contains('orgs/Acme/Team.md')));
      updateGitBackupSettings((s) => s.copyWith(orgsIncluded: {'Acme'}));
      await backup.backUpNow();
      expect(await remoteFiles(), contains('orgs/Acme/Team.md'));
      expect(read(library, '.gitignore'), isNot(contains('orgs/Acme/')));
      // Off again, and the team's note changed here: the repository keeps what it had, and loses nothing.
      updateGitBackupSettings((s) => s.copyWith(orgsIncluded: const {}));
      write(library, 'orgs/Acme/Team.md', '# Team\n\nchanged on this device, not the team’s business\n');
      write(library, 'Inbox/Plan.md', '# Plan\n\nso there is a commit\n');
      await backup.backUpNow();
      expect(await remoteFile('orgs/Acme/Team.md'), '# Team\n\nthe team’s note');
    });

    test('recordings off by default; on, each under the cap, the one over it named', skip: skip, () async {
      gitGround(remote: remote);
      final backup = await engine(library: library, appData: appData);
      var outcome = await backup.backUpNow();
      expect(await remoteFiles(), isNot(anyElement(startsWith('recordings/'))));
      updateGitBackupSettings((s) => s.copyWith(recordings: true));
      outcome = await backup.backUpNow();
      expect(outcome.refused, ['recordings/long.wav']);
      final files = await remoteFiles();
      expect(files, contains('recordings/short.wav'));
      expect(files, isNot(contains('recordings/long.wav')));
    });

    test('Publish as a website vendors the publisher and commits the workflow and publish.json, for a GitHub remote only', skip: skip, () async {
      // The remote is a file URL here, so the switch does nothing; a GitHub address in the settings with the same
      // repository on disk is what the switch reads.
      gitGround(remote: remote);
      final bundle = PublishBundle(version: '1+t', files: {for (final path in publishFiles.keys) path: Uint8List.fromList('x'.codeUnits)});
      final backup = await engine(library: library, appData: appData, publish: bundle);
      updateGitBackupSettings((s) => s.copyWith(publish: true));
      await backup.backUpNow();
      expect(exists(library, pagesWorkflowPath), isFalse, reason: 'not GitHub');
      // Pointed at GitHub in name (no push happens: the fetch would fail, so the commit alone is checked).
      final core = await gitCore();
      updateGitBackupSettings((s) => s.copyWith(remote: 'https://github.com/me/notes.git'));
      final local = GitBackup(invoke: core.invoke, place: () async => RepoPlace(kind: RepoKind.library, path: library, libraryPath: library), handle: () => 'matt', holdsPusher: () async => false, auth: () async => GitAuth.none, appData: appData, places: () async => AttachmentPlaces.legacy(appData), publishBundle: () async => bundle, warn: (_) {});
      await local.backUpNow();
      expect(exists(library, pagesWorkflowPath), isTrue);
      expect(exists(library, '.glyph/publish/dist/ghost-publish.js'), isTrue);
      expect(read(library, 'publish.json'), contains('"baseUrl": "https://me.github.io/notes/"'));
      expect(await git(['ls-files', '.github', '.glyph/publish', 'publish.json'], library), contains('.glyph/publish/VERSION'));
    });
  });

  group('failures', () {
    test('a remote that cannot be reached is a red row with Retry and a plain cause, and the page keeps the sentence', skip: skip, () async {
      final on = gitGround(remote: 'https://127.0.0.1:9/nobody/nothing.git');
      final backup = await engine(library: library, appData: appData, record: on.record);
      final outcome = await backup.backUpNow(personStarted: true);
      expect(outcome.committed, isNotNull, reason: 'the commit is local and stands');
      expect(outcome.failure?.trouble, GitTrouble.noConnection);
      final job = on.record[backupJobId]!;
      expect(job.state, JobState.failed, reason: 'a failed job stays on the record for its Retry');
      expect(job.cause, 'The git host couldn’t be reached.');
      expect(job.fix?.kind, JobFixKind.retry);
      expect(gitBackupSettings().lastFailure, 'The git host couldn’t be reached.');
      expect(const GitFailure(GitTrouble.signIn, 'Sign-in refused: 401').plain, 'The git host didn’t accept the token.');
      expect(GitFailure.said('Not fast-forward: x').trouble, GitTrouble.notFastForward);
      expect(GitFailure.said('No repository: x').trouble, GitTrouble.noRepo);
    });

    test('a phone does not push more than 100 MB; the row says to use a Mac', skip: skip, () async {
      gitGround(remote: remote);
      write(library, 'Inbox/Big.md', 'x' * 2000);
      final backup = await engine(library: library, appData: appData, isPhone: true, phoneMost: 1000);
      final outcome = await backup.backUpNow();
      expect(outcome.committed, isNotNull);
      expect(outcome.failure?.message, contains('more than a phone pushes in one go'));
      expect(outcome.pushed, isFalse);
    });
  });

  group('restore', () {
    test('a clone opened as the library: the notes and folders, the attachments where the app reads them, the organizations held aside for the team, the config read; then deepened', skip: skip, () async {
      gitGround(remote: remote, orgs: {'Acme'});
      final backup = await engine(library: library, appData: appData);
      updateGitBackupSettings((s) => s.copyWith(recordings: true));
      await backup.backUpNow();
      write(library, 'Inbox/Plan.md', '# Plan\n\nsecond commit\n');
      await backup.backUpNow();
      final core = await gitCore();
      final fresh = '${realPath(root)}/fresh';
      final restore = GitRestore(invoke: core.invoke, appData: fresh, places: () async => AttachmentPlaces.legacy(fresh));
      final said = <String>[];
      final outcome = await restore.cloneInto(url: remote, into: '$fresh/git/clone', progress: said.add);
      expect(outcome.notes, 2, reason: 'Plan and Standup; the team’s note is held aside');
      expect(outcome.orgsHeld, ['Acme']);
      expect(exists('$fresh/git/clone', 'orgs/Acme/Team.md'), isFalse);
      expect(exists(fresh, 'git/held/Acme/Team.md'), isTrue);
      expect(exists('$fresh/git/clone', 'workspaces/Work/Standup.md'), isTrue);
      expect(exists('$fresh/git/clone', 'Inbox/Plan.versions'), isTrue);
      expect(exists('$fresh/git/clone', '.glyph/notes/11111111-1111-4111-8111-111111111111.json'), isTrue);
      expect(outcome.attachments, 3, reason: 'the picture, the file and the short recording');
      expect(exists(fresh, 'images/pic.jpg'), isTrue);
      expect(exists(fresh, 'recordings/short.wav'), isTrue);
      expect(outcome.settings!.remote, remote);
      expect(outcome.settings!.orgsIncluded, isEmpty, reason: 'the held organization is off on this device');
      expect(outcome.settings!.recordings, isTrue);
      expect(said, contains('Cloning'));
      // Shallow first, then the whole history.
      final repo = GitRepo(core.invoke, '$fresh/git/clone');
      expect((await repo.status()).shallow, isTrue);
      expect(await repo.log(count: 10), hasLength(1));
      await restore.deepen('$fresh/git/clone', GitAuth.none);
      expect(await repo.log(count: 10), hasLength(2));
      // A commit from the fresh device keeps the held organization as the repository had it.
      write('$fresh/git/clone', 'Inbox/Plan.md', '# Plan\n\nfrom the fresh device\n');
      await repo.commit('Edit: Plan', const GitWho(name: 'matt', email: 'm@x'), keep: ['orgs/Acme']);
      expect(await git(['ls-tree', '-r', '--name-only', 'HEAD'], '$fresh/git/clone'), contains('orgs/Acme/Team.md'));
    });

    test('Import from a repo folder refuses a folder with no repository, and opens one made by hand', skip: skip, () async {
      gitGround(remote: remote);
      final backup = await engine(library: library, appData: appData);
      await backup.backUpNow();
      final core = await gitCore();
      final restore = GitRestore(invoke: core.invoke, appData: '${realPath(root)}/x', places: () async => AttachmentPlaces.legacy('${realPath(root)}/x'));
      await expectLater(restore.importFolder('${realPath(root)}/nowhere'), throwsA(isA<GitFailure>().having((f) => f.trouble, 'trouble', GitTrouble.noRepo)));
      final byHand = '${realPath(root)}/byhand';
      await git(['clone', '-q', remote, byHand], realPath(root));
      final outcome = await restore.importFolder(byHand);
      expect(outcome.notes, 2);
      expect(outcome.settings!.remote, remote);
    });
  });
}
