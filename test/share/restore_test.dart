// A share survives a restore (lib/share/share.dart, "a share survives a restore"; docs/MARKDOWN_FIRST.md §11 decision
// 8, Matt 2026-10-31): a share made here seals what the device knows of it under the account key beside the blob on
// the service, and the note says `share: <id>` in its page front matter; a device with no settings that signs in gets
// every share back at the same link; a share whose note's id changed is found by its marker; stopping a share takes
// the meta down with it and the marker off the note; the marker never reaches a reader; and against a service that
// knows no meta the settings' entry is enough, as before. Over the service in memory and the fake crypto.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/front_matter.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/share/share.dart';

import 'support.dart';

/// A device: its notes, its settings, its account, and its shares over the service; [save] writes a note's words as
/// the library would.
class Here {
  Here(this.service, {Fetcher? fetcher, bool marker = true}) {
    prefs.startWithoutStorage();
    account = SignedAccount();
    shares = Shares(
      account: account,
      api: apiOf(service, fetcher),
      crypto: service.crypto,
      prefs: prefs,
      pictures: Pictures(),
      listNotes: () async => notes.values.toList(),
      save: marker
          ? (note, body) async {
              saves.add(note.id);
              notes[note.id] = note.copyWith(body: body);
            }
          : null,
    );
  }

  final FakeService service;
  final PreferencesStore prefs = PreferencesStore();
  final Map<String, Note> notes = {};
  final List<String> saves = [];
  late final SignedAccount account;
  late final Shares shares;

  Note keep(String id, String body) => notes[id] = Note(id: id, body: body, createdAt: 0, updatedAt: 0);

  /// Signs in, and lets what sign-in starts (the restore, and the shares written again) finish.
  Future<void> signIn() async {
    account.signIn(service);
    await shares.settled;
  }

  /// Every meta written to the service, in order.
  List<String> get metaPuts => [for (final call in service.calls) if (call.startsWith('PUT shares/') && call.endsWith('/meta')) call];
}

