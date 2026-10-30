// Forms from a share link, on the device (lib/forms/form_inbox.dart, docs/FORMS.md), over the service in memory
// (test/support/fake_service.dart, its forms kept by fake_forms.dart) and the fake crypto: a shared form said to the
// service with its note and nothing of where it goes in its share; an answer a visitor's browser sealed opened and
// filed as a ticket in the form's notebook, its answers in the front matter and the body, its picture kept, its line
// in the index, its workspace and the bell told; and each answer filed ONCE across the account's two devices - a
// claim the other device holds passed over, a claim lapsed taken up, a ticket synced already not written twice - and
// one sealed only to a teammate left for them. And the seal the reader makes, opened through the Rust core.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/account/enc_key.dart';
import 'package:ghost_md/core/book.dart' show chaptersOf;
import 'package:ghost_md/core/front_matter.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart' show preferences;
import 'package:ghost_md/forms/form_def.dart';
import 'package:ghost_md/forms/form_inbox.dart';
import 'package:ghost_md/share/share.dart' show readShareLink;

import '../account_ui/support.dart';

const String _library = 'native/target/debug/libghost_core.dylib';

const String notebookBody = '---\nbook: true\nkey: BUG\n---\n# Bug reports\n\n1. [[Report a bug]]\n';
const String formBody = '''# Report a bug

Tell us what went wrong.

```form
to: [[Bug reports]]
ticket: Bug: {Summary}
template: Bug report
- Summary: short, required
- What happened: long, required
- How bad: choice (Annoying | Blocking)
- Your email: email
- Screenshot: file
```
''';

/// A device's forms step, against the service it was made with: its own notes, files and memory, the account's pair,
/// a workspace for every note the test says, and the bell's calls kept.
class Pass {
  Pass(this.device, {this.spaces = const {}});
  final Device device;
  final Map<String, String> spaces;
  final Map<String, String> filed = {};
  final List<String> told = [];

  Future<KeptEncryptionKey> key() async => ensureEncryptionKey(EncryptionKeyContext(token: device.account.session!.token, accountKey: (await device.account.accountKey())!, keys: device.keys, api: device.api, crypto: device.service.crypto));

  FormPassContext get ctx => FormPassContext(
        token: device.account.session!.token,
        api: device.api,
        crypto: device.service.crypto,
        pair: () async => (await key()).pair,
        notes: device.notes,
        files: device.files,
        now: () => 1792275600000,
        prefs: () => preferences.value,
        kept: device.kept,
        workspaceOf: (id) => spaces[id],
        orgOf: (space) => space == 'team-space' ? 'org-1' : null,
        fileNote: (id, space) => filed[id] = space,
        told: (id, title, form) async => told.add('$title from $form'),
      );

  Future<int> run() => syncForms(ctx);
}

/// The ticket notes a device holds.
List<Note> tickets(Device device) => [for (final note in device.notes.held.values) if (frontMatterValue(note.body, 'via') == 'form') note];

