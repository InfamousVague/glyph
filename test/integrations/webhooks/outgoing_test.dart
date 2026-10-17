// Outgoing webhooks (lib/integrations/webhooks/outgoing.dart, docs/INTEGRATIONS.md §1): a run of saves of one note is
// one POST, 10 seconds after the last, with the lines it changed; each hook hears only its scope and its events;
// signed with its secret; a failure tried three times more and then said; nothing with Local only on; and only what
// this device changed (CoreLibrary.savedHere), never a note written as another device has it. On the test's clock.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/core_library.dart' show SavedHere;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/integrations/webhooks/outgoing.dart';
import 'package:ghost_md/integrations/webhooks/payload.dart';
import 'package:ghost_md/integrations/webhooks/setup.dart';

import '../../library/support.dart';

Note note(String id, String body, {int at = 1}) => Note(id: id, body: body, createdAt: 1, updatedAt: at);

void main() {
  late PreferencesStore prefs;
  late List<FetchRequest> sent;
  late List<int> answers;
  late List<Duration> waited;
  late WebhookSender sender;

  WebhookSender make({List<Note> Function()? notes}) {
    final kept = MemoryStored();
    sender = WebhookSender(
      prefs: prefs,
      kept: () => kept,
      on: () => true,
      clock: () => DateTime.utc(2026, 10, 17, 18).millisecondsSinceEpoch,
      wait: (time) async => waited.add(time),
      fetch: (request) async {
        sent.add(request);
        final status = answers.isEmpty ? 200 : answers.removeAt(0);
        if (status == 0) throw const SocketLike();
        return FetchResponse(status);
      },
    );
    final controller = StreamController<SavedHere>.broadcast(sync: true);
    sender.start(saves: controller.stream, notes: notes);
    addTearDown(controller.close);
    addTearDown(sender.dispose);
    return sender;
  }

  Map<String, Object?> bodyOf(FetchRequest request) => (jsonDecode(request.text) as Map).cast<String, Object?>();

  setUp(() {
    prefs = PreferencesStore()..startWithoutStorage();
    sent = [];
    answers = [];
    waited = [];
  });

  testWidgets('a run of typing is one call, 10 seconds after the last save, with the lines the run changed', (tester) async {
    make().add('https://hooks.test/in', events: {WebhookEvent.edited});
    const before = '# Baby\n\n- [ ] Buy a crib\n- [ ] Paint';
    sender.heard(note('n1', before), note('n1', '# Baby\n\n- [ ] Buy a crib\n- [ ] Paint the'));
    await tester.pump(const Duration(seconds: 6));
    sender.heard(note('n1', '# Baby\n\n- [ ] Buy a crib\n- [ ] Paint the'), note('n1', '# Baby\n\n- [ ] Buy a crib\n- [ ] Paint the room'));
    await tester.pump(const Duration(seconds: 9));
    expect(sent, isEmpty, reason: 'still within 10 seconds of the last save');
    await tester.pump(const Duration(seconds: 1));
    expect(sent, hasLength(1));
    final request = sent.single;
    expect((request.method, request.url.toString(), request.headers['Content-Type']), ('POST', 'https://hooks.test/in', 'application/json'));
    expect(request.headers.containsKey(signatureHeader), isFalse, reason: 'no secret, no signature');
    final body = bodyOf(request);
    expect(body['event'], 'note.edited');
    expect(body['at'], '2026-10-17T18:00:00Z');
    expect((body['note'] as Map)['changed'], ['- [ ] Paint the room']);
    expect((body['note'] as Map)['title'], 'Baby');
    expect(sender.statusOf(sender.setup.outgoing.single.id)?.problem, isNull);
  });

  testWidgets('a note saved without a break is sent a minute after its first save all the same', (tester) async {
    make().add('https://hooks.test/in', events: {WebhookEvent.edited});
    var body = 'start';
    for (var i = 0; i < 13; i += 1) {
      final next = '$body $i';
      sender.heard(note('n1', body), note('n1', next));
      body = next;
      await tester.pump(const Duration(seconds: 5));
    }
    expect(sent, hasLength(1));
    sender.stop();
  });

  testWidgets('two notes are two calls; a new note is note.created, and a blank one waits for its words', (tester) async {
    make().add('https://hooks.test/in', events: {WebhookEvent.created, WebhookEvent.edited});
    sender.heard(null, note('a', ''));
    sender.heard(note('b', 'old'), note('b', 'new'));
    await tester.pump(quietFor);
    expect([for (final r in sent) bodyOf(r)['event']], ['note.edited']);
    sender.heard(note('a', ''), note('a', '# Fresh'));
    await tester.pump(quietFor);
    expect([for (final r in sent) bodyOf(r)['event']], ['note.edited', 'note.created']);
    expect((bodyOf(sent.last)['note'] as Map)['changed'], ['# Fresh']);
  });

  testWidgets('a ticked to-do is todo.done to a hook that asks for it, and edited to one that does not', (tester) async {
    make()
      ..add('https://done.test/', events: {WebhookEvent.todoDone}, id: 'done')
      ..add('https://edits.test/', events: {WebhookEvent.edited}, id: 'edits')
      ..add('https://made.test/', events: {WebhookEvent.created}, id: 'made');
    sender.heard(note('n', '- [ ] Buy a crib'), note('n', '- [x] Buy a crib'));
    await tester.pump(quietFor);
    expect({for (final r in sent) r.url.host: bodyOf(r)['event']}, {'done.test': 'todo.done', 'edits.test': 'note.edited'});
  });

  testWidgets('each hook hears its own scope: a workspace, a notebook, a tag', (tester) async {
    prefs.update((now) => now.copyWith(workspaces: KeptWorkspaces.fromJson({'list': [{'id': 'w-fam', 'name': 'Family'}], 'notes': {'in-fam': 'w-fam'}})));
    final book = note('book', '---\nbook: true\n---\n# Trip\n\n- [[Packing]]');
    final page = note('page', '# Packing\n\nsocks');
    make(notes: () => [book, page])
      ..add('https://space.test/', events: {WebhookEvent.edited}, scope: const WebhookScope(ScopeKind.workspace, 'w-fam'), id: 's')
      ..add('https://book.test/', events: {WebhookEvent.edited}, scope: const WebhookScope(ScopeKind.notebook, 'book'), id: 'b')
      ..add('https://tag.test/', events: {WebhookEvent.edited}, scope: const WebhookScope(ScopeKind.tag, 'work'), id: 't');
    sender.heard(note('in-fam', 'a'), note('in-fam', 'b'));
    sender.heard(note('page', '# Packing\n\nsocks'), note('page', '# Packing\n\nsocks\nhat'));
    sender.heard(note('tagged', 'x'), note('tagged', 'x #Work/clients #work'));
    sender.heard(note('other', 'x'), note('other', 'y #workshop'));
    await tester.pump(quietFor);
    expect({for (final r in sent) '${r.url.host} ${(bodyOf(r)['note'] as Map)['id']}'}, {'space.test in-fam', 'book.test page', 'tag.test tagged'});
    expect((bodyOf(sent.firstWhere((r) => r.url.host == 'space.test'))['note'] as Map)['workspace'], 'Family');
  });

  testWidgets('a secret signs the very bytes sent', (tester) async {
    make().add('https://hooks.test/in', events: {WebhookEvent.edited}, secret: 'shh');
    sender.heard(note('n', 'a'), note('n', 'b'));
    await tester.pump(quietFor);
    expect(sent.single.headers[signatureHeader], signatureOf('shh', sent.single.body!));
  });

  testWidgets('a failure is tried three times more, waiting longer each time, and then said in the pane', (tester) async {
    make().add('https://hooks.test/in', events: {WebhookEvent.edited}, id: 'h');
    answers = [500, 0, 503];
    sender.heard(note('n', 'a'), note('n', 'b'));
    await tester.pump(quietFor);
    await tester.pump();
    expect(sent, hasLength(4));
    expect(waited, retryWaits);
    expect(sender.statusOf('h')?.problem, isNull, reason: 'the fourth went');

    sent.clear();
    waited.clear();
    answers = [500, 500, 500, 404];
    sender.heard(note('n', 'b'), note('n', 'c'));
    await tester.pump(quietFor);
    await tester.pump();
    expect(sent, hasLength(4));
    expect(sender.statusOf('h')?.problem, 'The URL answered 404.');
  });

  testWidgets('nothing is sent with Local only on, when the note is saved or when its send is due', (tester) async {
    make().add('https://hooks.test/in', events: {WebhookEvent.edited});
    prefs.update((now) => now.copyWith(localOnly: true));
    sender.heard(note('n', 'a'), note('n', 'b'));
    await tester.pump(quietFor);
    expect(sent, isEmpty);
    prefs.update((now) => now.copyWith(localOnly: false));
    sender.heard(note('n', 'b'), note('n', 'c'));
    prefs.update((now) => now.copyWith(localOnly: true));
    await tester.pump(quietFor);
    expect(sent, isEmpty);
    expect(await sender.sendTest(sender.setup.outgoing.single.id), 'Nothing is sent while Local only is on.');
  });

  test('only what this device changed is heard: a note written as another device has it is not', () async {
    final it = libraryOver();
    final kept = MemoryStored();
    sender = WebhookSender(prefs: prefs, kept: () => kept, on: () => true, wait: (_) async {}, fetch: (request) async {
      sent.add(request);
      return FetchResponse(200);
    });
    addTearDown(sender.dispose);
    sender.start(saves: it.library.savedHere);
    sender.add('https://hooks.test/in', events: {WebhookEvent.created, WebhookEvent.edited});
    await it.library.createNote('# Mine', id: 'a');
    await it.library.apply(const Note(id: 'b', body: '# Theirs', createdAt: 1, updatedAt: 2));
    await it.library.apply(const Note(id: 'a', body: '# Mine\n\nfrom another device', createdAt: 1, updatedAt: 3, revision: 2));
    await Future<void>.delayed(Duration.zero);
    await sender.flush();
    expect([for (final r in sent) (bodyOf(r)['event'], (bodyOf(r)['note'] as Map)['id'])], [('note.created', 'a')]);
    await it.library.update('a', '# Mine\n\nfrom another device\n\nand from me', 2);
    await Future<void>.delayed(Duration.zero);
    await sender.flush();
    expect((bodyOf(sent.last)['note'] as Map)['changed'], ['and from me']);
  });

  testWidgets('a hook is added, checked, and removed', (tester) async {
    make();
    expect(sender.add('http://example.com', events: {WebhookEvent.edited}), contains('secure'));
    expect(sender.add('https://x.test', events: const {}), 'Choose at least one thing to be told of.');
    expect(sender.add('https://x.test', events: {WebhookEvent.edited}, scope: const WebhookScope(ScopeKind.workspace, null)), 'Choose which notes.');
    expect(sender.add('https://x.test/in', events: {WebhookEvent.edited}, secret: '  ', id: 'h'), isNull);
    expect(sender.setup.outgoing.single.secret, isNull);
    expect(prefs.value.toJson()[webhooksKey], isA<Map<String, Object?>>(), reason: 'kept with the settings that travel');
    expect(await sender.sendTest('h'), isNull);
    expect(sender.statusOf('h')?.event, 'note.edited');
    sender.remove('h');
    expect(sender.setup.outgoing, isEmpty);
    expect(sender.statusOf('h'), isNull);
    expect(prefs.value.toJson().containsKey(webhooksKey), isFalse);
  });
}

/// No answer at all, as a socket that would not connect.
class SocketLike implements Exception {
  const SocketLike();
}