void main() {
  late FakeService service;

  setUp(() async {
    service = await FakeService.start(seed: testAccount);
  });

  test('a share made here seals its meta beside the blob, and the note says it is shared', () async {
    final here = Here(service);
    await here.signIn();
    final note = here.keep('n1', '# Orders\n\nTwo crates.');
    final link = await here.shares.shareNote(note, here.notes.values.toList());
    final found = readShareLink(link)!;
    final kept = service.shares[found.id]!;
    expect(kept.meta, isNotNull);
    expect(kept.meta, isNot(contains(found.key)), reason: 'sealed: the service holds the key only under the account key');
    final opened = await service.crypto.open(service.accountKey, kept.meta!, shareMetaContext(found.id));
    expect(opened, {'v': 1, 'noteId': 'n1', 'key': found.key});
    // The marker: the id in the page's front matter, never the key.
    expect(here.saves, ['n1']);
    expect(frontMatterValue(here.notes['n1']!.body, 'share'), found.id);
    expect(here.notes['n1']!.body, isNot(contains(found.key)));
    expect(shareMarkerOf(here.notes['n1']!.body), found.id);
    // And the marker is not in what a reader opens.
    final read = await here.shares.readShared(link);
    expect(read.pages.single.body, '# Orders\n\nTwo crates.');
    // Shared again with the marker in place, the share is unchanged: nothing goes.
    expect(await here.shares.refreshShares(), 0);
    expect(here.metaPuts, hasLength(1), reason: 'the meta goes once per change');
  });

  test('a device with no settings that signs in has its shares back at the same links, from the metas', () async {
    final phone = Here(service);
    await phone.signIn();
    final a = phone.keep('a', '# A\n\nWords.');
    final b = phone.keep('b', '# B\n\nMore.');
    final linkA = await phone.shares.shareNote(a, phone.notes.values.toList());
    final linkB = await phone.shares.shareNote(b, phone.notes.values.toList());
    await phone.shares.shareWithPlace('b', on: true);
    await phone.shares.shareWithPlaces('b', on: true);
    expect(phone.metaPuts.where((call) => call.contains(readShareLink(linkB)!.id)), hasLength(3), reason: 'the meta goes again with each switch');
    expect(phone.prefs.value.shares.keys, unorderedEquals(['a', 'b']));

    // The settings are gone (a restore from a repository, a wiped device): a fresh device, the notes back from the files.
    final mac = Here(service);
    for (final note in phone.notes.values) {
      mac.keep(note.id, note.body);
    }
    expect(mac.prefs.value.shares, isEmpty);
    await mac.signIn();
    expect(mac.prefs.value.shares.keys, unorderedEquals(['a', 'b']));
    expect(mac.shares.linkFor('a'), linkA);
    expect(mac.shares.linkFor('b'), linkB);
    expect((mac.shares.sharingPlace('b'), mac.shares.sharingPlaces('b'), mac.shares.sharingRecording('b')), (true, true, true), reason: 'the switches come back as they were');
    expect(mac.saves, isEmpty, reason: 'the notes already carried their markers');
    expect(service.calls.where((call) => call == 'PUT shares/${readShareLink(linkA)!.id}'), hasLength(2), reason: 'what came back was shared again as the Mac reads it');
    // Shared again from the Mac, the links still read.
    final edited = mac.keep('a', '---\nshare: ${readShareLink(linkA)!.id}\n---\n# A\n\nWords, edited.');
    expect(await mac.shares.refreshShares(), 1);
    expect((await mac.shares.readShared(linkA)).pages.single.body, '# A\n\nWords, edited.');
    expect(edited.body, contains('share:'));
  });

  test('a restored note whose id changed is found by its marker, and marked where it had none', () async {
    final phone = Here(service);
    await phone.signIn();
    final note = phone.keep('old-id', '# Trip');
    final link = await phone.shares.shareNote(note, phone.notes.values.toList());
    final id = readShareLink(link)!.id;
    final other = phone.keep('plain', '# Plain');
    final otherLink = await phone.shares.shareNote(other, phone.notes.values.toList());

    final mac = Here(service);
    // The file came back under a new id, its marker with it; the other note's marker was lost on the way.
    mac.keep('new-id', phone.notes['old-id']!.body);
    mac.keep('plain', '# Plain');
    await mac.signIn();
    expect(mac.prefs.value.shares.keys, unorderedEquals(['new-id', 'plain']));
    expect(mac.shares.linkFor('new-id'), link);
    expect(mac.shares.linkFor('plain'), otherLink);
    expect(mac.saves, ['plain'], reason: 'the marker written back where it was missing');
    expect(shareMarkerOf(mac.notes['plain']!.body), readShareLink(otherLink)!.id);
    expect(shareMarkerOf(mac.notes['new-id']!.body), id);
  });

  test('a share from an older build gets its meta at the next refresh, and the settings\' entry wins where both have one', () async {
    final here = Here(service);
    await here.signIn();
    // An entry as the settings carried it before there were metas: on the service, a blob and nothing beside it.
    final key = newShareKey(service.crypto);
    const id = 'OlderBuildShare0000000';
    service.shares[id] = (blob: 'eA', created: 1, updated: 1, meta: null);
    here.prefs.update((p) => p.copyWith(shares: {'n': ShareEntry(id: id, key: key)}));
    here.keep('n', '# N');
    await here.shares.refreshShares();
    expect(service.shares[id]!.meta, isNotNull, reason: 'the meta written through for an old share');
    expect(await service.crypto.open(service.accountKey, service.shares[id]!.meta!, shareMetaContext(id)), {'v': 1, 'noteId': 'n', 'key': key});
    // A second device that already lists the note under another share keeps its own.
    final mac = Here(service);
    mac.keep('n', '# N');
    mac.prefs.update((p) => p.copyWith(shares: {'n': ShareEntry(id: 'MacsOwnShareOfTheNote0', key: newShareKey(service.crypto))}));
    await mac.signIn();
    expect(mac.prefs.value.shares['n']!.id, 'MacsOwnShareOfTheNote0');
  });

  test('stopping a share takes the meta down with it and the marker off the note', () async {
    final here = Here(service);
    await here.signIn();
    final note = here.keep('n', '# N\n\nWords.');
    final link = await here.shares.shareNote(note, here.notes.values.toList());
    final id = readShareLink(link)!.id;
    expect(service.shares[id]!.meta, isNotNull);
    await here.shares.stopSharing('n');
    expect(service.shares.containsKey(id), isFalse);
    expect(here.notes['n']!.body, '# N\n\nWords.');
    expect(here.saves, ['n', 'n']);
    // Signing in again finds nothing to put back.
    final mac = Here(service);
    mac.keep('n', '# N\n\nWords.');
    await mac.signIn();
    expect(mac.prefs.value.shares, isEmpty);
  });

  test('a meta the device cannot open is passed over, and a service that knows no meta leaves the settings\' entry enough', () async {
    // A meta sealed by a newer app, or not this account's.
    service.shares['FromANewerApp000000000'] = (blob: 'eA', created: 1, updated: 1, meta: 'bm90IHNlYWxlZA');
    final here = Here(service);
    await here.signIn();
    expect(here.prefs.value.shares, isEmpty);
    // An older service: 404 to every meta write. The share still goes, and the link still reads.
    final old = Here(service, fetcher: (request) async {
      if (request.url.path.endsWith('/meta')) return FetchResponse.json(404, {'error': 'Not found.'});
      return service.fetcher(request);
    });
    await old.signIn();
    final note = old.keep('n', '# N');
    final link = await old.shares.shareNote(note, old.notes.values.toList());
    expect(old.prefs.value.shares['n']!.id, readShareLink(link)!.id);
    expect(service.shares[readShareLink(link)!.id]!.meta, isNull);
    expect((await old.shares.readShared(link)).pages.single.body, '# N');
    expect(shareMarkerOf(old.notes['n']!.body), readShareLink(link)!.id, reason: 'the marker is the file\'s, whatever the service knows');
  });

  test('the meta carries the switches and the recording\'s descriptor, and reads back as an entry', () {
    const entry = ShareEntry(id: 'AbCdEfGhIjKlMnOpQrStUv', key: 'k', place: true, recording: false, audio: {'upload': 'u', 'parts': 3});
    final meta = shareMetaOf('n', entry);
    expect(meta, {'v': 1, 'noteId': 'n', 'key': 'k', 'place': true, 'recording': false, 'audio': {'upload': 'u', 'parts': 3}});
    expect(shareEntryOfMeta('AbCdEfGhIjKlMnOpQrStUv', meta), isNull, reason: 'a key a link could not carry is not one');
    final key = 'K' * 43;
    final read = shareEntryOfMeta('AbCdEfGhIjKlMnOpQrStUv', {...meta, 'key': key})!;
    expect(read.noteId, 'n');
    expect((read.entry.id, read.entry.key, read.entry.place, read.entry.places, read.entry.recording), ('AbCdEfGhIjKlMnOpQrStUv', key, true, false, false));
    expect(read.entry.audio, {'upload': 'u', 'parts': 3});
    expect(shareEntryOfMeta('x', {'v': 2, 'noteId': 'n', 'key': key}), isNull, reason: 'a newer shape is passed over');
    expect(jsonEncode(meta), isNot(contains('sent')), reason: 'what was last sent is this device\'s own');
  });
}