void main() {
  late Device phone, mac;
  late String formId, pub;

  Future<Device> withNotes(Device device) async {
    device.keep('book', notebookBody);
    device.keep('form', formBody);
    return device;
  }

  setUp(() async {
    phone = await withNotes(await Device.make(engine: false));
    mac = await withNotes(await Device.make(service: phone.service, engine: false));
    // The phone shares the form: what goes is its public part alone.
    final link = await phone.shares!.shareNote(phone.notes.held['form']!, phone.notes.held.values.toList());
    formId = readShareLink(link)!.id;
    pub = (await Pass(phone).key()).pub;
  });

  Future<void> answered(String id, Map<String, Object?> answers, {List<String>? to, Map<String, Object?>? file}) => phone.service.forms.answer(
        phone.service.crypto,
        form: formId,
        id: id,
        keys: to ?? [pub],
        payload: {
          'v': 1,
          'answers': [for (final MapEntry(:key, :value) in answers.entries) [key, value]],
          'file': ?file,
          'at': 1792275541000,
        },
        at: 1792275541000,
      );

  test('a shared form is said to the service with its note, and its share carries nothing of where it goes', () async {
    final shared = await phone.shares!.readShared(phone.shares!.linkFor('form')!);
    expect(shared.pages.single.body, isNot(contains('Bug reports')));
    expect(shared.pages.single.body, isNot(contains('ticket:')));
    expect(formOf(shared.pages.single.body)!.fields, hasLength(5));
    expect(await Pass(phone).run(), 0);
    final form = phone.service.forms.forms[formId]!;
    expect((form.note, form.org, form.files, form.state), ('form', null, true, 'open'));
    // Said once: a second pass with nothing changed says nothing.
    phone.service.calls.clear();
    await Pass(phone).run();
    expect(phone.service.calls.where((call) => call.startsWith('PUT forms')), isEmpty);
    // A form whose notebook is a team's is the team's to file.
    phone.kept.write('glyph-forms-said', null);
    await Pass(phone, spaces: {'book': 'team-space'}).run();
    expect(form.org, 'org-1');
  });

  test('an answer is opened and filed as a ticket in the form’s notebook, its answers and its picture with it', () async {
    await Pass(phone).run();
    final png = base64Url.encode([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]).replaceAll('=', '');
    await answered('answer-0000000000000001', {'Summary': 'Crash on launch', 'What happened': 'It closes at once.', 'How bad': 'Blocking', 'Your email': 'ana@example.com'}, file: {'field': 'Screenshot', 'name': 'shot.png', 'type': 'image/png', 'data': png});
    final pass = Pass(phone, spaces: {'book': 'work'});
    expect(await pass.run(), 1);
    final ticket = phone.notes.held[formTicketId('answer-0000000000000001')]!;
    expect(noteTitleOf(ticket), 'Bug: Crash on launch');
    expect((frontMatterValue(ticket.body, 'type'), frontMatterValue(ticket.body, 'id'), frontMatterValue(ticket.body, 'status')), ('ticket', 'BUG-1', 'To do'));
    expect((frontMatterValue(ticket.body, 'via'), frontMatterValue(ticket.body, 'form'), frontMatterValue(ticket.body, 'email'), frontMatterValue(ticket.body, 'how-bad')), ('form', '[[Report a bug]]', 'ana@example.com', 'Blocking'));
    // The ticket template the form names, filled, and the answers under it.
    expect(ticket.body, contains('## Steps to reproduce'));
    expect(ticket.body, contains('## What happened\n\nIt closes at once.\n'));
    final picture = formFileName('answer-0000000000000001', 'png');
    expect(ticket.body, contains('![shot.png](image/$picture)'));
    expect(phone.files.pictures[picture], [0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);
    expect(ticket.createdAt, 1792275541000);
    // In the notebook's index, in its workspace, and the bell told.
    expect(chaptersOf(phone.notes.held['book']!.body).map((c) => c.title), ['Report a bug', 'Bug: Crash on launch']);
    expect(pass.filed, {ticket.id: 'work'});
    expect(pass.told, ['Bug: Crash on launch from Report a bug']);
    // Filed: gone from the service, and counted.
    expect(phone.service.forms.inbox, isEmpty);
    expect(phone.service.forms.forms[formId]!.filed, 1);
    // A second answer of the same summary takes the next key and a title of its own.
    await answered('answer-0000000000000002', {'Summary': 'Crash on launch', 'What happened': 'Again.'});
    expect(await Pass(phone).run(), 1);
    final second = phone.notes.held[formTicketId('answer-0000000000000002')]!;
    expect((noteTitleOf(second), frontMatterValue(second.body, 'id')), ('Bug: Crash on launch (2)', 'BUG-2'));
  });

  test('both devices at once file an answer once: the claim keeps it to one of them', () async {
    await Pass(phone).run();
    await answered('answer-0000000000000003', {'Summary': 'Slow sync', 'What happened': 'Minutes.'});
    final made = await Future.wait([Pass(phone).run(), Pass(mac).run()]);
    expect(made.reduce((a, b) => a + b), 1);
    expect(tickets(phone).length + tickets(mac).length, 1);
    expect(phone.service.forms.claims, hasLength(1), reason: 'the second device was refused its claim');
    expect(phone.service.forms.acks, ['answer-0000000000000003']);
    // And neither files it again on its next pass.
    expect(await Pass(phone).run() + await Pass(mac).run(), 0);
  });

  test('a claim the phone left is the Mac’s once it lapses; a ticket that reached the Mac is not written again', () async {
    await Pass(phone).run();
    await answered('answer-0000000000000004', {'Summary': 'Lost a note', 'What happened': 'Gone.'});
    // The phone claims it, and stops before it files it.
    await phone.api.call('POST', 'forms/inbox/answer-0000000000000004/claim', token: phone.account.session!.token, body: {'device': formDevice(phone.kept, phone.service.crypto)});
    expect(await Pass(mac).run(), 0, reason: 'the phone holds it');
    expect(tickets(mac), isEmpty);
    phone.service.clock = () => DateTime.now().millisecondsSinceEpoch + 121000;
    phone.service.forms.claimFor = 120000;
    expect(await Pass(mac).run(), 1, reason: 'the claim lapsed');
    expect(tickets(mac).single.id, formTicketId('answer-0000000000000004'));

    // Filed on the phone, its ticket synced to the Mac, the ack lost: the Mac only tells the service.
    await answered('answer-0000000000000005', {'Summary': 'Typo', 'What happened': 'Teh.'});
    final synced = Note(id: formTicketId('answer-0000000000000005'), body: '---\ntype: ticket\nvia: form\n---\n# Typo\n', createdAt: 1, updatedAt: 1);
    mac.notes.held[synced.id] = synced;
    expect(await Pass(mac).run(), 0);
    expect(mac.notes.held[synced.id], same(synced), reason: 'not written again');
    expect(phone.service.forms.inbox, isEmpty, reason: 'and the service told it is filed');
  });

  test('an answer sealed only to a teammate is theirs to file, unclaimed; an older service is quiet', () async {
    await Pass(phone).run();
    final teammate = await phone.service.crypto.encryptionPublicKeyOf(await phone.service.crypto.newEncryptionKey());
    await answered('answer-0000000000000006', {'Summary': 'For Sam'}, to: [teammate]);
    expect(await Pass(phone).run(), 0);
    expect(phone.service.forms.claims, isEmpty);
    expect(phone.service.forms.inbox, hasLength(1));
    phone.service.forms.routes = false;
    expect(await Pass(phone).run(), 0);
  });

  group('the reader’s seal, through the core', () {
    final built = File(_library).existsSync();
    final skip = built ? null : 'the Mac\'s core is not built: run tool/build-native.sh host (wanted $_library)';
    test('an answer tauri/src/read/form.ts sealed opens with the fixture’s key into its answers', () async {
      final core = await GhostCore.open(libraryPath: File(_library).absolute.path);
      addTearDown(core.close);
      final AccountCrypto crypto = CoreCrypto(core.invoke);
      final fixture = (jsonDecode(File('tauri/src/read/formSeal.fixture.json').readAsStringSync()) as Map).cast<String, Object?>();
      final pair = await crypto.importEncryptionKey((fixture['jwk'] as Map).cast<String, Object?>());
      final sealed = (fixture['sealed'] as Map).cast<String, Object?>();
      final answer = await openFormAnswer(crypto, pair, form: fixture['form'] as String, answer: fixture['answer'] as String, mine: fixture['public'] as String, wraps: sealed['wraps'] as List, blob: sealed['blob'] as String);
      expect(answer.answers, [('Summary', 'Crash on launch ✓, “quoted”'), ('What happened', 'It closes\nat once.')]);
    }, skip: skip);
  });
}

String noteTitleOf(Note note) => RegExp(r'^# (.*)$', multiLine: true).firstMatch(note.body)!.group(1)!;
