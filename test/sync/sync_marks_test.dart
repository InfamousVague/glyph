// Each note's sync mark (lib/sync/sync_marks.dart; docs/ACTIVITY.md, In place): read from what the sync keeps, told by
// the real note pass on the service in memory (lib/sync/notes.dart) and by hand for a team's channel.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/sync/notes.dart';
import 'package:ghost_md/sync/sync_marks.dart';

import 'support.dart';

void main() {
  setUp(forgetPictureAsks);

  late DateTime now;
  late NoteSyncMarks marks;
  setUp(() {
    now = DateTime(2026, 10, 29, 12);
    marks = NoteSyncMarks(clock: () => now)..syncing = () => true;
    useNoteSyncMarks(marks);
  });
  tearDown(() => useNoteSyncMarks(NoteSyncMarks()));

  group('from what the sync keeps', () {
    test('nothing for a note as it was sent; an arrow once it changes here; nothing for a blank one never sent', () {
      final sent = note('a', '# Plan\n\nwords', updatedAt: 1);
      marks.account(SyncState(notes: {'a': NoteMark(rev: 1, mark: mark(sent))}));
      expect(marks.of(sent).look, NoteSyncLook.none);
      expect(marks.of(edited(sent, '# Plan\n\nmore words', 2)).look, NoteSyncLook.waiting);
      expect(marks.of(note('b', 'never sent')).look, NoteSyncLook.waiting, reason: 'a note the account has never had');
      expect(marks.of(note('c', '   ')).look, NoteSyncLook.none, reason: 'opened and left empty: not a note yet');
    });

    test('nothing at all signed out, with Local only, before the first pass, or live with another device', () {
      final changed = note('a', 'words');
      expect(marks.of(changed).look, NoteSyncLook.none, reason: 'no pass has told the marks anything yet');
      marks.account(SyncState());
      expect(marks.of(changed).look, NoteSyncLook.waiting);
      marks.live = (id) => id == 'a';
      expect(marks.of(changed).look, NoteSyncLook.none, reason: 'its words go a keystroke at a time');
      marks.live = (_) => false;
      marks.syncing = () => false;
      expect(marks.of(changed).look, NoteSyncLook.none);
    });

    test('a tick for a moment as it goes, then nothing; an arrow over the tick for a change since', () {
      final one = note('a', 'words', updatedAt: 1);
      marks.account(SyncState(notes: {'a': NoteMark(rev: 1, mark: mark(one))}));
      marks.sent('a');
      final tick = marks.of(one);
      expect(tick.look, NoteSyncLook.sent);
      expect(tick.left, marks.tickFor);
      expect(marks.of(edited(one, 'more', 2)).look, NoteSyncLook.waiting, reason: 'changed again since');
      now = now.add(marks.tickFor);
      expect(marks.of(one).look, NoteSyncLook.none);
    });

    test('red, with the reason, until it goes', () {
      final changed = note('a', 'words', updatedAt: 2);
      marks.account(SyncState());
      marks.failed('a', 'That note is too big.');
      expect(marks.of(changed), const NoteSyncMark(NoteSyncLook.failed, reason: 'That note is too big.'));
      marks.sent('a');
      marks.account(SyncState(notes: {'a': NoteMark(rev: 2, mark: mark(changed))}));
      expect(marks.of(changed).look, NoteSyncLook.sent);
    });

    test('a team\'s note: by its channel\'s word, an arrow for a change since it went', () {
      marks.teamNote = (id) => id == 't';
      marks.account(SyncState());
      final team = note('t', 'the team\'s words', updatedAt: 5);
      expect(marks.of(team).look, NoteSyncLook.none, reason: 'the channel has not seen to it since the app started');
      marks.teamSeen('t', 5, went: true);
      expect(marks.of(team).look, NoteSyncLook.sent);
      now = now.add(marks.tickFor);
      expect(marks.of(team).look, NoteSyncLook.none);
      expect(marks.of(edited(team, 'more', 6)).look, NoteSyncLook.waiting);
      marks.failed('t', 'Attic Press: the service is away.');
      expect(marks.of(team).look, NoteSyncLook.failed);
      marks.teamSeen('t', 6);
      expect(marks.of(edited(team, 'more', 6)).look, NoteSyncLook.none);
    });

    test('a file going is said until it has gone, sent or not', () {
      final first = marks.sending(FileKind.image, 'p.png');
      final second = marks.sending(FileKind.image, 'p.png');
      expect(marks.isSending(FileKind.image, 'p.png'), isTrue);
      expect(marks.isSending(FileKind.recording, 'p.png'), isFalse);
      first();
      first();
      expect(marks.isSending(FileKind.image, 'p.png'), isTrue, reason: 'the second is still going');
      second();
      expect(marks.isSending(FileKind.image, 'p.png'), isFalse);
    });
  });

  group('told by the note pass', () {
    test('a note sent is ticked; one refused is red with why, and ticked once it goes', () async {
      final api = await FakeService.start(seed: testAccount);
      var failing = true;
      Future<FetchResponse> fetcher(FetchRequest request) async {
        if (failing && request.method == 'PUT' && request.url.path.endsWith('/notes/b')) return FetchResponse.json(413, {'error': 'That note is too big.'});
        return api.fetcher(request);
      }

      final phone = deviceOf(api, fetcher: fetcher);
      phone.notes['a'] = note('a', 'words a', createdAt: 1, updatedAt: 1);
      phone.notes['b'] = note('b', 'words b', createdAt: 1, updatedAt: 1);
      marks.account(phone.state);
      expect([marks.of(phone.notes['a']!).look, marks.of(phone.notes['b']!).look], [NoteSyncLook.waiting, NoteSyncLook.waiting]);
      await phone.run();
      marks.account(phone.state);
      expect(marks.of(phone.notes['a']!).look, NoteSyncLook.sent);
      expect(marks.of(phone.notes['b']!), const NoteSyncMark(NoteSyncLook.failed, reason: 'That note is too big.'));
      failing = false;
      await phone.run();
      marks.account(phone.state);
      expect(marks.of(phone.notes['b']!).look, NoteSyncLook.sent);
      now = now.add(marks.tickFor);
      expect([marks.of(phone.notes['a']!).look, marks.of(phone.notes['b']!).look], [NoteSyncLook.none, NoteSyncLook.none]);
    });

    test('a picture going is said while it goes', () async {
      final api = await FakeService.start(seed: testAccount);
      final seen = <bool>[];
      late Device phone;
      Future<FetchResponse> fetcher(FetchRequest request) async {
        if (request.method == 'PUT' && request.url.path.contains('/recordings/')) seen.add(marks.isSending(FileKind.image, 'p1.png'));
        return api.fetcher(request);
      }

      phone = deviceOf(api, fetcher: fetcher, pictures: {'p1.png': [1, 2, 3]});
      phone.notes['a'] = note('a', '![](image/p1.png)', createdAt: 1, updatedAt: 1);
      await phone.run();
      expect(seen, contains(true), reason: 'the bar shows while its bytes go');
      expect(marks.isSending(FileKind.image, 'p1.png'), isFalse, reason: 'and goes once they have');
    });
  });
}
