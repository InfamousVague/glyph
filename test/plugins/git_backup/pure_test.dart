// The git backup's parts that need no core (lib/plugins/git_backup; Matt, 2026-10-31): where the repository may be and
// the refusals (iCloud Drive, Dropbox, OneDrive, Google Drive, a SAF tree's mirror), the generated .gitignore and
// README.txt, the attachments brought in with the recordings cap, the sizes, the commit messages, the settings and the
// committed config with its secret guard, the merge's pure rules (a conflict copy's fresh id, the versions, the config
// key by key), the pusher claim on two devices, and what Publish writes.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/summary_handoff.dart' show SummaryDevice;
import 'package:ghost_md/core/library_folder.dart' show LibraryStatus;
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/versions_file.dart' show readFile, withVersion;
import 'package:ghost_md/files/attachment_places.dart';
import 'package:ghost_md/plugins/git_backup/git_backup.dart';
import 'package:ghost_md/plugins/host.dart';

import 'support.dart';

void main() {
  group('where the repository is', () {
    test('a syncing folder is told by its path, and refused in a sentence that says what to do', () {
      expect(syncingFolder('/Users/matt/Library/Mobile Documents/com~apple~CloudDocs/Notes'), 'iCloud Drive');
      expect(syncingFolder('/Users/matt/Dropbox/Notes'), 'Dropbox');
      expect(syncingFolder('/Users/matt/Library/CloudStorage/OneDrive-Personal/Notes'), 'OneDrive');
      expect(syncingFolder('/Users/matt/Library/CloudStorage/GoogleDrive-me@gmail.com/My Drive/Notes'), 'Google Drive');
      expect(syncingFolder('/Users/matt/Google Drive/Notes'), 'Google Drive');
      expect(syncingFolder('/Users/matt/Documents/Notes'), isNull);
      expect(libraryRefusal('/Users/matt/Dropbox/Notes'), allOf(contains('Dropbox'), contains('Settings › Library folder'), contains('set this up again')));
      expect(libraryRefusal('/Users/matt/Notes'), isNull);
    });

    test('the app’s own folder and a chosen plain folder hold .git; a SAF tree gets a mirror; an unreachable folder and a syncing one are refused', () {
      final own = placeFor(const LibraryStatus(kind: 'app', own: '/data/Library'), mirrorRoot: '/data/git/library');
      expect((own.place!.kind, own.place!.path, own.place!.libraryPath, own.refusal), (RepoKind.library, '/data/Library', '/data/Library', null));
      final chosen = placeFor(const LibraryStatus(kind: 'folder', path: '/Users/matt/Notes', own: '/data/Library'), mirrorRoot: '/data/git/library');
      expect((chosen.place!.kind, chosen.place!.path), (RepoKind.library, '/Users/matt/Notes'));
      final tree = placeFor(const LibraryStatus(kind: 'tree', name: 'Notes', own: '/data/Library'), mirrorRoot: '/data/git/library');
      expect((tree.place!.kind, tree.place!.path, tree.place!.isMirror, tree.place!.libraryPath), (RepoKind.mirror, '/data/git/library', true, null));
      final gone = placeFor(const LibraryStatus(kind: 'folder', path: '/Volumes/Drive/Notes', reachable: false), mirrorRoot: '/data/git/library');
      expect(gone.place, isNull);
      expect(gone.refusal, contains('can’t be reached'));
      final cloud = placeFor(const LibraryStatus(kind: 'folder', path: '/Users/matt/Library/Mobile Documents/com~apple~CloudDocs/Notes'), mirrorRoot: '/data/git/library');
      expect(cloud.place, isNull);
      expect(cloud.refusal, contains('iCloud Drive'));
      expect(mirrorExplained, contains('copy of it kept inside Ghost.md'));
    });
  });

  group('the generated files', () {
    test('.gitignore: the index and its journals, films always, recordings while off, each organization not included; .glyph/notes is kept', () {
      final off = gitignoreText(const GitBackupSettings(), orgs: ['Acme', 'Beta Corp']);
      expect(off, contains('.glyph/index.sqlite\n'));
      expect(off, contains('.glyph/index.sqlite-wal\n'));
      expect(off, contains('.DS_Store\n'));
      expect(off, contains('video/\n'));
      expect(off, contains('recordings/\n'));
      expect(off, contains('orgs/Acme/\n'));
      expect(off, contains('orgs/Beta\\ Corp/\n'), reason: 'a space escaped as a pattern reads it');
      expect(off, isNot(contains('.glyph/notes')));
      final on = gitignoreText(const GitBackupSettings(recordings: true, orgsIncluded: {'Acme'}), orgs: ['Acme', 'Beta Corp']);
      expect(on, isNot(contains('recordings/')));
      expect(on, isNot(contains('orgs/Acme/')));
      expect(on, contains('orgs/Beta\\ Corp/'));
    });

    test('the README is README.txt, never a note, and says what the repository is, how to restore, and that it is plain text', () {
      final text = readmeText(madeBy: 'matt');
      expect(text, contains('Ghost.md library'));
      expect(text, contains('Open library from git'));
      expect(text, contains('anyone who can read the repository can read the notes'));
      expect(text, contains('Made by matt'));
      // The dot folders are never indexed as notes: the vault's walk skips them, `.trash/` alone read as the Trash
      // (vault.rs `markdown()`, trash.rs), so `.git/` holds no notes and `.trash/` holds trashed ones.
      // The mirror writer here keeps the same rule.
      final dir = tempFolder('readme');
      addTearDown(() => dir.deleteSync(recursive: true));
      write(dir.path, '.git/a.md', 'not a note');
      write(dir.path, '.trash/b.md', 'not a note');
      write(dir.path, 'Inbox/stale.md', 'gone from the library');
      writeMirror(dir.path, const []);
      expect(exists(dir.path, '.git/a.md'), isTrue, reason: 'dot folders are left alone');
      expect(exists(dir.path, '.trash/b.md'), isTrue);
      expect(exists(dir.path, 'Inbox/stale.md'), isFalse, reason: 'a note gone from the library goes from the mirror');
    });

    test('attachments come in at the names the notes link, recordings only when on and under the cap, and go when the app lost them', () {
      final root = tempFolder('attachments');
      addTearDown(() => root.deleteSync(recursive: true));
      final fixture = fixtureLibrary(root);
      // The old places: every kind beside the app's data, as a build before 2.3.94 had them.
      final map = AttachmentMap(repoPath: fixture.library, places: AttachmentPlaces.legacy(fixture.appData));
      var refused = map.bring(const GitBackupSettings(recordings: false, recordingsMaxBytes: 100));
      expect(refused, isEmpty);
      expect(File('${fixture.library}/image/pic.jpg').readAsBytesSync(), [0xff, 0xd8, 1, 2, 3]);
      expect(exists(fixture.library, 'file/doc.pdf'), isTrue);
      expect(exists(fixture.library, 'recordings'), isFalse, reason: 'off');
      refused = map.bring(const GitBackupSettings(recordings: true, recordingsMaxBytes: 100));
      expect(refused, ['recordings/long.wav'], reason: 'over the cap, named');
      expect(exists(fixture.library, 'recordings/short.wav'), isTrue);
      expect(exists(fixture.library, 'recordings/long.wav'), isFalse);
      File('${fixture.appData}/images/pic.jpg').deleteSync();
      map.bring(const GitBackupSettings(recordings: true, recordingsMaxBytes: 100));
      expect(exists(fixture.library, 'image/pic.jpg'), isFalse, reason: 'gone from the app, gone from the repository');
      // The other way, after a clone.
      final other = '${realPath(root)}/other-data';
      expect(AttachmentMap(repoPath: fixture.library, places: AttachmentPlaces.legacy(other)).restore(), 2);
      expect(exists(other, 'images/files/doc.pdf'), isTrue);
      expect(exists(other, 'recordings/short.wav'), isTrue);
      // The attachments slice's places: pictures settled under the Library (nothing copied, nothing deleted), files
      // read from both (the repository's folder is read, so nothing is taken out of it either).
      final settled = AttachmentPlaces(image: ['${fixture.library}/image'], file: ['${fixture.appData}/images/files', '${fixture.library}/file'], video: ['${fixture.appData}/video'], recording: ['${fixture.appData}/recordings', '${fixture.library}/recordings']);
      writeBytes(fixture.library, 'image/own.jpg', [1]);
      writeBytes(fixture.library, 'file/written-here.pdf', [2]);
      AttachmentMap(repoPath: fixture.library, places: settled).bring(const GitBackupSettings());
      expect(exists(fixture.library, 'image/own.jpg'), isTrue, reason: 'the Library’s own pictures are the repository’s');
      expect(exists(fixture.library, 'file/written-here.pdf'), isTrue, reason: 'a file a newer build wrote under the Library stays');
      expect(exists(fixture.library, 'file/doc.pdf'), isTrue, reason: 'and the one beside the app’s data is brought in');
      expect(AttachmentMap(repoPath: fixture.library, places: settled).restore(), 1, reason: 'pictures are written where they are; of the files, the one a newer build wrote under the Library goes beside the app, where this build writes');
    });

    test('the sizes count what a commit takes, and what the switches leave out', () {
      final root = tempFolder('sizes');
      addTearDown(() => root.deleteSync(recursive: true));
      final fixture = fixtureLibrary(root);
      final sizes = repoSizes(repoPath: fixture.library, places: AttachmentPlaces.legacy(fixture.appData), settings: const GitBackupSettings(), orgs: ['Acme']);
      expect(sizes.committed.files, 5, reason: 'Plan.md, Plan.versions, Standup.md, pic.jpg and doc.pdf; the dot folder and the film are not counted, Acme is left out');
      expect(sizes.recordings.bytes, 220);
      expect(sizes.orgsExcluded.files, 1);
      expect(sizes.video.bytes, 'a film'.length);
      expect(sizeWords(12), '12 B');
      expect(sizeWords(2048), '2.0 kB');
      expect(sizeWords(1500000), '1.5 MB');
      expect(sizeWords(250000000), '250 MB');
      expect(orgFoldersAt(fixture.library), ['Acme']);
    });
  });

  group('commit messages', () {
    test('one note each kind, several, and changes with no note in them', () {
      expect(commitMessage([const GitChange('Inbox/Plan.md', 'modified')]), 'Edit: Plan');
      expect(commitMessage([const GitChange('Inbox/Plan.md', 'added')]), 'New: Plan');
      expect(commitMessage([const GitChange('Inbox/Plan.md', 'removed')]), 'Deleted: Plan');
      expect(commitMessage([const GitChange('workspaces/Work/Plan.md', 'renamed', from: 'Inbox/Plan.md')]), 'Moved: Plan');
      expect(commitMessage([const GitChange('.trash/Inbox/Plan.md', 'added')]), 'Trashed: Plan');
      expect(commitMessage([const GitChange('Inbox/Plan.md', 'modified'), const GitChange('Inbox/Plan.versions', 'modified')]), 'Edit: Plan', reason: 'the versions ride with the note');
      expect(commitMessage([const GitChange('Inbox/A.md', 'modified'), const GitChange('Inbox/B.md', 'added'), const GitChange('Inbox/C.md', 'modified')]), '3 notes changed: A, B…');
      expect(commitMessage([const GitChange('Inbox/A.md', 'added'), const GitChange('Inbox/B.md', 'added')]), 'New: A, B');
      expect(commitMessage([const GitChange('Inbox/A.md', 'removed'), const GitChange('Inbox/B.md', 'removed'), const GitChange('Inbox/C.md', 'removed')]), 'Deleted: A, B…');
      expect(commitMessage([const GitChange('Inbox/A.md', 'modified')], titleOf: (_) => 'The real title'), 'Edit: The real title');
      expect(commitMessage([const GitChange('image/x.jpg', 'added')]), 'A picture');
      expect(commitMessage([const GitChange('image/x.jpg', 'added'), const GitChange('image/y.jpg', 'added')]), '2 pictures');
      expect(commitMessage([const GitChange('.gitignore', 'modified'), const GitChange('.glyph/config.json', 'added')]), 'Library settings');
      expect(commitMessage([const GitChange('Inbox/Plan.versions', 'modified')]), 'History of Plan');
      expect(mergeMessage(theirs: 1, conflicts: 0), 'Merge a commit from the remote');
      expect(mergeMessage(theirs: 3, conflicts: 2), 'Merge 3 commits from the remote, 2 conflict copies kept');
    });
  });

  group('settings', () {
    test('round through JSON, and the committed config carries no secret and no device state', () {
      final settings = GitBackupSettings(remote: 'https://github.com/matt/notes.git', recordings: true, recordingsMaxBytes: 5, orgsIncluded: const {'Acme'}, publish: true, authUser: 'x-access-token', repoPath: '/x', lastPushAt: DateTime.utc(2026, 10, 31, 12), conflicts: const ['Inbox/Plan (conflict from git).md']);
      final back = GitBackupSettings.fromJson(settings.toJson());
      expect((back.remote, back.recordings, back.recordingsMaxBytes, back.publish, back.authUser, back.repoPath, back.lastPushAt), ('https://github.com/matt/notes.git', true, 5, true, 'x-access-token', '/x', DateTime.utc(2026, 10, 31, 12)));
      expect(back.orgsIncluded, {'Acme'});
      expect(back.conflicts, ['Inbox/Plan (conflict from git).md']);
      final config = settings.toConfigJson(madeBy: 'matt');
      expect(config.keys, unorderedEquals(['remote', 'branch', 'recordings', 'orgs', 'publish', 'cadence', 'madeBy']));
      expect(GitBackupSettings.fromJson(null).configured, isFalse);
    });

    test('config.json takes the git key beside the others, refuses a secret, and reads back for a clone', () {
      final dir = tempFolder('config');
      addTearDown(() => dir.deleteSync(recursive: true));
      write(dir.path, '.glyph/config.json', '{"version": 1, "workspaces": {"Work": {"hue": "moss"}}}\n');
      writeGitConfig(dir.path, const GitBackupSettings(remote: 'https://gitlab.com/me/notes.git', orgsIncluded: {'Acme'}), madeBy: 'matt');
      final text = read(dir.path, '.glyph/config.json');
      expect(text, contains('"hue": "moss"'));
      expect(text, contains('"remote": "https://gitlab.com/me/notes.git"'));
      final back = readGitConfig(dir.path)!;
      expect(back.remote, 'https://gitlab.com/me/notes.git');
      expect(back.orgsIncluded, {'Acme'});
      expect(() => writeGitConfig(dir.path, const GitBackupSettings(remote: 'https://x.com/a.git?token=abc'), madeBy: 'matt'), throwsStateError);
      expect(readGitConfig('${dir.path}/nowhere'), isNull);
    });

    test('the shapes, the hosts and the auth user', () {
      expect(remoteShape(''), contains('Paste'));
      expect(remoteShape('git@github.com:me/notes.git'), contains('SSH'));
      expect(remoteShape('http://github.com/me/notes.git'), contains('HTTPS'));
      expect(remoteShape('https://github.com'), contains('needs the repository'));
      expect(remoteShape('https://github.com/me/notes.git'), isNull);
      expect(gitTokenShape('a b'), contains('no spaces'));
      expect(gitTokenShape('short'), contains('cut short'));
      expect(gitTokenShape('github_pat_abcdefghijkl'), isNull);
      expect(remoteHostName('https://github.com/me/notes.git'), 'GitHub');
      expect(remoteHostName('https://gitlab.com/me/notes.git'), 'GitLab');
      expect(remoteHostName('https://codeberg.org/me/notes.git'), 'Codeberg');
      expect(remoteHostName('https://git.example.org/me/notes.git'), 'git.example.org');
      expect(authUserFor('https://github.com/me/notes.git'), 'x-access-token');
      expect(authUserFor('https://gitlab.com/me/notes.git'), 'oauth2');
      expect(authUserFor('https://git.example.org/me/notes.git'), 'git');
      expect(remoteShort('https://github.com/me/notes.git'), 'me/notes');
      expect(pagesSiteFor('https://github.com/Me/notes.git'), 'https://me.github.io/notes/');
      expect(pagesSiteFor('https://gitlab.com/me/notes.git'), isNull);
      expect(isGitHubRemote(null), isFalse);
    });
  });

  group('the merge’s rules', () {
    test('a conflict copy carries a FRESH id, written into front matter it had or did not have', () {
      final had = conflictCopyText('---\nid: aaaa\ntitle: Plan\n---\n# Plan\n', id: 'bbbb');
      expect(had, '---\nid: bbbb\ntitle: Plan\n---\n# Plan\n');
      expect(noteIdOf(had), 'bbbb');
      final none = conflictCopyText('# Plan\n\nwords\n', id: 'cccc');
      expect(none, startsWith('---\nid: cccc\n---\n# Plan'));
      final made = conflictCopyText('---\nid: aaaa\n---\n# Plan\n');
      expect(noteIdOf(made), allOf(isNot('aaaa'), hasLength(36)));
      expect(conflictCopyPath('Inbox/Plan.md', exists: (_) => false), 'Inbox/Plan (conflict from git).md');
      expect(conflictCopyPath('Inbox/Plan.md', exists: (p) => p == 'Inbox/Plan (conflict from git).md'), 'Inbox/Plan (conflict from git) 2.md');
      expect(isConflictCopy('Inbox/Plan (conflict from git).md'), isTrue);
    });

    test('versions merge every version of both sides once; the config merges key by key, last writer where both changed', () {
      // Two devices' files of one note, each a version kept from the same first one (lib/core/versions_file.dart).
      final first = withVersion(null, 'n1', '# Plan\n', at: DateTime.utc(2026, 10, 31, 10).millisecondsSinceEpoch, by: 'matt')!;
      final mine = withVersion(first, 'n1', '# Plan\n\nmine\n', at: DateTime.utc(2026, 10, 31, 11).millisecondsSinceEpoch, by: 'matt')!;
      final theirs = withVersion(first, 'n1', '# Plan\n\ntheirs\n', at: DateTime.utc(2026, 10, 31, 10, 30).millisecondsSinceEpoch, by: 'phone')!;
      final merged = mergedVersions(mine, theirs);
      expect(merged, allOf(contains('+mine'), contains('+theirs')));
      expect(readFile(merged)!.versions.length, 3, reason: 'the shared first once, then each side’s');
      expect(mergedVersions(mine, 'not a versions file'), mine);
      final config = mergedConfig('{"version": 1, "a": 1, "b": 1}', '{"version": 1, "a": 2, "b": 1, "mine": true}', '{"version": 1, "a": 3, "b": 1, "theirs": true}');
      expect(config, contains('"a": 3'));
      expect(config, allOf(contains('"mine": true'), contains('"theirs": true')));
      expect(mergedConfig('{"a": 1}', '{"a": 2}', '{"a": 3}', theirsNewer: false), contains('"a": 2'));
      expect(mergedConfig('{"a": 1}', '{}', '{"a": 1}'), isNot(contains('"a"')), reason: 'we took it out, they left it');
      expect(isTextPath('Inbox/x.canvas'), isTrue);
      expect(isTextPath('image/x.jpg'), isFalse);
    });
  });

  group('one pusher', () {
    test('two devices of one account: the first to claim pushes, the other sees it elsewhere, a stale claim passes, release lets go', () async {
      var account = <String, Object?>{};
      var now = DateTime.utc(2026, 10, 31, 12).millisecondsSinceEpoch;
      PusherClaims deviceOf(String id, String name, {bool phone = false}) {
        var prefs = const Preferences();
        return PusherClaims(
          device: () => SummaryDevice(id: id, name: name),
          // What the device reads: the account’s copy as the sync holds it over this device’s own (the account’s is
          // what every device is told; a release on one device reaches the others through it).
          preferences: () => prefs.copyWith(more: {...prefs.more, ...account}),
          setPreferences: (change) => prefs = change(prefs.copyWith(more: {...prefs.more, ...account})),
          // The sync: the account's copy takes a live claim of another's over mine (lib/sync/prefs.dart `merged`).
          syncNow: () async {
            final merged = chosenPusherClaim(prefs.more[pusherClaimKey], account[pusherClaimKey], now: now);
            account = {...account, pusherClaimKey: ?merged};
            prefs = prefs.copyWith(more: {...prefs.more, pusherClaimKey: ?merged});
          },
          accountHeld: () => account,
          isPhone: phone,
          clock: () => now,
          warn: (_) {},
        );
      }

      final mac = deviceOf('mac1', 'Mac');
      final phone = deviceOf('ph1', 'phone', phone: true);
      expect(await mac.holds(), isTrue);
      expect(await phone.holds(), isFalse, reason: 'the Mac got there first');
      expect(phone.elsewhere()?.name, 'Mac');
      expect(mac.elsewhere(), isNull);
      // Still the Mac's after a while; renewed as it ages.
      now += pusherRenewMs + 1;
      expect(await mac.holds(), isTrue);
      expect(PusherClaim.fromJson(account[pusherClaimKey])!.at, lessThanOrEqualTo(now));
      // The Mac goes quiet a day: the claim is stale, and the phone, after deferring to a desktop, takes it.
      now += pusherClaimMs + 1;
      expect(await phone.holds(), isFalse, reason: 'a phone waits for a desktop first');
      now += phoneDefers.inMilliseconds + 1;
      expect(await phone.holds(), isTrue);
      expect(await mac.holds(), isFalse);
      phone.release();
      account.remove(pusherClaimKey);
      expect(await mac.holds(), isTrue);
      // The merge rule on its own.
      final mine = PusherClaim(by: 'a', at: now).toJson();
      final theirs = PusherClaim(by: 'b', at: now).toJson();
      expect(chosenPusherClaim(mine, theirs, now: now), theirs);
      expect(chosenPusherClaim(mine, PusherClaim(by: 'b', at: now - pusherClaimMs - 1).toJson(), now: now), mine);
      expect(chosenPusherClaim(mine, null, now: now), mine);
    });
  });

  group('publish', () {
    test('with the switch on for a GitHub remote, the publisher is vendored once a version, the workflow and publish.json written; off, taken out', () {
      final dir = tempFolder('publish');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bundle = PublishBundle(version: '0.1.0+abc', files: {'bin/ghost-publish.mjs': Uint8List.fromList([1, 2]), 'dist/ghost-publish.js': Uint8List.fromList([3, 4, 5]), 'templates/github-pages.yml': Uint8List.fromList('name: Publish\n'.codeUnits)});
      const on = GitBackupSettings(remote: 'https://github.com/me/notes.git', publish: true);
      var wrote = writePublishing(dir.path, on, bundle: bundle, title: 'matt’s notes');
      expect((wrote.vendored, wrote.workflow, wrote.config), (true, true, true));
      expect(read(dir.path, '.glyph/publish/VERSION').trim(), '0.1.0+abc');
      expect(File('${dir.path}/.glyph/publish/dist/ghost-publish.js').readAsBytesSync(), [3, 4, 5]);
      expect(read(dir.path, pagesWorkflowPath), 'name: Publish\n');
      expect(read(dir.path, 'publish.json'), allOf(contains('"title": "matt’s notes"'), contains('"baseUrl": "https://me.github.io/notes/"'), contains('"orgs": false')));
      // Again, nothing rewritten; the person's publish.json is left alone.
      write(dir.path, 'publish.json', '{"title": "Mine"}\n');
      wrote = writePublishing(dir.path, on, bundle: bundle, title: 'x');
      expect((wrote.vendored, wrote.workflow, wrote.config), (false, false, false));
      expect(read(dir.path, 'publish.json'), '{"title": "Mine"}\n');
      // A newer bundle: vendored again.
      wrote = writePublishing(dir.path, on, bundle: PublishBundle(version: '0.2.0+def', files: bundle.files), title: 'x');
      expect(wrote.vendored, isTrue);
      // No bundle in this build: the workflow says so.
      wrote = writePublishing(dir.path, on, bundle: null, title: 'x');
      expect(wrote.missingBundle, isTrue);
      expect(read(dir.path, pagesWorkflowPath), contains('not vendored in this repository yet'));
      // Off: the workflow and the vendored copy go; publish.json stays.
      wrote = writePublishing(dir.path, const GitBackupSettings(remote: 'https://github.com/me/notes.git'), bundle: bundle, title: 'x');
      expect(wrote.removed, isTrue);
      expect(exists(dir.path, pagesWorkflowPath), isFalse);
      expect(exists(dir.path, '.glyph/publish'), isFalse);
      expect(exists(dir.path, 'publish.json'), isTrue);
      // Not for GitLab.
      wrote = writePublishing(dir.path, const GitBackupSettings(remote: 'https://gitlab.com/me/notes.git', publish: true), bundle: bundle, title: 'x');
      expect(exists(dir.path, pagesWorkflowPath), isFalse);
    });

    test('the app’s assets carry the publisher once tool/publish-assets.sh has run, and read as a bundle', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final here = File('assets/publish/VERSION');
      final bundle = await publishBundleFromAssets();
      if (!here.existsSync()) {
        expect(bundle, isNull, reason: 'a build without the script’s files says so');
        return;
      }
      expect(bundle!.version, here.readAsStringSync().trim());
      expect(bundle.files.keys, unorderedEquals(publishFiles.keys));
      expect(String.fromCharCodes(bundle.workflow!), contains('node .glyph/publish/bin/ghost-publish.mjs'));
      expect(bundle.files['dist/ghost-publish.js']!.length, greaterThan(1000000));
    });
  });

  tearDown(() => usePluginGround(PluginGround()));
}
